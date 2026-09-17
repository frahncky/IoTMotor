#pragma once
// MQTT sobre WebSocket (ws://) para redes que bloqueiam as portas 1883/8883,
// como a IFMA_IOT. Implementa a interface Client do Arduino, entao o
// PubSubClient continua igual: basta usar esta classe no lugar do WiFiClient.
// Mantenha este arquivo identico nas pastas dos dois firmwares.
#include <Arduino.h>
#include <Client.h>
#include <WiFiClient.h>
#include <base64.h>
#include <esp_random.h>

class MqttWebSocketClient : public Client {
 public:
  explicit MqttWebSocketClient(const char* caminho = "/mqtt") : _caminho(caminho) {}

  int connect(IPAddress ip, uint16_t porta) override {
    return connect(ip.toString().c_str(), porta);
  }

  int connect(const char* host, uint16_t porta) override {
    stop();
    if (!_tcp.connect(host, porta, 6000)) return 0;
    uint8_t chave[16];
    esp_fill_random(chave, sizeof(chave));
    _tcp.printf("GET %s HTTP/1.1\r\nHost: %s:%u\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: mqtt\r\n\r\n",
                _caminho, host, porta, base64::encode(chave, sizeof(chave)).c_str());
    // Le o cabecalho HTTP ate a linha em branco; exige "101 Switching Protocols".
    char linha[160];
    size_t n = 0;
    bool primeira = true, aceito = false;
    const unsigned long inicio = millis();
    while (millis() - inicio < 6000) {
      if (_tcp.available() <= 0) {
        if (!_tcp.connected()) break;
        delay(5);
        continue;
      }
      const char c = static_cast<char>(_tcp.read());
      if (c == '\r') continue;
      if (c != '\n') {
        if (n < sizeof(linha) - 1) linha[n++] = c;
        continue;
      }
      linha[n] = '\0';
      if (primeira) {
        aceito = !strncmp(linha, "HTTP/1.1 101", 12);
        primeira = false;
      } else if (n == 0) {
        if (!aceito) break;
        _aberto = true;
        return 1;
      }
      n = 0;
    }
    stop();
    return 0;
  }

  size_t write(uint8_t b) override { return write(&b, 1); }
  size_t write(const uint8_t* buf, size_t tamanho) override {
    return enviarQuadro(0x82, buf, tamanho);  // FIN + binario
  }

  int available() override {
    bombear();
    return static_cast<int>(_rxFim - _rxIni);
  }
  int read() override {
    bombear();
    return _rxIni < _rxFim ? _rx[_rxIni++] : -1;
  }
  int read(uint8_t* buf, size_t tamanho) override {
    bombear();
    const size_t m = min(tamanho, _rxFim - _rxIni);
    memcpy(buf, _rx + _rxIni, m);
    _rxIni += m;
    return static_cast<int>(m);
  }
  int peek() override {
    bombear();
    return _rxIni < _rxFim ? _rx[_rxIni] : -1;
  }
  // WiFiClient::flush() descarta a recepcao; aqui nao ha nada a esvaziar.
  void flush() override {}
  void stop() override {
    _tcp.stop();
    _aberto = false;
    _rxIni = _rxFim = 0;
    _cabLen = 0;
    _resta = 0;
    _ctrlLen = 0;
  }
  uint8_t connected() override { return (_rxIni < _rxFim) || (_aberto && _tcp.connected()); }
  operator bool() override { return connected(); }

 private:
  size_t enviarQuadro(uint8_t primeiro, const uint8_t* buf, size_t tamanho) {
    if (!_aberto || tamanho > 0xFFFF) return 0;
    uint8_t cab[8];
    size_t h = 0;
    cab[h++] = primeiro;
    if (tamanho < 126) {
      cab[h++] = 0x80 | static_cast<uint8_t>(tamanho);
    } else {
      cab[h++] = 0x80 | 126;
      cab[h++] = static_cast<uint8_t>(tamanho >> 8);
      cab[h++] = static_cast<uint8_t>(tamanho);
    }
    uint8_t mascara[4];  // O cliente sempre mascara (RFC 6455).
    esp_fill_random(mascara, sizeof(mascara));
    memcpy(cab + h, mascara, 4);
    h += 4;
    if (_tcp.write(cab, h) != h) return 0;
    uint8_t bloco[256];
    for (size_t i = 0; i < tamanho;) {
      const size_t m = min(tamanho - i, sizeof(bloco));
      for (size_t j = 0; j < m; ++j) bloco[j] = buf[i + j] ^ mascara[(i + j) & 3];
      if (_tcp.write(bloco, m) != m) return 0;
      i += m;
    }
    return tamanho;
  }

