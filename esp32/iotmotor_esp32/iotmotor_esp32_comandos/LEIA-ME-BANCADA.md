# Firmware IoTMotor ESP32-01 — bancada

Este arquivo descreve `iotmotor_esp32_comandos.ino` (versão `bench-2.0`). O código do GitHub **não atualiza a placa sozinho**: compile e grave o `.ino` no ESP32 pela IDE Arduino. Configure a placa ESP32 Dev Module, velocidade Serial de **115200 baud**, e instale **PubSubClient** e **ArduinoJson 6.x**.

## Antes de ligar

**Somente testes com LED ou saída de relé SEM motor ou contator conectado.** O servidor `test.mosquitto.org` é público, usa MQTT TCP sem autenticação na porta 1883, e terceiros podem enviar mensagens. Não é uma arquitetura adequada a acionamento real. O firmware de teste não substitui intertravamentos, contatores, relé térmico, dispositivos de proteção, parada de emergência e avaliação de riscos.

- Wi-Fi aberto `IFMA_IOT`; o ESP32 se conecta por `WiFi.begin(WIFI_SSID)` quando não há senha. Redes com portal cativo podem conectar ao ponto de acesso sem liberar Internet.
- MQTT no ESP32: `test.mosquitto.org:1883`. No navegador HTTPS: `wss://test.mosquitto.org:8081`. Prefixo `iotmotor`, dispositivo `esp32-01`.
- Monitor Serial 115200 mostra conexão Wi-Fi, IP, MQTT e publicação. Se o broker falhar, imprima e informe o `mqtt.state()`.
- `GPIO2` é a saída preservada do sketch anterior. `GPIO32` é um **jumper local de habilitação**, configurado `INPUT_PULLUP`; somente curto temporário entre **GPIO32 e GND** autoriza partida de teste. Não aplique tensão externa no GPIO. Retirar o jumper ou perder Wi-Fi/MQTT desliga a saída por software (não é função de segurança certificada).
- O comando `stop` é aceito mesmo sem jumper. `start` aceita apenas `mode: direct` e `device_id: esp32-01`. `star_delta` é recusado porque um único relé não consegue fazer partida estrela-triângulo com intertravamento. O firmware não assina o tópico genérico `/request/command`.
- A página web exige confirmação explícita antes de enviar partida, telemetria recente com `bench_armed: true`, e só confirma acionamento após retorno do ESP32. Isso **não autentica** comandos no broker público.

## Medições e sensores

Por padrão, `DEMO_MODE=1`: o firmware publica `voltage`, `current`, `power`, `pf`, `frequency`, `energy`, `vibration` e `temperature` **simulados** para exercitar os gráficos. Cada mensagem contém `demo: true` e `data_source: simulated`; a página exibe esse aviso. Nenhum valor simulado é uma medição física.

Para medições reais, configure `DEMO_MODE=0`, habilite cada sensor realmente instalado e instale as bibliotecas correspondentes:

| Macro | Hardware e bibliotecas | Dados |
| --- | --- | --- |
| `USE_PZEM=1` | PZEM-004T v3; `PZEM004Tv30`; TX do PZEM no GPIO16 (RX2), RX no GPIO17 (TX2), GND comum | Tensão, corrente, potência ativa, FP, frequência, energia |
| `USE_DS18B20=1` | DS18B20 no GPIO4 com pull-up 4,7 kΩ para 3,3 V; `OneWire`, `DallasTemperature` | Temperatura |
| `USE_MPU6050=1` | MPU6050 alimentado em 3,3 V, SDA 21, SCL 22; `Wire` do core | Estimativa RMS da variação de aceleração em g; exige calibração para diagnóstico de vibração |

**Atenção a tensões de rede:** não faça ligações de PZEM/contatores em circuito energizado sem infraestrutura e pessoal qualificado. Confirme isolamento, alimentações, aterramento e compatibilidade elétrica na bancada. Quando a leitura do sensor não for válida, o campo correspondente **não é enviado**. O painel mostra “Sem leitura”. Potência aparente `S=V·I` e reativa `Q=√max(0,S²−P²)` são calculadas na interface apenas quando os valores de entrada estiverem disponíveis.

## Tópicos

- Telemetria QoS 0 **não retida**: `iotmotor/esp32-01/telemetry`, com `seq`, `demo`, `bench_armed`, `motor_on`, `mode` e os campos disponíveis.
- Status retido: `iotmotor/esp32-01/status`. Uma mensagem retida não prova que a placa esteja online.
- Comando dirigido: `iotmotor/esp32-01/command` com JSON `{ "device_id": "esp32-01", "command": "start", "mode": "direct", "origin": "web_bench" }`; para parar use `"command": "stop", "mode": "manual_stop"`.
- Capacidades retidas: `iotmotor/esp32-01/capabilities`.

Se trocar de placa, atualizar o firmware, conectar sensores ou fazer alterações no GitHub, **é preciso gravar novamente o ESP32**; atualizar o site Cloudflare não atualiza o firmware.
