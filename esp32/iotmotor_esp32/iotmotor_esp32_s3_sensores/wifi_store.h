#pragma once
// Lista de redes Wi-Fi gravada na placa (NVS), na ordem definida pelo usuario.
//
// - Ate MAX_REDES redes. Ao conectar, a placa busca as redes visiveis e tenta
//   na ordem da lista: a primeira que responder e usada.
// - A lista e editada pela aba "Wi-Fi" do painel, via MQTT.
// - A senha NAO trafega em texto aberto no broker publico: a placa tem um par
//   de chaves P-256 proprio (gerado no primeiro boot; a privada fica so na
//   NVS) e publica a chave publica. O painel faz ECDH com uma chave efemera,
//   deriva a chave AES-256 como SHA-256("iotmotor-wifi-v1" || segredo) e cifra
//   a senha em AES-GCM, com o SSID como dado autenticado.
//
// Mantenha este arquivo identico nas pastas dos dois firmwares.
#include <Arduino.h>
#include <WiFi.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <mbedtls/ecp.h>
#include <mbedtls/gcm.h>
#include <mbedtls/sha256.h>
#include <mbedtls/base64.h>
#include <esp_random.h>
#include <esp_wifi.h>

namespace wifistore {

constexpr uint8_t MAX_REDES = 8;
constexpr size_t MAX_SSID = 32;
constexpr size_t MAX_SENHA = 64;

struct Rede {
  char ssid[MAX_SSID + 1];
  char senha[MAX_SENHA + 1];
};

inline Rede redes[MAX_REDES];
inline uint8_t total = 0;
inline uint8_t chavePrivada[32];
inline uint8_t chavePublica[65];  // Ponto P-256 nao comprimido (0x04 || X || Y).
inline bool chavesProntas = false;

inline int aleatorio(void*, unsigned char* saida, size_t tamanho) {
  esp_fill_random(saida, tamanho);
  return 0;
}

inline void salvar() {
  Preferences memoria;
  if (!memoria.begin("iot-redes", false)) return;
  memoria.putUChar("n", total);
  char chave[4];
  for (uint8_t i = 0; i < MAX_REDES; ++i) {
    snprintf(chave, sizeof(chave), "s%u", i);
    if (i < total) memoria.putString(chave, redes[i].ssid);
    else memoria.remove(chave);
    snprintf(chave, sizeof(chave), "p%u", i);
    if (i < total) memoria.putString(chave, redes[i].senha);
    else memoria.remove(chave);
  }
  memoria.end();
}

inline int indiceDe(const char* ssid) {
  for (uint8_t i = 0; i < total; ++i)
    if (!strcmp(redes[i].ssid, ssid)) return i;
  return -1;
}

// Insere (ou atualiza) a rede na posicao pedida; posicao fora da lista = fim.
inline bool adicionar(const char* ssid, const char* senha, int posicao, bool gravar = true) {
  if (!ssid || !*ssid || strlen(ssid) > MAX_SSID || !senha || strlen(senha) > MAX_SENHA) return false;
  const int existente = indiceDe(ssid);
  if (existente >= 0) {  // Mesma rede: tira da posicao antiga antes de reinserir.
    for (uint8_t i = existente; i + 1 < total; ++i) redes[i] = redes[i + 1];
    --total;
  }
  if (total >= MAX_REDES) return false;
  if (posicao < 0 || posicao > total) posicao = total;
  for (int i = total; i > posicao; --i) redes[i] = redes[i - 1];
  strncpy(redes[posicao].ssid, ssid, MAX_SSID);
  redes[posicao].ssid[MAX_SSID] = '\0';
  strncpy(redes[posicao].senha, senha, MAX_SENHA);
  redes[posicao].senha[MAX_SENHA] = '\0';
  ++total;
  if (gravar) salvar();
  return true;
}

inline bool remover(const char* ssid) {
  const int i = indiceDe(ssid ? ssid : "");
  if (i < 0) return false;
  for (uint8_t j = i; j + 1 < total; ++j) redes[j] = redes[j + 1];
  --total;
  salvar();
  return true;
}

// A nova ordem precisa conter exatamente as redes ja cadastradas.
inline bool reordenar(JsonArrayConst ordem) {
  if (ordem.size() != total) return false;
  Rede nova[MAX_REDES];
  uint8_t n = 0;
  for (JsonVariantConst item : ordem) {
    const int i = indiceDe(item | "");
    if (i < 0) return false;
    for (uint8_t k = 0; k < n; ++k)
      if (!strcmp(nova[k].ssid, redes[i].ssid)) return false;  // Repetida.
    nova[n++] = redes[i];
  }
  for (uint8_t i = 0; i < n; ++i) redes[i] = nova[i];
  salvar();
  return true;
}

// Carrega a lista. Na primeira vez, semeia com as redes de wifi_local.h e com
// a rede antiga do portal; depois disso a lista pertence ao usuario.
inline void carregar(const char* const* ssidsIniciais, const char* const* senhasIniciais, uint8_t n) {
  Preferences memoria;
  memoria.begin("iot-redes", false);
  const bool semeada = memoria.getBool("ok", false);
  total = 0;
  if (semeada) {
    const uint8_t salvas = memoria.getUChar("n", 0);
    char chave[4];
    for (uint8_t i = 0; i < salvas && i < MAX_REDES; ++i) {
      snprintf(chave, sizeof(chave), "s%u", i);
      const String ssid = memoria.getString(chave, "");
      snprintf(chave, sizeof(chave), "p%u", i);
      const String senha = memoria.getString(chave, "");
      if (ssid.length()) adicionar(ssid.c_str(), senha.c_str(), -1, false);
    }
    memoria.end();
    return;
  }
  memoria.putBool("ok", true);
  memoria.end();
  for (uint8_t i = 0; i < n; ++i) adicionar(ssidsIniciais[i], senhasIniciais[i], -1, false);
  Preferences antiga;  // Rede gravada pela versao anterior do portal.
  if (antiga.begin("iotmotor-wifi", true)) {
    const String ssid = antiga.getString("ssid", "");
    const String senha = antiga.getString("pass", "");
    antiga.end();
    if (ssid.length()) adicionar(ssid.c_str(), senha.c_str(), 0, false);
  }
  // Rede que o driver de Wi-Fi lembra da ultima conexao (gravada pelo firmware
  // anterior). E ela que mantem a placa na rede quando esta versao chega pela
  // atualizacao OTA, que nao traz as senhas de wifi_local.h.
  wifi_config_t lembrada = {};
  if (esp_wifi_get_config(WIFI_IF_STA, &lembrada) == ESP_OK && lembrada.sta.ssid[0]) {
    char ssid[MAX_SSID + 1] = {0};
    char senha[MAX_SENHA + 1] = {0};
    memcpy(ssid, lembrada.sta.ssid, MAX_SSID);
    memcpy(senha, lembrada.sta.password, MAX_SENHA);
    if (adicionar(ssid, senha, 0, false))
      Serial.printf("[WiFi] rede lembrada pelo driver importada: %s\n", ssid);
    memset(senha, 0, sizeof(senha));
  }
  memset(&lembrada, 0, sizeof(lembrada));
  salvar();
}

inline bool prepararChaves() {
  Preferences memoria;
  if (!memoria.begin("iot-chave", false)) return false;
  mbedtls_ecp_group grupo;
  mbedtls_mpi d;
  mbedtls_ecp_point q;
  mbedtls_ecp_group_init(&grupo);
  mbedtls_mpi_init(&d);
  mbedtls_ecp_point_init(&q);
  bool ok = mbedtls_ecp_group_load(&grupo, MBEDTLS_ECP_DP_SECP256R1) == 0;
  if (ok && memoria.getBytes("priv", chavePrivada, sizeof(chavePrivada)) == sizeof(chavePrivada)) {
    ok = mbedtls_mpi_read_binary(&d, chavePrivada, sizeof(chavePrivada)) == 0 &&
         mbedtls_ecp_mul(&grupo, &q, &d, &grupo.G, aleatorio, nullptr) == 0;
  } else if (ok) {
    ok = mbedtls_ecp_gen_keypair(&grupo, &d, &q, aleatorio, nullptr) == 0 &&
         mbedtls_mpi_write_binary(&d, chavePrivada, sizeof(chavePrivada)) == 0 &&
         memoria.putBytes("priv", chavePrivada, sizeof(chavePrivada)) == sizeof(chavePrivada);
  }
  size_t tamanho = 0;
  ok = ok && mbedtls_ecp_point_write_binary(&grupo, &q, MBEDTLS_ECP_PF_UNCOMPRESSED, &tamanho,
                                            chavePublica, sizeof(chavePublica)) == 0 &&
       tamanho == sizeof(chavePublica);
  mbedtls_ecp_point_free(&q);
  mbedtls_mpi_free(&d);
  mbedtls_ecp_group_free(&grupo);
  memoria.end();
  chavesProntas = ok;
  return ok;
}

inline size_t deBase64(const char* texto, uint8_t* saida, size_t maximo) {
  size_t tamanho = 0;
  if (!texto || mbedtls_base64_decode(saida, maximo, &tamanho,
                                      reinterpret_cast<const unsigned char*>(texto), strlen(texto)))
    return 0;
  return tamanho;
}

// Decifra a senha enviada pelo painel. O SSID autentica o texto cifrado.
inline bool decifrarSenha(const char* ssid, const char* epkB64, const char* ivB64,
                          const char* ctB64, char* senha, size_t maximo) {
  if (!chavesProntas) return false;
  uint8_t epk[65], iv[12], ct[MAX_SENHA + 16];
  if (deBase64(epkB64, epk, sizeof(epk)) != sizeof(epk) ||
      deBase64(ivB64, iv, sizeof(iv)) != sizeof(iv)) return false;
  const size_t tamanhoCt = deBase64(ctB64, ct, sizeof(ct));
  if (tamanhoCt < 16 || tamanhoCt - 16 >= maximo) return false;
  const size_t tamanhoSenha = tamanhoCt - 16;

  mbedtls_ecp_group grupo;
  mbedtls_mpi d;
  mbedtls_ecp_point efemera, produto;
  mbedtls_ecp_group_init(&grupo);
  mbedtls_mpi_init(&d);
  mbedtls_ecp_point_init(&efemera);
  mbedtls_ecp_point_init(&produto);
  uint8_t segredo[32];
  bool ok = mbedtls_ecp_group_load(&grupo, MBEDTLS_ECP_DP_SECP256R1) == 0 &&
            mbedtls_mpi_read_binary(&d, chavePrivada, sizeof(chavePrivada)) == 0 &&
            mbedtls_ecp_point_read_binary(&grupo, &efemera, epk, sizeof(epk)) == 0 &&
            mbedtls_ecp_check_pubkey(&grupo, &efemera) == 0 &&
            mbedtls_ecp_mul(&grupo, &produto, &d, &efemera, aleatorio, nullptr) == 0 &&
            mbedtls_mpi_write_binary(&produto.MBEDTLS_PRIVATE(X), segredo, sizeof(segredo)) == 0;
  mbedtls_ecp_point_free(&produto);
  mbedtls_ecp_point_free(&efemera);
  mbedtls_mpi_free(&d);
  mbedtls_ecp_group_free(&grupo);
  if (!ok) return false;

  static const char ROTULO[] = "iotmotor-wifi-v1";
  uint8_t chave[32];
  mbedtls_sha256_context sha;
  mbedtls_sha256_init(&sha);
  ok = mbedtls_sha256_starts(&sha, 0) == 0 &&
       mbedtls_sha256_update(&sha, reinterpret_cast<const unsigned char*>(ROTULO), sizeof(ROTULO) - 1) == 0 &&
       mbedtls_sha256_update(&sha, segredo, sizeof(segredo)) == 0 &&
       mbedtls_sha256_finish(&sha, chave) == 0;
  mbedtls_sha256_free(&sha);
  memset(segredo, 0, sizeof(segredo));
  if (!ok) return false;

  mbedtls_gcm_context gcm;
  mbedtls_gcm_init(&gcm);
  ok = mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, chave, 256) == 0 &&
       mbedtls_gcm_auth_decrypt(&gcm, tamanhoSenha, iv, sizeof(iv),
                                reinterpret_cast<const unsigned char*>(ssid), strlen(ssid),
                                ct + tamanhoSenha, 16, ct, reinterpret_cast<unsigned char*>(senha)) == 0;
  mbedtls_gcm_free(&gcm);
  memset(chave, 0, sizeof(chave));
  if (!ok) return false;
  senha[tamanhoSenha] = '\0';
  return true;
}