  // Le o cabecalho do proximo quadro; false se ainda estiver incompleto.
  bool lerCabecalho() {
    for (;;) {
      size_t precisa = 2;
      if (_cabLen >= 2) {
        const uint8_t l = _cab[1] & 0x7F;
        precisa += (l == 126 ? 2 : l == 127 ? 8 : 0) + ((_cab[1] & 0x80) ? 4 : 0);
      }
      if (_cabLen >= precisa) break;
      if (_tcp.available() <= 0) return false;
      _cab[_cabLen++] = static_cast<uint8_t>(_tcp.read());
    }
    const uint8_t l = _cab[1] & 0x7F;
    uint64_t tam = l;
    size_t p = 2;
    if (l == 126) {
      tam = (static_cast<uint16_t>(_cab[2]) << 8) | _cab[3];
      p = 4;
    } else if (l == 127) {
      tam = 0;
      for (int i = 0; i < 8; ++i) tam = (tam << 8) | _cab[2 + i];
      p = 10;
    }
    _mascarado = _cab[1] & 0x80;
    if (_mascarado) memcpy(_mascara, _cab + p, 4);
    _op = _cab[0] & 0x0F;
    _controle = _op >= 0x8;
    _cabLen = 0;
    _pos = 0;
    _resta = tam;
    _ctrlLen = 0;
    if (_controle && tam > sizeof(_ctrl)) {
      stop();
      return false;
    }
    if (_controle && tam == 0) tratarControle();
    return true;
  }

  void tratarControle() {
    if (_op == 0x8) stop();                              // close
    else if (_op == 0x9) enviarQuadro(0x8A, _ctrl, _ctrlLen);  // ping -> pong
  }

  // Move bytes do TCP para o buffer de dados, removendo o enquadramento WebSocket.
  void bombear() {
    if (!_aberto) return;
    if (_rxIni == _rxFim) {
      _rxIni = _rxFim = 0;
    } else if (_rxIni > sizeof(_rx) / 2) {
      memmove(_rx, _rx + _rxIni, _rxFim - _rxIni);
      _rxFim -= _rxIni;
      _rxIni = 0;
    }
    while (_aberto && _tcp.available() > 0) {
      if (_resta == 0) {
        if (!lerCabecalho()) return;
        continue;
      }
      if (_controle) {
        while (_resta && _tcp.available() > 0) {
          uint8_t b = static_cast<uint8_t>(_tcp.read());
          if (_mascarado) b ^= _mascara[_pos & 3];
          _ctrl[_ctrlLen++] = b;
          --_resta;
          ++_pos;
        }
        if (_resta == 0) tratarControle();
        continue;
      }
      const size_t espaco = sizeof(_rx) - _rxFim;
      if (!espaco) return;  // PubSubClient ainda nao consumiu os dados
      size_t m = static_cast<size_t>(min<uint64_t>(_resta, espaco));
      m = min(m, static_cast<size_t>(_tcp.available()));
      const int lidos = _tcp.read(_rx + _rxFim, m);
      if (lidos <= 0) return;
      if (_mascarado)
        for (int j = 0; j < lidos; ++j) _rx[_rxFim + j] ^= _mascara[(_pos + j) & 3];
      _rxFim += lidos;
      _resta -= lidos;
      _pos += lidos;
    }
  }

  WiFiClient _tcp;
  const char* _caminho;
  bool _aberto = false, _mascarado = false, _controle = false;
  uint8_t _cab[14];
  size_t _cabLen = 0;
  uint8_t _mascara[4] = {0, 0, 0, 0};
  uint8_t _op = 0;
  uint64_t _resta = 0;
  size_t _pos = 0;
  uint8_t _ctrl[125];
  size_t _ctrlLen = 0;
  uint8_t _rx[2048];
  size_t _rxIni = 0, _rxFim = 0;
};
