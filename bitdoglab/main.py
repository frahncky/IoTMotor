"""Painel MQTT BitDogLab para o quadro de comando IoT Motor (MicroPython / Pico W).

Le a telemetria real do quadro (PZEM e estado do motor) e da placa de
sensores (temperatura e vibracao), lista as partidas gravadas no quadro e
envia start/stop pelo protocolo de docs/mqtt.md. Quem aciona
contatores e aplica permissivos, intertravamentos e desarmes e o quadro.

Controles:
  Joystick esq/dir  -> troca a tela
  Joystick cima/baixo (tela Partida) -> escolhe a partida
  A (segurar 1,2 s) -> liga com a partida escolhida
  A (toque)         -> vai para a tela Partida
  B                 -> desliga (sempre enviado)
  SW (joystick)     -> silencia o alarme sonoro

Matriz 5x5: alarme (pisca), Y/triangulo na estrela-triangulo, barra de carga
(corrente/nominal) com o motor ligado, barra de vibracao na tela Sensores e
icone de estado com o motor parado.
"""
import json
import time
import network
from machine import ADC, PWM, Pin, SoftI2C
from umqtt.simple import MQTTClient
import config

PREFIX = getattr(config, "IOTMOTOR_PREFIX", "iotmotor")
BOARD = getattr(config, "IOTMOTOR_BOARD", "esp32-01")
SENSORS = getattr(config, "IOTMOTOR_SENSORS_BOARD", "esp32-02")
T_TELEMETRY = "%s/%s/telemetry" % (PREFIX, BOARD)
T_PROFILES = "%s/%s/profiles" % (PREFIX, BOARD)
T_STATUS = "%s/%s/status" % (PREFIX, BOARD)
T_COMMAND = "%s/%s/command" % (PREFIX, BOARD)
T_ACK = "%s/%s/command_ack" % (PREFIX, BOARD)
T_SENSORS = "%s/%s/telemetry" % (PREFIX, SENSORS)
T_MOTOR_INFO = "%s/%s/motor_info" % (PREFIX, BOARD)
T_ALARMS = "%s/%s/alarms" % (PREFIX, SENSORS)

PAGE_NAMES = ("Eletrica", "Sensores", "Uso", "Partida")
PAGE_PROFILE = 3
LED_LEVEL = int(65535 * getattr(config, "LED_BRIGHTNESS", 0.06))
BUZZER_ON = getattr(config, "BUZZER_ENABLED", True)

# ---------------------------------------------------------------- hardware
a = Pin(config.PIN_BUTTON_A, Pin.IN, Pin.PULL_UP)
b = Pin(config.PIN_BUTTON_B, Pin.IN, Pin.PULL_UP)
sw = Pin(config.PIN_JOYSTICK_BUTTON, Pin.IN, Pin.PULL_UP)
joy_x = ADC(getattr(config, "PIN_JOYSTICK_X", 27))
joy_y = ADC(getattr(config, "PIN_JOYSTICK_Y", 26))
leds = []
for pin in (config.PIN_LED_R, config.PIN_LED_G, config.PIN_LED_B):
    p = PWM(Pin(pin))
    p.freq(1000)
    p.duty_u16(0)
    leds.append(p)
buzzer = PWM(Pin(getattr(config, "PIN_BUZZER", 21)))
buzzer.duty_u16(0)

oled = None
try:
    import ssd1306
    i2c = SoftI2C(sda=Pin(config.PIN_OLED_SDA), scl=Pin(config.PIN_OLED_SCL))
    oled = ssd1306.SSD1306_I2C(128, 64, i2c)
except Exception as exc:
    print("Display OLED indisponivel:", exc)

mat = None
try:
    from matrix import Matrix, GREEN, YELLOW, RED, BLUE, CYAN
    mat = Matrix(getattr(config, "PIN_MATRIX", 7),
                 getattr(config, "MATRIX_BRIGHTNESS", 0.04),
                 getattr(config, "MATRIX_FLIP", False))
    mat.clear()
