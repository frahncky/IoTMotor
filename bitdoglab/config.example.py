# Copie para config.py na memoria da BitDogLab e configure os dados reais.
# NAO publique config.py com credenciais.
WIFI_SSID = "SUA_REDE"
WIFI_PASSWORD = "SUA_SENHA"
# Opcional: redes tentadas em ordem (tem prioridade sobre WIFI_SSID).
WIFI_NETWORKS = [
    ("SUA_REDE", "SUA_SENHA"),
    ("REDE_RESERVA", "SENHA_RESERVA"),
]

# Use o MESMO broker MQTT do painel e do app IoTMotor.
MQTT_HOST = "test.mosquitto.org"
MQTT_PORT = 8080  # WebSocket; a rede do IFMA bloqueia 1883
MQTT_USE_TLS = False
MQTT_USE_WEBSOCKET = True
MQTT_WEBSOCKET_PATH = "/mqtt"
MQTT_USER = ""
MQTT_PASSWORD = ""
MQTT_CLIENT_ID = "iotmotor-bitdoglab"

# Quadro de comando do IoT Motor (protocolo em docs/mqtt.md).
# Topicos: <PREFIX>/<BOARD>/telemetry, profiles, status, command, command_ack.
IOTMOTOR_PREFIX = "iotmotor"
IOTMOTOR_BOARD = "esp32-01"
IOTMOTOR_SENSORS_BOARD = "esp32-02"  # temperatura e vibracao

# True: botao A (segurar) envia "start" da partida escolhida.
# "stop" (botao B) e sempre enviado. Permissivos e protecoes ficam no quadro.
ENABLE_MOTOR_COMMANDS = False

# Mapeamento da BitDogLab v6.3 com Raspberry Pi Pico W.
# Verifique a revisao fisica antes de usar com outra versao.
PIN_BUTTON_A = 5
PIN_BUTTON_B = 6
PIN_OLED_SDA = 14
PIN_OLED_SCL = 15
PIN_LED_R = 13
PIN_LED_G = 11
PIN_LED_B = 12
PIN_JOYSTICK_X = 27   # ADC1
PIN_JOYSTICK_Y = 26   # ADC0
JOYSTICK_X_SIGN = 1   # troque para -1 se esquerda/direita estiverem invertidas
JOYSTICK_Y_SIGN = 1   # troque para -1 se cima/baixo estiverem invertidos
LED_BRIGHTNESS = 0.06  # 0.0 a 1.0
# Buzzer e matriz 5x5 nao sao usados; o programa so os mantem desligados.
PIN_BUZZER = 21
PIN_MATRIX = 7
START_HOLD_MS = 1200
TELEMETRY_STALE_MS = 15000
