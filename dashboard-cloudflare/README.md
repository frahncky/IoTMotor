# IoTMotor — dois ESP32 no dashboard Cloudflare

A página em `dashboard-cloudflare/index.html` usa `dual-dashboard.js`. **ESP32-01** lê o **PZEM-004T v3** e recebe comandos de bancada; **ESP32-S3 (esp32-02)** lê **MPU6050** (vibração) e **DS18B20** (temperatura). Ambos publicam no mesmo broker Mosquitto. A página junta as leituras, mantendo diagnóstico e histórico por origem.

| Origem | Firmware na `main` | Tópico de telemetria |
| --- | --- | --- |
| ESP32 comandos + PZEM, `esp32-01` | `esp32/iotmotor_esp32/iotmotor_esp32_comandos/iotmotor_esp32_comandos.ino` | `iotmotor/esp32-01/telemetry` |
| ESP32-S3 sensores, `esp32-02` | `esp32/iotmotor_esp32/iotmotor_esp32_s3_sensores/iotmotor_esp32_s3_sensores.ino` | `iotmotor/esp32-02/telemetry` |

Todos usam `test.mosquitto.org`: **porta 1883 MQTT/TCP nos firmwares** e **`wss://test.mosquitto.org:8081` no navegador**. Prefixo `iotmotor`. A rede Wi-Fi aberta configurada é `IFMA_IOT`; uma rede com portal cativo pode conectar ao Wi-Fi sem permitir acesso ao broker.

## Grandezas e gráficos

A página tem cartões/gráficos de tensão, corrente, potência ativa, potência aparente, potência reativa, fator de potência, frequência, energia, vibração RMS e temperatura. Potência aparente é `V × I`; reativa é calculada a partir da aparente e potência ativa ou fator de potência, quando disponíveis. Campos sem sensor ou sem leitura atual aparecem como `—`. O histórico CSV inclui o `device_id`. Cada módulo tem indicador de frescor: **status MQTT retido não é comprovação de telemetria recente**.

A configuração padrão do firmware ESP32-01 usa **PZEM real**, não números fictícios. Para fazer testes de gráficos sem o sensor, há `DEMO_MODE=1` opcional, e o JSON marca `demo:true`/`data_source:simulated`. O firmware ESP32-S3 usa sensores físicos; o modelo e a pinagem foram baseados na proposta de dois módulos do repositório e precisam de conferência com a montagem real. O painel não mede nada por si: apenas exibe o que os dispositivos publicam.

## Comandos: APENAS bancada sem motor

Comandos vão exclusivamente para `iotmotor/esp32-01/command` com `device_id`, `command`, `mode`, `origin` e `timestamp`, tal como no aplicativo Flutter. O ESP32-S3 não recebe comandos nem tem relé.

- **Partida direta de teste:** só habilitada na página com telemetria recente do ESP32-01, PZEM válido e jumper físico entre GPIO32 e GND. Há confirmação adicional na interface. O firmware aciona apenas a saída de teste GPIO2: **não conecte motor ou contator ao relé** enquanto usar broker público.
- **Parada:** disponível sempre que o MQTT estiver conectado; pode sobrepor uma partida ainda sem resposta.
- **Estrela-triângulo:** aparece no painel, mas fica indisponível. O sketch atual tem somente uma saída; não possui três contatores, intertravamentos ou proteções de máquina. Não trate os modos de software como comandos de potência física.
- A mensagem após um clique diz que o pedido foi publicado; o estado só é atualizado quando o ESP32 publicar telemetria. O campo `motor_on` é estado **solicitado do GPIO**, não leitura real de um contator ou motor.

**Não é seguro operar motor real por broker público sem autenticação**, mesmo que a interface exija confirmação e o firmware tenha um jumper: terceiros podem enviar mensagens, e o GPIO não é uma função de segurança certificada. Para operação real, adote broker autenticado com ACL e TLS, circuito independente de parada, contatores intertravados e proteções elétricas adequadas.

## Publicação no Cloudflare Worker ou Pages

Este repositório contém arquivos estáticos e testes GitHub Actions; os testes **não publicam** no Cloudflare. Se o seu endereço é `*.workers.dev`, publique `index.html` e `dual-dashboard.js` como assets do **Worker**, com a pasta `dashboard-cloudflare` como diretório estático. O arquivo `_headers` é usado no Pages e não substitui configuração de cabeçalhos no Worker.

Se preferir Pages com Git: branch `main`, root `/`, framework `None`, build command `exit 0`, output `dashboard-cloudflare`. Só depois do deploy do Cloudflare concluído as mudanças aparecem no endereço público. Verifique no navegador `/dual-dashboard.js`; se houver 404, o Worker não está servindo esta versão.

Para investigar: primeiro conecte ao broker e observe o diagnóstico individual de `esp32-01` e `esp32-02`. Em cada placa, abra o Monitor Serial a **115200 baud** para verificar Wi-Fi/IP, estado MQTT e leituras físicas. Alterar arquivos no GitHub ou publicar o dashboard **não regrava automaticamente os firmwares**.

O broker público Mosquitto pode ficar temporariamente indisponível: https://test.mosquitto.org/ . Nunca coloque credenciais Wi-Fi, MQTT ou Cloudflare nos arquivos públicos. Revise também versões antigas do repositório que continham senha de Wi-Fi e altere qualquer credencial exposta.
