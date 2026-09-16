# Dashboard IoTMotor para Cloudflare Pages

Dashboard web **somente leitura** compatível com o firmware que está em `esp32/iotmotor_esp32/iotmotor_esp32_comandos/iotmotor_esp32_comandos.ino` na branch `main`.

## O que funciona

- Conexão MQTT por WebSocket seguro (WSS) com diagnóstico de conexão e reconexão.
- Telemetria do `esp32-01`: tensão, corrente, estado do motor e data da última amostra.
- Gráficos ao vivo (120 amostras por sessão) e exportação de CSV.
- Configuração editável de URL WSS, prefixo e ID; somente esses dados não secretos são guardados no navegador.
- A ausência de telemetria após 10 segundos é sinalizada, mesmo se o broker continuar conectado. O status MQTT retido, sozinho, não comprova que o ESP32 esteja online.

**As medições do firmware `comandos` são simuladas por software, não leituras de sensores reais.**

O dashboard não possui botões de partida/parada nem publica comandos. O firmware atual aceita comandos remotos pelo broker público sem autenticação: **não ligue um motor real enquanto usar essa configuração.** Para comandar um motor em produção, use broker privado com autenticação/TLS, controle de acesso, intertravamentos e proteção elétrica local; o Cloudflare Pages, sozinho, não protege o broker.

## Publicar no Cloudflare Pages

1. No Cloudflare, vá a **Workers & Pages → Create application → Pages → Import an existing Git repository**.
2. Autorize o acesso ao repositório privado `frahncky/IoTMotor`, se solicitado, e selecione-o.
3. Configure:

   | Campo | Valor |
   | --- | --- |
   | Production branch | `main` |
   | Framework preset | `None` |
   | Root directory | `/` (raiz do repositório) |
   | Build command | `exit 0` |
   | Build output directory | `dashboard-cloudflare` |

4. Selecione **Save and Deploy**. O Cloudflare fornecerá o endereço `*.pages.dev` depois que o deploy tiver êxito. Não há necessidade de compilar Flutter nem de configurar `npm` para este dashboard.
5. Na página publicada, use `wss://broker.hivemq.com:8884/mqtt`, prefixo `iotmotor`, dispositivo `esp32-01`, e clique **Conectar ao MQTT**.

O ESP32 mantém `broker.hivemq.com:1883` (TCP). A página usa a entrada WebSocket segura do **mesmo broker**, não se conecta diretamente ao IP local do ESP32. O acesso WSS à porta 8884 depende de o serviço público estar operacional. Caso não funcione, configure outro broker com WSS e altere o firmware para publicar nele também.

### Testar sem o ESP32

Ao conectar, o status de broker pode ficar conectado, mas não aparecerão amostras se nenhum ESP32 estiver publicando no tópico configurado. Isso não é um defeito dos gráficos. O botão **Exportar CSV** só é habilitado depois da primeira amostra.

### Verificação de código

A aplicação é estática (`index.html` + `app.js` + `_headers`) e não depende de build. Para verificar a sintaxe do script com Node.js:

```bash
node --check dashboard-cloudflare/app.js
```

## Limitações e segurança

- O broker público HiveMQ é compartilhado e **não é adequado para dados privados nem comandos de produção**.
- O dashboard não exige login. Publicar no Cloudflare Pages não estabelece autenticação MQTT e os dados do broker público podem ser forjados por terceiros.
- Se quiser acesso restrito ao site, configure Cloudflare Access separadamente e migre a comunicação do ESP32 para um broker privado autenticado.
- Não coloque senha Wi-Fi, token Cloudflare nem credenciais MQTT no JavaScript, no HTML ou no GitHub. Um arquivo de frontend é visível a qualquer visitante.
- O código do firmware atual versionou uma senha Wi-Fi; troque essa credencial e remova-a também do histórico Git antes de compartilhar o repositório.
- O dashboard em `dashboard_iotmotor/` da branch de PR #3 é outro projeto, voltado aos **dois novos firmwares** daquela proposta. Não confunda com esta versão, que monitora o firmware `comandos` atualmente instalado.
