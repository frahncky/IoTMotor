# Desenvolvimento

Como o projeto está organizado, como testar e como cada parte chega ao usuário.

## Estrutura

```text
dashboard-cloudflare/   Painel web: HTML e JavaScript puros, sem build
  index.html              Página única (estilos inline)
  dual-dashboard.js       Conexão, telemetria, card do motor, gráficos, avisos
  local-controls.js       Partidas gravadas no quadro (lista e editor)
  remote-controls.js      Ligar/Desligar, segurança do ensaio, modo instrumentação
  motor-animation.js      Desenho animado do motor
  motor-sound.js          Som do motor (gravação Pixabay + síntese de fallback)
  hardware-mirror.js      Espelho do LCD e dos contatores (só leitura)
  alarm-controls.js       Alarmes da placa e alarmes sugeridos
  motor-info.js           Dados do motor e manutenção
  board-history.js        Histórico de 7 dias da placa
  wifi-manager.js         Aba Dispositivos: Wi-Fi, versão de firmware, OTA
  command-seal.js         Comandos cifrados (AES-256-GCM)
  mqtt-shared.js          Uma conexão MQTT dividida entre os módulos
  vendor/                 MQTT.js 5.10.4 servido pelo próprio painel (sem CDN)
  *.test.cjs              Testes (node --test)
functions/mqtt.js       Ponte MQTT na porta 443 (Cloudflare Pages Function)
esp32/iotmotor_esp32/   Firmware das duas placas (veja firmware.md)
lib/                    App Flutter
  features/iot_motor/
    controller/           Estado e regras do app: uma classe, dividida por assunto
                          em partes (alertas, histórico, partidas, placas, dispositivos)
    models/               Telemetria, aquisição, alarmes, dados do motor
    services/             MQTT, selo de comando, atualização do app, armazenamento
    view/                 Abas Início, Histórico, Alertas e Configurações
      tabs/settings/      Painéis das Configurações (motor, perfis, alertas, manutenção)
test/                   Testes do app (flutter test)
tool/                   Simuladores das placas em Dart
docs/                   Documentação técnica, incluindo vibracao.md, audio.md e imagens SVG
```

## Rodar o painel localmente

O painel não tem build: sirva a pasta e abra no navegador.

```sh
cd dashboard-cloudflare
python3 -m http.server 8000
# abra http://localhost:8000
```

Sem a ponte da Cloudflare, use o broker direto no campo **URL WebSocket segura**:
`wss://test.mosquitto.org:8081`.

## Simular as placas

Os simuladores publicam telemetria parecida com a das placas, sem hardware:

```sh
dart run tool/esp32_01_simulator.dart --host test.mosquitto.org --prefix iotmotor-teste
dart run tool/esp32_02_simulator.dart --host test.mosquitto.org --prefix iotmotor-teste
```

Use um prefixo próprio (como `iotmotor-teste`) para não misturar com a bancada
real, e configure o mesmo prefixo no painel. `--help` lista as opções.

## Testes