// Busca as redes visiveis e tenta as cadastradas na ordem da lista.
inline bool conectarEmOrdem(uint32_t esperaPorRedeMs) {
  if (!total) return false;
  WiFi.mode(WIFI_STA);
  const int encontradas = WiFi.scanNetworks(false, true);
  for (uint8_t i = 0; i < total; ++i) {
    bool visivel = encontradas <= 0;  // Se a busca falhar, tenta mesmo assim.
    for (int j = 0; j < encontradas && !visivel; ++j)
      visivel = WiFi.SSID(j) == redes[i].ssid;
    if (!visivel) continue;
    Serial.printf("[WiFi] tentando %s (prioridade %u de %u)\n", redes[i].ssid, i + 1, total);
    WiFi.disconnect(false, false);
    if (*redes[i].senha) WiFi.begin(redes[i].ssid, redes[i].senha);
    else WiFi.begin(redes[i].ssid);
    const unsigned long inicio = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - inicio < esperaPorRedeMs) delay(100);
    if (WiFi.status() == WL_CONNECTED) {
      WiFi.scanDelete();
      return true;
    }
  }
  WiFi.scanDelete();
  return false;
}

// ---- Rede propria da placa (ponto de acesso usado pelo portal) ----
// Nome e senha definidos pela aba "Wi-Fi" do painel; sem senha = rede aberta.
inline char apNome[MAX_SSID + 1] = "";
inline char apSenha[MAX_SENHA + 1] = "";

