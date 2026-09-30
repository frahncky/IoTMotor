// Alarmes da placa de sensores (alarm_list.h), com o codigo real do firmware.
// A regra que o painel e o app repetem: comparacao estrita, e leitura velha
// (mais de 15 s) nao dispara nem silencia.
#include "teste.h"
#include "Arduino.h"
#include "ArduinoJson.h"
#include "Preferences.h"
#include "../iotmotor_esp32/iotmotor_esp32_s3_sensores/alarm_list.h"

static void recomecar() {
  prefsFalsas::apagar();
  alarmes::total = 0;
  alarmes::totalEventos = 0;
  alarmes::medidasDoQuadroEm = 0;
  alarmes::medidasDoQuadro.clear();
}

static void adicionar(const char* json) {
  StaticJsonDocument<256> doc;
  deserializeJson(doc, json);
  const char* motivo = "";
  const bool ok = alarmes::salvar(doc.as<JsonVariantConst>(), motivo);
  if (!ok) std::printf("    salvar recusou: %s\n", motivo);
  CONFERE(ok);
}

static void telemetriaDoQuadro(const char* json, uint32_t agora) {
  StaticJsonDocument<256> doc;
  deserializeJson(doc, json);
  alarmes::receberMedidasDoQuadro(doc.as<JsonVariantConst>(), agora);
}

TESTE("primeiro boot cria vibracao 4,5 mm/s e temperatura 60 C") {
  recomecar();
  alarmes::carregar(4.5f, 60.0f);
  CONFERE(alarmes::total == 2);
  bool vib = false, temp = false;
  for (uint8_t i = 0; i < alarmes::total; ++i) {
    vib = vib || (!strcmp(alarmes::lista[i].campo, "vibration_mms") && alarmes::lista[i].limite == 4.5f);
    temp = temp || (!strcmp(alarmes::lista[i].campo, "temperature") && alarmes::lista[i].limite == 60.0f);
  }
  CONFERE(vib && temp);
}

TESTE("comparacao estrita: igual ao limite nao dispara") {
  recomecar();
  alarmes::carregar(4.5f, 60.0f);
  CONFERE(!alarmes::avaliar(1000, true, true, 1.0f, 60.0f));
  CONFERE(alarmes::avaliar(2000, true, true, 1.0f, 60.1f));
  CONFERE(!alarmes::avaliar(3000, true, true, 4.5f, 59.9f));
  CONFERE(alarmes::avaliar(4000, true, true, 4.51f, 20.0f));
}

TESTE("sensor ausente nao dispara alarme de limite") {
  recomecar();
  alarmes::carregar(4.5f, 60.0f);
  CONFERE(!alarmes::avaliar(1000, false, false, 99.0f, 99.0f));
  CONFERE(!alarmes::avaliar(1000, true, true, NAN, 20.0f));  // Janela ainda sem leitura.
}

TESTE("alarme de corrente usa a telemetria do quadro e expira em 15 s") {
  recomecar();
  adicionar(R"({"id":"corr","field":"current","board":"command","above":true,"limit":10,"on":true})");
  telemetriaDoQuadro(R"({"current":12.5,"voltage":220})", 1000);
  CONFERE(alarmes::avaliar(1000 + 15000, true, true, 0, 20));
  CONFERE(!alarmes::avaliar(1000 + 15001, true, true, 0, 20));  // Leitura velha.
}

TESTE("alarme abaixo do limite (tensao baixa)") {
  recomecar();
  adicionar(R"({"id":"vmin","field":"voltage","board":"command","above":false,"limit":200,"on":true})");
  telemetriaDoQuadro(R"({"voltage":199.5})", 5);  // 0 = "sem leitura" no firmware.
  CONFERE(alarmes::avaliar(10, true, true, 0, 20));
  telemetriaDoQuadro(R"({"voltage":200})", 20);
  CONFERE(!alarmes::avaliar(30, true, true, 0, 20));
}

TESTE("alarme desligado nao dispara") {
  recomecar();
  adicionar(R"({"id":"quente","field":"temperature","board":"sensors","above":true,"limit":30,"on":false})");
  CONFERE(!alarmes::avaliar(1000, true, true, 0, 80));
}

TESTE("cada disparo vira um evento com inicio e fim") {
  recomecar();
  alarmes::carregar(4.5f, 60.0f);
  alarmes::avaliar(1000, true, true, 1.0f, 65.0f, 1790000000);
  CONFERE(alarmes::totalEventos == 1);
  CONFERE(alarmes::eventos[0].valor == 65.0f && alarmes::eventos[0].fim == 0);
  alarmes::avaliar(61000, true, true, 1.0f, 50.0f, 1790000060);
  CONFERE(alarmes::eventos[0].fim == 1790000060);
  CONFERE(alarmes::eventos[0].fimMs - alarmes::eventos[0].inicioMs == 60000);
}

TESTE("fila de eventos guarda so os 10 ultimos") {
  recomecar();
  alarmes::carregar(4.5f, 60.0f);
  for (uint32_t i = 0; i < 12; ++i) {
    alarmes::avaliar(i * 2000, true, true, 1.0f, 70.0f + i);
    alarmes::avaliar(i * 2000 + 1000, true, true, 1.0f, 20.0f);
  }
  CONFERE(alarmes::totalEventos == alarmes::MAX_EVENTOS);
  PERTO(alarmes::eventos[0].valor, 72.0, 0.001);  // Os dois primeiros sairam.
}

TESTE("lista sobrevive a gravar e reiniciar a placa") {
  recomecar();
  alarmes::carregar(4.5f, 60.0f);
  adicionar(R"({"id":"corr","field":"current","board":"command","above":true,"limit":14.5,"on":true,"trip":true})");
  alarmes::total = 0;
  alarmes::carregar(4.5f, 60.0f);  // Nao semeia de novo: ja existe lista.
  CONFERE(alarmes::total == 3);
  const int i = alarmes::indiceDe("corr");
  CONFERE(i >= 0 && alarmes::lista[i].desarma && alarmes::lista[i].doQuadro);
}

TESTE("oito alarmes completos cabem no documento do ESP32") {
  recomecar();
  alarmes::total = 0;
  size_t texto = 0;
  for (uint8_t n = 0; n < alarmes::MAX_ALARMES; ++n) {
    alarmes::Alarme& a = alarmes::lista[alarmes::total++];
    memset(a.id, 'a', alarmes::MAX_ID_ALARME);
    a.id[alarmes::MAX_ID_ALARME] = 0;
    strcpy(a.campo, "vibration_mms");
    a.desarma = true;
    texto += alarmes::MAX_ID_ALARME + 1 + strlen(a.campo) + 1;
  }
  // Monta o mesmo JSON de gravar(), num documento grande, para medir.
  DocumentoPc doc(16384);
  JsonArray array = doc.to<JsonArray>();
  for (uint8_t i = 0; i < alarmes::total; ++i) {
    JsonObject item = array.createNestedObject();
    item["id"] = alarmes::lista[i].id;
    item["field"] = alarmes::lista[i].campo;
    item["board"] = "sensors";
    item["above"] = true;
    item["limit"] = 1.0f;
    item["on"] = true;
    item["trip"] = true;
  }
  const size_t noEsp32 = bytesNoEsp32(doc, texto);
  std::printf("    8 alarmes: %zu de %zu bytes no ESP32\n", noEsp32, alarmes::TAMANHO_DOC_ALARMES);
  CONFERE(noEsp32 <= alarmes::TAMANHO_DOC_ALARMES);
}