| O quê | Comando |
| --- | --- |
| Painel (sintaxe) | `for f in dashboard-cloudflare/*.js; do node --check $f; done` |
| Painel (testes) | `node --test dashboard-cloudflare/*.test.cjs` |
| App | `flutter test` e `flutter analyze` |
| Firmware | `arduino-cli compile …` ([comandos](firmware.md#primeira-gravação-por-cabo)) |

Os testes do painel rodam cada módulo num DOM de mentira com um cliente MQTT
falso (`vm` do Node). Os do app usam um `MqttMotorService` falso e alimentam o
controlador com mensagens como se viessem do broker.

## Integração contínua

| Workflow | Quando roda | O que faz |
| --- | --- | --- |
| `cloudflare-dashboard.yml` | PR e push na `main` que mexem no painel, em `functions/` ou no firmware | Checa sintaxe, roda os testes do painel e confere firmware × painel × app (versões, campos, arquivos iguais nas duas placas) |
| `esp32-compile.yml` | PR e push na `main` no firmware, ou manual | Compila as duas placas |
| `publish-firmware.yml` | Push na `main` no firmware | Compila e publica `esp32-01.bin` e `esp32-02.bin` no release `firmware-latest` |
| `android-apk.yml` | PR e push na `main` no app (`lib/`, `android/`, `assets/`, `pubspec.*`) | Na PR, exige versão maior que a da `main`. Roda `flutter test` e gera o APK assinado (só ARM, 32 e 64 bits). Só o push na `main` publica: `app-latest` e a release da versão (por exemplo, `app-v2.4.3`) |

Erro de compilação do firmware ou do app aparece na própria PR, antes do merge.

## Como cada parte chega ao usuário

| Parte | Caminho | Quanto demora |
| --- | --- | --- |
| **Painel** | Cloudflare Pages ligado ao GitHub publica a `main` em [iotmotor.pages.dev](https://iotmotor.pages.dev). Cada PR ganha uma prévia | ~1 min |
| **Firmware** | `publish-firmware.yml` → release `firmware-latest` → botão **Atualizar firmware** em cada placa | ~3 min + OTA |
| **App** | `android-apk.yml` → release `app-latest` (`IoTMotor.apk` + `app-latest.json`) → **Configurações › Atualizar este app** | ~7 min |

### Versão do app

Cada atualização do app tem número e nome:

- **Número:** `version:` do `pubspec.yaml` (por exemplo, `2.4.3+12`). O que vem depois do `+` é o `versionCode`; a versão exibida é `2.4.3`.
- **Nome:** `nomeDaVersao` em `lib/app/versao.dart`, curto e dizendo o que a versão traz ("Alertas no celular").

Ao mudar o app, suba o número e troque o nome na mesma PR: sem isso a PR falha
no `android-apk.yml`. Na `main`, o CI publica a release `app-v<número>` com o
título "IoTMotor <versão> — <nome da versão>" e o APK, e o `app-latest.json`
leva o nome, que o app mostra em **Configurações › Atualizar este app**.

- Correção pequena: `2.4.3 → 2.4.4`.
- Recurso novo: `2.4.x → 2.5.0`.
- Mudança grande: `2.x → 3.0.0`.

Configuração do Cloudflare Pages:
- branch `main`;
- build command `exit 0`;
- output `dashboard-cloudflare`;
- a pasta `functions/` fica na raiz, que é onde o Pages procura.

O APK é assinado com uma chave fixa, que vem dos segredos `ANDROID_KEYSTORE_*`.
Sem eles o workflow para, porque um APK com outra assinatura obrigaria a
desinstalar o app para atualizar.

## Segredos do repositório

| Segredo | Usado em | Para quê |
| --- | --- | --- |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | `android-apk.yml` | Assinar o APK |
| `IOTMOTOR_CMD_SENHA` | firmware | [Senha de comando](firmware.md#senha-de-comando). Hoje não existe |

## Fechar o painel com login

O endereço do painel é público. Para exigir login, use o **Cloudflare Access**
no projeto Pages `iotmotor` (o plano gratuito cobre até 50 pessoas):

1. Cloudflare → **Zero Trust** → Access → **Applications** → *Add an application* → **Self-hosted**.
2. Domínio: `iotmotor.pages.dev`.
3. Policy: *Allow* → **Emails** → os e-mails do grupo.
4. Identity provider: **One-time PIN**. Cada pessoa recebe um código por e-mail, sem precisar de conta.

Isso não substitui a senha de comando: quem estiver no broker continua vendo a
telemetria, que não é cifrada.

## Checklist ao mudar aquisição e telemetria

- [ ] Se mudar `pzem_read_ms`, `publish_ms`, `chart_ms` ou `record_ms`, mantenha as validações equivalentes no firmware, web e app.
- [ ] O ESP32-01 continua sendo a fonte oficial: grava em NVS e publica `<prefixo>/system/acquisition` como mensagem retida.
- [ ] O ESP32-S3 deve continuar assinando a configuração e aplicar somente a cadência de publicação; a aquisição de vibração fica em 1000 Hz / janela RMS de 1 s.
- [ ] Mudou `vibracao.h`? Atualize [vibracao.md](vibracao.md), especialmente filtros, taxa, janela, critérios de validade e faixa útil.
- [ ] Gráficos não devem criar amostras sintéticas. A janela temporal deve usar dados realmente recebidos.
- [ ] Atualize [mqtt.md](mqtt.md), [guia-de-uso.md](guia-de-uso.md) e [firmware.md](firmware.md) quando o contrato mudar.

## Checklist ao mudar o firmware

- [ ] Troque `firmware_version` no `.ino` e as constantes `FIRMWARE_PUBLICADO` (painel) e `firmwarePublicado` (app). O CI confere as três.
- [ ] Arquivos comuns (`wifi_store.h`, `comando_seguro.h`, `ota_update.h`…) devem mudar **nas duas pastas**.
- [ ] Comando novo? Documente em [mqtt.md](mqtt.md). Placa antiga responde `unknown_action`, e o painel traduz isso em "atualize a placa".
- [ ] Campo novo na telemetria do quadro? A placa de sensores lê essa telemetria: confira se o tamanho cabe (ela aceita até 1800 bytes).
- [ ] Confira que as duas placas compilam na PR (`esp32-compile.yml`).

## Proveniência do áudio do motor

A gravação-base `dashboard-cloudflare/motor-ligado.mp3` foi obtida no Pixabay, a partir da busca de efeitos sonoros **electric motor**. A origem, licença, processamento e arquivos derivados do app estão registrados em [audio.md](audio.md) e em [../THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
