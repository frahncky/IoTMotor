# Dashboard IoTMotor — Cloudflare Pages

Painel estático, somente leitura, para o firmware `esp32/iotmotor_esp32/iotmotor_esp32_comandos/iotmotor_esp32_comandos.ino` (`esp32-01`). A página usa MQTT sobre **WebSocket seguro (WSS)**; o ESP32 usa MQTT/TCP. Não é preciso compilar o Flutter para publicar este painel.

## Configuração para o ESP32 que utiliza Mosquitto

| Dispositivo | Host / URL | Porta e protocolo |
|---|---|---|
| ESP32 | `test.mosquitto.org` | `1883` (MQTT/TCP) |
| Dashboard Cloudflare | `wss://test.mosquitto.org:8081` | `8081` (MQTT/WSS) |

No painel, use prefixo `iotmotor` e ID `esp32-01`, **desde que esses valores continuem iguais no firmware**. Não use `mosquito` (sem o segundo `t`), ponto extra depois de `.org` ou porta `1883` em uma URL `wss://`.

A versão anterior sugeria HiveMQ por padrão. Esta versão migra automaticamente **somente aquele valor antigo** armazenado no navegador, sem sobrescrever um broker personalizado. O endereço pode ser alterado no campo de conexão; o painel guarda apenas URL, prefixo e ID, sem credenciais.

> O firmware `comandos` gera tensão e corrente simuladas por software. O painel não mede sensores reais nem oferece controle remoto: um broker público sem autenticação não é seguro para acionar motores.

## Publicação no Cloudflare Pages

1. Cloudflare → **Workers & Pages** → **Create application** → **Pages** → conectar GitHub.
2. Selecione o repositório privado `frahncky/IoTMotor` e autorize o acesso se necessário.
3. Branch de produção: `main`; framework: `None`; diretório raiz: `/`; comando de build: `exit 0`; diretório de saída: `dashboard-cloudflare`.
4. Publique e abra o endereço real `*.pages.dev` fornecido pelo Cloudflare. Alterações no GitHub precisam de um deploy concluído para aparecerem no site. Não existe URL pública garantida ou confirmada neste repositório.
5. Atualize a página (se necessário, recarga forçada) e clique **Conectar ao MQTT**.

## Identificar por que não aparece telemetria

- **O endereço `*.pages.dev` não abre:** verifique o deploy no Cloudflare; enviar código ao GitHub não publica o site sozinho.
- **Biblioteca indisponível:** o navegador não carregou MQTT.js pelo CDN; confira conexão/restrições da rede ou Console do navegador.
- **Broker indisponível / Reconectando:** a conexão WebSocket à URL WSS falhou. Confira endereço, certificado e porta. O broker público Mosquitto informa que pode haver indisponibilidade de WebSockets ou TLS: https://test.mosquitto.org/.
- **Broker conectado, sem dados:** a página conectou, mas não recebeu nada em `iotmotor/esp32-01/telemetry`. Verifique no ESP32 se a alteração do host foi **recompilada e gravada**, se conectou ao Wi-Fi e ao MQTT, se ID e prefixo batem e se o código está publicando.
- **Status `online` sem dados:** pode ser uma mensagem *retida* do broker; não comprova que a placa esteja online agora.

Se a página continuar vazia, forneça a URL publicada e copie o texto do quadro **Diagnóstico da conexão**. Isso distingue falha de publicação, de WebSocket, de assinatura e de firmware.

## Segurança

O Mosquitto público serve para testes e pode apresentar interrupções. Não conecte a saída do relé a um motor durante os ensaios e não envie comandos de partida/parada por um broker público sem autenticação. Para operar hardware real, use broker privado com TLS, autenticação, autorização por tópico, proteção elétrica e intertravamentos locais. Não publique credenciais de Wi-Fi, chaves MQTT nem tokens do Cloudflare no frontend ou no GitHub. O firmware original contém credencial Wi-Fi versionada; troque-a e elimine o segredo também do histórico antes de compartilhar o repositório.

O dashboard `dashboard_iotmotor/` no PR #3 é um projeto distinto, para outros firmwares. Este painel foi feito para o sketch `comandos`.