except Exception as exc:
    print("Matriz de LED indisponivel:", exc)

nic = network.WLAN(network.STA_IF)
nic.active(True)

# ---------------------------------------------------------------- estado
mqtt = None
tele = {}
tele_ms = None
tele_ts_ms = None
sens = {}
sens_ms = None
profiles = []          # [(id, nome_sem_acento)]
profile_cnt = {}       # id e nome -> lista cnt da partida
nominal_a = getattr(config, "MOTOR_NOMINAL_A", None)
vib_limit = getattr(config, "VIBRATION_LIMIT_MMS", 4.5)
sel = 0
pending = None         # (seq, action)
pending_at = 0
message = ""
message_at = 0
seq_counter = 0
page = 0
a_start = None
a_long_done = False
was_a = was_b = was_sw = False
joy_x_dir = joy_y_dir = 0
alarm_muted_key = None
beeps = []             # fila [(freq, ms_ligado, ms_pausa)]
beep_until = 0
beep_off_until = 0
last_wifi_attempt = time.ticks_ms() - 5000
last_ping = time.ticks_ms()
last_alarm_beep = 0

ACCENTS = {
    "á": "a", "à": "a", "â": "a", "ã": "a", "é": "e", "ê": "e", "í": "i",
    "ó": "o", "ô": "o", "õ": "o", "ú": "u", "ç": "c", "Á": "A", "À": "A",
    "Â": "A", "Ã": "A", "É": "E", "Ê": "E", "Í": "I", "Ó": "O", "Ô": "O",
    "Õ": "O", "Ú": "U", "Ç": "C",
}

def ascii_text(text):
    return "".join(ACCENTS.get(ch, ch if ord(ch) < 128 else "?") for ch in str(text))

# ---------------------------------------------------------------- saidas
def led(red=0, green=0, blue=0):
    for p, on in zip(leds, (red, green, blue)):
        p.duty_u16(LED_LEVEL if on else 0)

def beep(*notes):
    """Enfileira bipes: cada nota e (freq, ms_ligado, ms_pausa)."""
    if BUZZER_ON:
        beeps.extend(notes)

CLICK = (2000, 25, 0)
OK_TONE = ((1800, 60, 60), (2400, 90, 0))
FAIL_TONE = ((600, 350, 0),)
ALARM_TONE = ((2600, 150, 100), (2600, 150, 0))

def buzzer_tick(now):
    global beep_until, beep_off_until
    if beep_until and time.ticks_diff(now, beep_until) >= 0:
        buzzer.duty_u16(0)
        beep_until = 0
    if beep_until or time.ticks_diff(now, beep_off_until) < 0 or not beeps:
        return
    freq, on_ms, off_ms = beeps.pop(0)
    buzzer.freq(freq)
    buzzer.duty_u16(32768)
    beep_until = time.ticks_add(now, on_ms)
    beep_off_until = time.ticks_add(beep_until, off_ms)

def show(text):
    global message, message_at
    message = ascii_text(text)
    message_at = time.ticks_ms()
    print(text)