inline void carregarRedePropria(const char* nomePadrao) {
  Preferences memoria;
  String nome, senha;
  if (memoria.begin("iot-ap", true)) {
    nome = memoria.getString("nome", "");
    senha = memoria.getString("senha", "");
    memoria.end();
  }
  strncpy(apNome, nome.length() ? nome.c_str() : nomePadrao, MAX_SSID);
  apNome[MAX_SSID] = '\0';
  strncpy(apSenha, senha.c_str(), MAX_SENHA);
  apSenha[MAX_SENHA] = '\0';
}

inline bool salvarRedePropria(const char* nome, const char* senha) {
  const size_t n = strlen(nome), s = strlen(senha);
  if (!n || n > MAX_SSID || (s && (s < 8 || s > 63))) return false;  // WPA2: 8 a 63.
  Preferences memoria;
  if (!memoria.begin("iot-ap", false)) return false;
  memoria.putString("nome", nome);
  memoria.putString("senha", senha);
  memoria.end();
  strncpy(apNome, nome, MAX_SSID);
  apNome[MAX_SSID] = '\0';
  strncpy(apSenha, senha, MAX_SENHA);
  apSenha[MAX_SENHA] = '\0';
  return true;
}

enum class Resultado { NaoEWifi, Aceito, Recusado };

