#pragma once
// Comandos cifrados: o broker continua publico, mas so quem tem a senha manda.
//
// O painel e o aplicativo cifram o comando inteiro com AES-256-GCM. A chave sai
// de SHA-256("iotmotor-cmd-v1" | senha | device_id): cada placa tem a sua, entao
// um comando selado para o quadro nao vale para os sensores. O GCM autentica o
// texto: mexeu um byte, a placa recusa. E como o identificador da placa entra
// como dado autenticado, nem trocar o destino adianta.
//
// Contra repeticao (alguem gravar um comando do ar e reenviar) a placa publica
// um desafio aleatorio em <prefixo>/<placa>/auth. O comando so vale se trouxer
// o desafio da vez; assim que um comando e aceito, o desafio e queimado e outro
// e sorteado. O desafio tambem muda a cada reinicio.
//
// A senha vem de comando_local.h (fora do Git), como as redes Wi-Fi. Sem ela a
// placa se comporta como antes, aceitando comando aberto, e avisa isso na
// telemetria (secure: false) para o painel mostrar o aviso.
#include <Arduino.h>
#include <ArduinoJson.h>
#include <mbedtls/gcm.h>
#include <mbedtls/sha256.h>
#include <mbedtls/base64.h>
#include <esp_random.h>

#if __has_include("comando_local.h")
#include "comando_local.h"
#endif
#ifndef COMANDO_SENHA
#define COMANDO_SENHA ""
#endif

namespace comandoseguro {

constexpr char ROTULO[] = "iotmotor-cmd-v1";
constexpr size_t MAX_ABERTO = 1024;  // Comando ja decifrado.
constexpr size_t IV = 12, TAG = 16;

inline uint8_t chave[32];
inline bool ligado = false;
inline char desafio[33] = "";

inline void sortearDesafio() {
  uint8_t bruto[16];
  esp_fill_random(bruto, sizeof(bruto));
  for (size_t i = 0; i < sizeof(bruto); ++i)
    snprintf(desafio + i * 2, 3, "%02x", bruto[i]);
  desafio[32] = '\0';
}

// Deriva a chave desta placa a partir da senha compilada.
inline void iniciar(const char* deviceId) {
  const char* senha = COMANDO_SENHA;
  ligado = senha[0] && deviceId && deviceId[0];
  if (!ligado) {
    Serial.println("[CMD] sem senha em comando_local.h: comandos abertos no broker publico");
    return;
  }
  mbedtls_sha256_context sha;
  mbedtls_sha256_init(&sha);
  const bool ok =
      mbedtls_sha256_starts(&sha, 0) == 0 &&
      mbedtls_sha256_update(&sha, (const unsigned char*)ROTULO, sizeof(ROTULO) - 1) == 0 &&
      mbedtls_sha256_update(&sha, (const unsigned char*)senha, strlen(senha)) == 0 &&
      mbedtls_sha256_update(&sha, (const unsigned char*)deviceId, strlen(deviceId)) == 0 &&
      mbedtls_sha256_finish(&sha, chave) == 0;
  mbedtls_sha256_free(&sha);
  ligado = ok;
  if (!ok) {
    Serial.println("[CMD] falha derivando a chave: comandos abertos");
    return;
  }
  sortearDesafio();
  Serial.println("[CMD] comandos cifrados exigidos (AES-256-GCM)");
}

// Decifra o comando. 'saida' recebe o JSON original, terminado em '\0'.
inline bool abrir(const char* seladoB64, const char* deviceId, char* saida, size_t maximo,
                  const char*& motivo) {
  static uint8_t bruto[MAX_ABERTO + IV + TAG];
  size_t tamanho = 0;
  if (!seladoB64 || !seladoB64[0] ||
      mbedtls_base64_decode(bruto, sizeof(bruto), &tamanho,
                            (const unsigned char*)seladoB64, strlen(seladoB64))) {
    motivo = "selo ilegivel";
    return false;
  }
  if (tamanho <= IV + TAG) {
    motivo = "selo curto demais";
    return false;
  }
  const size_t texto = tamanho - IV - TAG;
  if (texto >= maximo) {
    motivo = "comando grande demais";
    return false;
  }
  mbedtls_gcm_context gcm;
  mbedtls_gcm_init(&gcm);
  const bool ok =
      mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, chave, 256) == 0 &&
      mbedtls_gcm_auth_decrypt(&gcm, texto, bruto, IV,
                               (const unsigned char*)deviceId, strlen(deviceId),
                               bruto + IV + texto, TAG, bruto + IV,
                               (unsigned char*)saida) == 0;
  mbedtls_gcm_free(&gcm);
  if (!ok) {
    motivo = "selo nao confere: senha diferente";
    return false;
  }
  saida[texto] = '\0';
  return true;
}

inline bool confereDesafio(const char* recebido) {
  return recebido && strlen(recebido) == 32 && !strcmp(recebido, desafio);
}

// Queima o desafio usado: o mesmo comando nao vale duas vezes.
inline void usar() { sortearDesafio(); }

inline void descrever(JsonDocument& doc) {
  doc["secure"] = ligado;
  if (ligado) doc["challenge"] = desafio;
}

}  // namespace comandoseguro