# ---------------------------------------------------------------- MQTT
def callback(topic, raw):
    global tele, tele_ms, tele_ts_ms, profiles, sel, pending, sens, sens_ms
    global profile_cnt, nominal_a, vib_limit
    t = topic.decode() if isinstance(topic, bytes) else topic
    if t == T_STATUS:
        return
    try:
        data = json.loads(raw)
    except (ValueError, TypeError):
        return
    if not isinstance(data, dict):
        return
    if t == T_SENSORS:
        data.pop("vib", None)  # diagnostico por eixo: grande e nao usado aqui
        sens = data
        sens_ms = time.ticks_ms()
    elif t == T_TELEMETRY:
        data.pop("lcd", None)
        tele = data
        tele_ms = time.ticks_ms()
        if data.get("ts"):
            tele_ts_ms = tele_ms
    elif t == T_PROFILES:
        current = profiles[sel][0] if profiles else None
        profiles = [(p.get("id"), ascii_text(p.get("name", p.get("id"))))
                    for p in data.get("profiles", []) if p.get("id")]
        profile_cnt = {}
        for p in data.get("profiles", []):
            for k in (p.get("id"), p.get("name")):
                if k:
                    profile_cnt[k] = p.get("cnt") or []
        ids = [p[0] for p in profiles]
        sel = ids.index(current) if current in ids else 0
    elif t == T_MOTOR_INFO:
        key = "current_y_a" if data.get("connection") == "star" else "current_a"
        if data.get(key):
            nominal_a = float(data[key])
    elif t == T_ALARMS:
        for al in data.get("alarms", []):
            if al.get("field") == "vibration_mms" and al.get("above") and al.get("limit"):
                vib_limit = float(al["limit"])
    elif t == T_ACK:
        if pending and str(data.get("seq")) == pending[0]:
            pending = None
            if data.get("accepted"):
                show("Aceito: " + str(data.get("action")))
                beep(*OK_TONE)
            else:
                show("Recusado: " + str(data.get("reason")))
                beep(*FAIL_TONE)

def wifi_networks():
    nets = getattr(config, "WIFI_NETWORKS", None)
    if nets:
        return list(nets)
    return [(config.WIFI_SSID, config.WIFI_PASSWORD)]

def connect_wifi():
    known = wifi_networks()
    try:
        visible = set(n[0].decode() for n in nic.scan())
    except Exception as exc:
        print("Falha no scan Wi-Fi:", exc)
        visible = None
    candidates = [n for n in known if visible is None or n[0] in visible] or known
    for ssid, password in candidates:
        print("Conectando ao Wi-Fi:", ssid)
        try:
            nic.disconnect()
        except Exception:
            pass
        nic.connect(ssid, password)
        deadline = time.ticks_add(time.ticks_ms(), 12000)
        while not nic.isconnected() and time.ticks_diff(deadline, time.ticks_ms()) > 0:
            time.sleep_ms(200)
        if nic.isconnected():
            print("Wi-Fi conectado:", ssid, nic.ifconfig()[0])
            return
    raise OSError("Wi-Fi indisponivel")

def disconnect():
    global mqtt, pending
    if mqtt:
        try:
            mqtt.disconnect()
        except Exception:
            try:
                mqtt.sock.close()
            except Exception:
                pass
    mqtt = None
    pending = None

def connect():
    global mqtt, last_ping
    if not nic.isconnected():
        connect_wifi()
    mac = nic.config("mac")
    client_id = (config.MQTT_CLIENT_ID + "-%02x%02x%02x" % (mac[-3], mac[-2], mac[-1])).encode()
    user = config.MQTT_USER.encode() if config.MQTT_USER else None
    password = config.MQTT_PASSWORD.encode() if config.MQTT_PASSWORD else None
    use_tls = getattr(config, "MQTT_USE_TLS", False)
    if getattr(config, "MQTT_USE_WEBSOCKET", False):
        from mqtt_websocket import WebSocketMQTTClient
        c = WebSocketMQTTClient(
            client_id, config.MQTT_HOST, port=config.MQTT_PORT,
            path=getattr(config, "MQTT_WEBSOCKET_PATH", "/mqtt"),
            use_tls=use_tls, user=user, password=password, keepalive=45,
        )
    else:
        ssl_params = {"server_hostname": config.MQTT_HOST} if use_tls else {}
        c = MQTTClient(client_id, config.MQTT_HOST, port=config.MQTT_PORT,
                       user=user, password=password, keepalive=45,
                       ssl=use_tls, ssl_params=ssl_params)
    c.set_callback(callback)
    try:
        c.connect()
        for t in (T_STATUS, T_PROFILES, T_ACK, T_TELEMETRY, T_SENSORS, T_MOTOR_INFO, T_ALARMS):
            c.subscribe(t.encode())
    except Exception:
        try:
            c.sock.close()
        except Exception:
            pass
        raise
    mqtt = c
    last_ping = time.ticks_ms()
    print("Conectada ao MQTT: %s:%d" % (config.MQTT_HOST, config.MQTT_PORT))