// Comandos da aba "Wi-Fi" do painel: wifi_list, wifi_add, wifi_remove e
// wifi_order. (wifi_portal fica com cada firmware, porque reinicia a placa.)
inline Resultado tratarComando(const char* acao, JsonVariantConst doc, const char*& motivo) {
  if (strncmp(acao, "wifi_", 5) || !strcmp(acao, "wifi_portal")) return Resultado::NaoEWifi;
  if (!strcmp(acao, "wifi_list")) {
    motivo = "lista publicada";
    return Resultado::Aceito;
  }
  const char* ssid = doc["ssid"] | "";
  if (!strcmp(acao, "wifi_add")) {
    char senha[MAX_SENHA + 1] = "";
    const bool aberta = doc["open"] | false;
    if (!aberta && !decifrarSenha(ssid, doc["epk"] | "", doc["iv"] | "", doc["ct"] | "",
                                   senha, sizeof(senha))) {
      motivo = "senha nao pode ser decifrada";
      return Resultado::Recusado;
    }
    const bool ok = adicionar(ssid, senha, doc["position"] | -1);
    memset(senha, 0, sizeof(senha));
    motivo = ok ? "rede gravada" : "rede invalida ou lista cheia";
    return ok ? Resultado::Aceito : Resultado::Recusado;
  }
  if (!strcmp(acao, "wifi_remove")) {
    if (total <= 1 && indiceDe(ssid) >= 0) {  // Sem rede, so o portal salvaria a placa.
      motivo = "a lista precisa ter ao menos uma rede";
      return Resultado::Recusado;
    }
    const bool ok = remover(ssid);
    motivo = ok ? "rede removida" : "rede nao encontrada";
    return ok ? Resultado::Aceito : Resultado::Recusado;
  }
  if (!strcmp(acao, "wifi_ap")) {  // Nome e senha da rede propria da placa.
    const char* nome = doc["name"] | "";
    char senha[MAX_SENHA + 1] = "";
    const bool aberta = doc["open"] | false;
    if (!aberta && !decifrarSenha(nome, doc["epk"] | "", doc["iv"] | "", doc["ct"] | "",
                                   senha, sizeof(senha))) {
      motivo = "senha nao pode ser decifrada";
      return Resultado::Recusado;
    }
    const bool ok = salvarRedePropria(nome, senha);
    memset(senha, 0, sizeof(senha));
    motivo = ok ? "rede da placa configurada" : "nome de 1 a 32 caracteres e senha de 8 a 63";
    return ok ? Resultado::Aceito : Resultado::Recusado;
  }
  if (!strcmp(acao, "wifi_order")) {
    const bool ok = reordenar(doc["order"].as<JsonArrayConst>());
    motivo = ok ? "ordem gravada" : "ordem invalida";
    return ok ? Resultado::Aceito : Resultado::Recusado;
  }
  motivo = "acao de wifi desconhecida";
  return Resultado::Recusado;
}

// Estado publicado no topico .../wifi (retido). Nunca inclui senhas.
inline void descrever(JsonDocument& doc) {
  JsonArray lista = doc.createNestedArray("networks");
  for (uint8_t i = 0; i < total; ++i) {
    JsonObject rede = lista.createNestedObject();
    rede["ssid"] = redes[i].ssid;
    rede["open"] = !*redes[i].senha;
  }
  doc["max"] = MAX_REDES;
  JsonObject propria = doc.createNestedObject("ap");
  propria["name"] = apNome;
  propria["open"] = !*apSenha;
  if (WiFi.status() == WL_CONNECTED) doc["connected"] = WiFi.SSID();
  if (chavesProntas) {
    unsigned char texto[96];
    size_t tamanho = 0;
    if (!mbedtls_base64_encode(texto, sizeof(texto), &tamanho, chavePublica, sizeof(chavePublica)))
      doc["pubkey"] = String(reinterpret_cast<char*>(texto), tamanho);
  }
}

}  // namespace wifistore
