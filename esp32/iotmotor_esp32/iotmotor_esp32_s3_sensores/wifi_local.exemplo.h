#pragma once
// Modelo versionado: NAO ponha senha aqui, este arquivo vai para o GitHub.
// Copie como wifi_local.h na mesma pasta (esse fica no .gitignore) e edite la.
//
// A placa tenta todas as redes cadastradas e usa a disponivel de sinal mais
// forte, entao da para levar a bancada de uma rede para outra sem regravar.
#define WIFI_SSID_LOCAL "Nome da rede"
#define WIFI_PASSWORD_LOCAL "senha"  // vazio ("") para rede aberta

// Redes adicionais (opcionais): apague as que nao usar.
// #define WIFI_SSID_2 "IFMA_IOT"
// #define WIFI_PASSWORD_2 ""
// #define WIFI_SSID_3 "Celular"
// #define WIFI_PASSWORD_3 "senha"
// #define WIFI_SSID_4 "Casa"
// #define WIFI_PASSWORD_4 "senha"