# ---------------------------------------------------------------- comandos
def fresh(ms):
    return ms is not None and time.ticks_diff(time.ticks_ms(), ms) <= config.TELEMETRY_STALE_MS

def next_seq():
    # O quadro exige seq crescente; painel e app usam Date.now()*1000.
    global seq_counter
    seq_counter = (seq_counter + 1) % 1000
    ms = int(tele["ts"]) * 1000 + time.ticks_diff(time.ticks_ms(), tele_ts_ms)
    return str(ms * 1000 + seq_counter)

def send(action, extra=None):
    global pending, pending_at
    if mqtt is None:
        show("Sem MQTT")
        beep(*FAIL_TONE)
        return
    seq = next_seq() if tele_ts_ms is not None else str(time.ticks_ms())
    cmd = {"v": 1, "device_id": BOARD, "seq": seq, "action": action}
    if extra:
        cmd.update(extra)
    try:
        mqtt.publish(T_COMMAND.encode(), json.dumps(cmd).encode(), retain=False, qos=0)
        pending = (seq, action)
        pending_at = time.ticks_ms()
        print("Enviado:", action)
    except OSError as exc:
        print("Erro ao enviar:", exc)
        disconnect()

def refuse(text):
    show(text)
    beep(*FAIL_TONE)

def request_start():
    if not config.ENABLE_MOTOR_COMMANDS:
        return refuse("Partida desativada")
    if not fresh(tele_ms) or tele_ts_ms is None:
        return refuse("Quadro offline")
    if not profiles:
        return refuse("Sem partidas")
    if tele.get("secure"):
        return refuse("Exige selo")
    if tele.get("actuation") is False:
        return refuse("Instrumentacao")
    if tele.get("motor_running") or any(tele.get("relays") or []):
        return refuse("Ja ligado")
    send("start", {"boot": tele.get("boot"), "profile": profiles[sel][0]})

# ---------------------------------------------------------------- entradas
def joy_dir(adc):
    v = adc.read_u16()
    if v > 50000:
        return 1
    if v < 15000:
        return -1
    return 0

def inputs(now):
    global was_a, was_b, was_sw, a_start, a_long_done, page, sel
    global joy_x_dir, joy_y_dir, alarm_muted_key
    av = a.value() == 0
    bv = b.value() == 0
    sv = sw.value() == 0

    if bv and not was_b:
        beep(CLICK)
        send("stop")  # parar e o lado seguro: vai sempre
    if av and not was_a:
        a_start = now
        a_long_done = False
        beep(CLICK)
    if av and a_start is not None and not a_long_done and not bv:
        if time.ticks_diff(now, a_start) >= config.START_HOLD_MS:
            a_long_done = True
            request_start()
    if not av and was_a:
        if not a_long_done:
            page = PAGE_PROFILE
        a_start = None
    if sv and not was_sw:
        key = alarm_key()
        if key:
            alarm_muted_key = key
            show("Alarme silenciado")
        beep(CLICK)

    dx = joy_dir(joy_x) * getattr(config, "JOYSTICK_X_SIGN", 1)
    dy = joy_dir(joy_y) * getattr(config, "JOYSTICK_Y_SIGN", 1)
    if dx and dx != joy_x_dir:
        page = (page + dx) % len(PAGE_NAMES)
        beep(CLICK)
    if dy and dy != joy_y_dir and page == PAGE_PROFILE and profiles:
        sel = (sel - dy) % len(profiles)  # cima = anterior
        beep(CLICK)
    joy_x_dir, joy_y_dir = dx, dy
    was_a, was_b, was_sw = av, bv, sv

# ---------------------------------------------------------------- alarme
def alarm_key():
    """Identifica o alarme atual; None se nao ha alarme."""
    parts = []
    if fresh(tele_ms) and tele.get("trip_alarm"):
        parts.append("trip:" + str(tele["trip_alarm"]))
    if fresh(sens_ms) and sens.get("alarm_active"):
        parts.append("sens:" + ",".join(sens.get("alarms_firing") or ["?"]))
    return "|".join(parts) or None

def alarm_tick(now):
    global last_alarm_beep, alarm_muted_key
    key = alarm_key()
    if key is None:
        alarm_muted_key = None
        return
    if key != alarm_muted_key and time.ticks_diff(now, last_alarm_beep) > 3000:
        last_alarm_beep = now
        beep(*ALARM_TONE)

# ---------------------------------------------------------------- tela
def number(src, key, fmt):
    try:
        return fmt % float(src[key])
    except (KeyError, TypeError, ValueError):
        return "--"

def duration(seconds):
    try:
        s = int(seconds)
    except (TypeError, ValueError):
        return "--"
    if s < 3600:
        return "%dm%02ds" % (s // 60, s % 60)
    return "%dh%02dm" % (s // 3600, (s % 3600) // 60)

def status_line():
    """Linha de rodape unica: mensagem > comando pendente > estado do motor."""
    if message and time.ticks_diff(time.ticks_ms(), message_at) < 4000:
        return message
    if pending:
        return "Aguardando quadro"
    if mqtt is None:
        return "Sem conexao"
    if not fresh(tele_ms):
        return "Quadro offline"
    if tele.get("trip_alarm"):
        return "DESARME " + ascii_text(tele.get("trip_field") or tele["trip_alarm"])
    if tele.get("motor_running"):
        return "LIGADO " + duration(tele.get("session_s"))
    if any(tele.get("relays") or []):
        return ascii_text(tele.get("start_phase") or "Partindo")
    return "Parado"

def row(y, label, value):
    oled.text(label, 0, y)
    oled.text(value, 128 - 8 * len(value), y)

def render():
    alarm = alarm_key()
    if mqtt is None or not fresh(tele_ms) or alarm:
        led(red=1)
    elif tele.get("motor_running"):
        led(green=1)
    elif any(tele.get("relays") or []):
        led(red=1, green=1)
    else:
        led(blue=1)
    if oled is None:
        return

    oled.fill(0)
    # Cabecalho: nome da tela e indicador de posicao (sem repetir estado).
    oled.text(PAGE_NAMES[page], 0, 0)
    for i in range(len(PAGE_NAMES)):
        x = 128 - 6 * (len(PAGE_NAMES) - i)
        if i == page:
            oled.fill_rect(x, 2, 4, 4, 1)
        else:
            oled.rect(x, 2, 4, 4, 1)
    oled.hline(0, 10, 128, 1)

    if page == 0:
        if fresh(tele_ms) and tele.get("pzem_ok", True):
            row(14, "Tensao", number(tele, "voltage", "%.1f V"))
            row(24, "Corrente", number(tele, "current", "%.2f A"))
            row(34, "Potencia", number(tele, "power", "%.0f W"))
            row(44, "FP", number(tele, "pf", "%.2f"))
        else:
            oled.text("Sem medicao", 20, 28)
    elif page == 1:
        if fresh(sens_ms):
            row(14, "Temp.", number(sens, "temperature", "%.1f C"))
            row(24, "Vibracao", number(sens, "vibration_mms", "%.2f"))
            row(34, "", "mm/s eixo " + str(sens.get("vibration_axis", "-")).upper())
            firing = sens.get("alarms_firing") or []
            if firing:
                oled.text(("Alarme: " + ",".join(firing))[:16], 0, 44)
        else:
            oled.text("Sensores offline", 0, 28)
    elif page == 2:
        if fresh(tele_ms):
            row(14, "Energia", number(tele, "energy", "%.2f kWh"))
            row(24, "Freq.", number(tele, "frequency", "%.1f Hz"))
            row(34, "Horimetro", duration(tele.get("run_s_total")))
            row(44, "Partidas", "%s hoje" % tele.get("starts_today", "--"))
        else:
            oled.text("Sem dados", 28, 28)
    else:
        if not profiles:
            oled.text("Aguardando lista", 0, 28)
        else:
            # Ate 3 partidas visiveis, com a escolhida destacada.
            first = max(0, min(sel - 1, len(profiles) - 3))
            for i, (pid, name) in enumerate(profiles[first:first + 3]):
                y = 14 + 10 * i
                if first + i == sel:
                    oled.fill_rect(0, y - 1, 128, 10, 1)
                    oled.text(name[:16], 0, y, 0)
                else:
                    oled.text(name[:16], 0, y)
            oled.text("Segure A: liga", 0, 44)

    oled.hline(0, 53, 128, 1)
    oled.text(status_line()[:16], 0, 56)
    oled.show()

# ---------------------------------------------------------------- matriz
def star_delta_phase():
    """'star', 'delta', 'dead' ou None, pelos contatores da partida em curso.

    Na partida gravada, o contator que desliga no meio (off > 0) e a estrela;
    o que liga depois desse instante e o triangulo.
    """
    cnt = profile_cnt.get(tele.get("profile"))
    relays = tele.get("relays") or []
    if not cnt or not relays or tele.get("mode") != "profile_bench":
        return None
    star = delta = None
    for i, c in enumerate(cnt):
        if c.get("use") and c.get("off", 0) > 0:
            star = i
    if star is None:
        return None
    for i, c in enumerate(cnt):
        if i != star and c.get("use") and c.get("on", 0) >= cnt[star]["off"]:
            delta = i
    if delta is None:
        return None
    if star < len(relays) and relays[star]:
        return "star"
    if delta < len(relays) and relays[delta]:
        return "delta" if tele.get("profile_ms", 0) < cnt[delta]["on"] + 3000 else None
    return "dead"

def matrix_tick(now):
    if mat is None:
        return
    blink = (now // 400) % 2 == 0
    if mqtt is None or not fresh(tele_ms):
        mat.icon("off", BLUE)
        return
    if alarm_key():
        if blink:
            mat.icon("alert", RED)
        else:
            mat.clear()
        return
    phase = star_delta_phase()
    if phase == "star":
        mat.icon("star", CYAN)
        return
    if phase == "delta":
        mat.icon("delta", CYAN)
        return
    if phase == "dead":
        mat.icon("dash", CYAN)
        return
    running = tele.get("motor_running")
    if page == 1 and running and fresh(sens_ms) and sens.get("vibration_mms") is not None:
        mat.bar(float(sens["vibration_mms"]) / vib_limit)
        return
    if running:
        if nominal_a and tele.get("current") is not None:
            mat.bar(float(tele["current"]) / nominal_a)
        else:
            mat.icon("play", GREEN)
        return
    if any(tele.get("relays") or []):
        if blink:
            mat.icon("play", YELLOW)
        else:
            mat.clear()
        return
    mat.icon("stop", BLUE)

# ---------------------------------------------------------------- laco
def main():
    global last_wifi_attempt, last_ping, pending
    print("BitDogLab: painel do quadro", BOARD)
    print("Partida habilitada:", config.ENABLE_MOTOR_COMMANDS)
    led(blue=1)
    last_ui = 0
    while True:
        now = time.ticks_ms()
        if mqtt is None and time.ticks_diff(now, last_wifi_attempt) > 5000:
            last_wifi_attempt = now
            if oled:
                oled.fill(0)
                oled.text("Conectando...", 0, 28)
                oled.show()
            try:
                connect()
            except Exception as exc:
                print("Falha de conexao:", exc)
                disconnect()
        inputs(now)
        if mqtt:
            try:
                mqtt.check_msg()
                if time.ticks_diff(now, last_ping) > 20000:
                    mqtt.ping()
                    last_ping = now
            except (OSError, MemoryError) as exc:
                print("MQTT caiu:", exc)
                disconnect()
        if pending and time.ticks_diff(now, pending_at) > 10000:
            refuse("Sem resposta")
            pending = None
        alarm_tick(now)
        buzzer_tick(now)
        if time.ticks_diff(now, last_ui) > 250:
            last_ui = now
            render()
            matrix_tick(now)
        time.sleep_ms(20)

main()
