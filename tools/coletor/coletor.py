# /// script
# requires-python = ">=3.10"
# dependencies = ["paho-mqtt>=2.1"]
# ///
"""Coletor contínuo do IoTMotor: grava a telemetria das duas placas em CSV.

Assina os mesmos tópicos MQTT do painel e grava uma linha por instante com o
quadro de comando (grandezas elétricas) e os sensores do motor (vibração e
temperatura), com as MESMAS colunas do "Exportar CSV" do painel. O código de
treino lê do mesmo jeito o que vem daqui e o que foi exportado do painel.

A coluna `condition` (rótulo do ensaio) vem do campo "Condição" do painel,
publicado no tópico retido <prefixo>/system/condition.

Uso (com o uv, que baixa o Python e a biblioteca MQTT sozinho):

    uv run tools/coletor/coletor.py

Um arquivo por dia (UTC) em tools/coletor/dados/. Ctrl+C encerra.
"""
from __future__ import annotations

import argparse
import json
import logging
import math
import signal
import sys
import threading
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
from urllib.parse import urlparse

# Mesmas regras do painel (dashboard-cloudflare/dual-dashboard.js).
JUNTAR_MS = 3000        # Leitura da outra placa entra na linha se chegou há até 3 s.
FOLGA_REGISTRO = 0.9    # Publicação a cada 1 s chega com atraso variável.
MAX_CONDICAO = 40
REGISTRO_PADRAO_MS = 1000

# Grandeza -> (placa de origem, nomes aceitos no JSON), na ordem do CSV.
METRICAS = [
    ("voltage", "command", ["voltage", "tensao", "v"]),
    ("current", "command", ["current", "corrente", "i"]),
    ("power", "command", ["power", "potencia", "w"]),
    ("apparent", "command", None),   # Calculadas: tensão x corrente.
    ("reactive", "command", None),
    ("pf", "command", ["pf", "power_factor", "fator_potencia", "fp"]),
    ("frequency", "command", ["frequency", "frequencia", "hz"]),
    ("energy", "command", ["energy", "energy_kwh", "energia", "kwh"]),
    ("vibration_mms", "sensor", ["vibration_mms"]),
    ("temperature", "sensor", ["temperature", "temperatura", "temp"]),
]

# Diagnóstico da vibração por eixo (s3-sensors-1.23 em diante): estatísticas
# da aceleração e espectro da velocidade em 17 faixas de 10 Hz (20 a 180 Hz).
VIB_EIXOS = ("x", "y", "z")
VIB_FAIXAS_HZ = [20 + 10 * i for i in range(17)]
VIB_CAMPOS = [  # (coluna, chave, JSON)
    ("mms", "mms", "mms"), ("acc_rms", "aRms", "a_rms"), ("acc_peak", "aPeak", "a_peak"),
    ("crest", "crest", "crest"), ("kurtosis", "kurt", "kurt"),
    ("peak_hz", "pkHz", "pk_hz"), ("peak_mms", "pkMms", "pk_mms"),
]


def _vib(r, eixo, chave, faixa=None):
    e = (r.get("vib") or {}).get(eixo)
    if not e:
        return None
    if faixa is None:
        return e.get(chave)
    return e["bands"][faixa] if e.get("bands") else None


COLUNAS = [
    ("measured_at", lambda r: r["at"]),
    ("clock_source", lambda r: r["clockSource"]),
    ("demo", lambda r: r["demo"]),
    ("condition", lambda r: r["condicao"]),
    ("motor_running", lambda r: r.get("motorOn")),
    ("bench_armed", lambda r: r.get("benchArmed")),
    ("mode", lambda r: r.get("mode")),
    ("profile", lambda r: r.get("profile")),
    ("session_s", lambda r: r.get("sessionS")),
    *[(f"relay_{i + 1}", (lambda i: lambda r: (r.get("relays") or [None] * 4)[i])(i)) for i in range(4)],
    ("pzem_ok", lambda r: r.get("pzemOk")),
    ("mpu_ok", lambda r: r.get("mpuOk")),
    ("temperature_ok", lambda r: r.get("temperatureOk")),
    ("vibration_samples", lambda r: r.get("sampleCount")),
    ("vibration_axis", lambda r: r.get("vibrationAxis")),
    *[(chave, (lambda k: lambda r: r.get(k))(chave)) for chave, _, _ in METRICAS],
    # vib_x_mms ... vib_z_b180: por eixo, as estatísticas e depois as faixas.
    *[col for e in VIB_EIXOS for col in (
        *[(f"vib_{e}_{nome}", (lambda e, k: lambda r: _vib(r, e, k))(e, k)) for nome, k, _ in VIB_CAMPOS],
        *[(f"vib_{e}_b{hz:03d}", (lambda e, i: lambda r: _vib(r, e, None, i))(e, i))
          for i, hz in enumerate(VIB_FAIXAS_HZ)],
    )],
]
CABECALHO = ",".join(nome for nome, _ in COLUNAS)

log = logging.getLogger("coletor")


# ---------------------------------------------------------------- leitura

def numero(v):
    """Como o numeric() do painel: número finito, texto com vírgula ou None."""
    if v is None or v == "":
        return None
    if isinstance(v, bool):
        return float(v)
    if isinstance(v, (int, float)):
        n = float(v)
    elif isinstance(v, str):
        try:
            n = float(v.replace(",", ".", 1))
        except ValueError:
            return None
    else:
        return None
    return n if math.isfinite(n) else None


def _bool(v):
    return v if isinstance(v, bool) else None


def ler_vib(v):
    """Como o lerVib() do painel."""
    if not isinstance(v, dict):
        return None
    out = {}
    for e in VIB_EIXOS:
        x = v.get(e)
        if not isinstance(x, dict):
            continue
        out[e] = {k: numero(x.get(json_)) for _, k, json_ in VIB_CAMPOS}
        faixas = x.get("bands")
        out[e]["bands"] = [numero(f) for f in faixas] \
            if isinstance(faixas, list) and len(faixas) == len(VIB_FAIXAS_HZ) else None
    return out or None


def ler_telemetria(obj):
    """Como o parseTelemetry() do painel, só com o que vai para o CSV."""
    if not isinstance(obj, dict):
        return None
    fonte = obj["data"] if isinstance(obj.get("data"), dict) else obj
    reles = fonte.get("relays")
    if not (isinstance(reles, list) and len(reles) == 4 and all(isinstance(x, bool) for x in reles)):
        reles = None
    if isinstance(fonte.get("motor_on"), bool):
        ligado = fonte["motor_on"]
    elif isinstance(fonte.get("motor_running"), bool):
        ligado = fonte["motor_running"]
    else:
        ligado = any(reles) if reles else None
    ts = fonte.get("ts")
    medido = ts * 1000 if isinstance(ts, (int, float)) and not isinstance(ts, bool) \
        and math.isfinite(ts) and ts > 1700000000 else None
    eixo = fonte.get("vibration_axis")
    a = {
        "deviceId": str(obj.get("device_id") or fonte.get("device_id") or ""),
        "demo": obj.get("demo") is True or fonte.get("demo") is True or fonte.get("data_source") == "simulated",
        "measuredAt": medido,
        "benchArmed": fonte.get("bench_armed") is True,
        "motorOn": ligado,
        "mode": fonte["mode"] if isinstance(fonte.get("mode"), str) else "—",
        "profile": fonte["profile"] if isinstance(fonte.get("profile"), str) else "",
        "relays": reles,
        "sessionS": numero(fonte.get("session_s")),
        "pzemOk": _bool(fonte.get("pzem_ok")),
        "mpuOk": _bool(fonte.get("mpu_ok")),
        "temperatureOk": _bool(fonte.get("temperature_ok")),
        "sampleCount": numero(fonte.get("sample_count")),
        "vibrationAxis": eixo if eixo in ("x", "y", "z") else "",
        "vib": ler_vib(fonte.get("vib")),
    }
    for chave, _, nomes in METRICAS:
        if nomes:
            a[chave] = next((n for n in (numero(fonte.get(k)) for k in nomes) if n is not None), None)
    v, i, p, fp = a["voltage"], a["current"], a["power"], a["pf"]
    a["apparent"] = v * i if v is not None and i is not None else None
    s = a["apparent"]
    if s is None:
        a["reactive"] = None
    elif p is not None:
        a["reactive"] = math.sqrt(max(0.0, s ** 2 - p ** 2))
    elif fp is not None:
        a["reactive"] = s * math.sqrt(max(0.0, 1 - fp ** 2))
    else:
        a["reactive"] = None
    return a


def ler_condicao(texto):
    """{"v":1,"condition":"..."} -> texto aparado; None se inválido."""
    try:
        dados = json.loads(texto)
    except (ValueError, TypeError):
        return None
    if not isinstance(dados, dict) or not isinstance(dados.get("condition"), str):
        return None
    return dados["condition"].strip()[:MAX_CONDICAO]


# ------------------------------------------------------------------- linha

def iso_ms(ms):
    """Como o toISOString() do JavaScript: 2026-09-30T12:00:00.000Z."""
    ms = int(math.floor(ms))
    d = datetime.fromtimestamp(ms // 1000, timezone.utc)
    return d.strftime("%Y-%m-%dT%H:%M:%S.") + f"{ms % 1000:03d}Z"


def registro_csv(command=None, sensor=None, at=0, condicao=""):
    """Como o registroCsv() do painel."""
    base = command or sensor
    medido = base.get("measuredAt") if base else None
    linha = {
        "at": iso_ms(medido if medido is not None else at),
        "clockSource": "placa" if medido else "navegador",
        "demo": bool((command or {}).get("demo") or (sensor or {}).get("demo")),
        "condicao": str(condicao or "").strip()[:MAX_CONDICAO],
    }
    if command:
        linha.update(
            motorOn=command["motorOn"], benchArmed=command["benchArmed"],
            mode="" if command["mode"] == "—" else command["mode"],
            profile=command["profile"], sessionS=command["sessionS"], pzemOk=command["pzemOk"],
        )
        if command["relays"]:
            linha["relays"] = list(command["relays"])
    if sensor:
        linha.update(mpuOk=sensor["mpuOk"], temperatureOk=sensor["temperatureOk"],
                     sampleCount=sensor["sampleCount"], vibrationAxis=sensor["vibrationAxis"])
        if sensor.get("vib"):
            linha["vib"] = sensor["vib"]
    for chave, origem, _ in METRICAS:
        amostra = command if origem == "command" else sensor
        if amostra and amostra.get(chave) is not None:
            linha[chave] = amostra[chave]
    return linha


def numero_js(x):
    """Número como o String() do JavaScript (220 e não 220.0; 1e-7; 1e+21)."""
    if x == 0:
        return "0"
    sinal = "-" if x < 0 else ""
    d = Decimal(repr(abs(float(x)))).normalize()
    _, digitos, exp = d.as_tuple()
    s = "".join(map(str, digitos))
    k, n = len(s), exp + len(s)
    if k <= n <= 21:
        texto = s + "0" * (n - k)
    elif 0 < n <= 21:
        texto = s[:n] + "." + s[n:]
    elif -6 < n <= 0:
        texto = "0." + "0" * (-n) + s
    else:
        e = n - 1
        texto = s[0] + ("." + s[1:] if k > 1 else "") + "e" + ("+" if e >= 0 else "-") + str(abs(e))
    return sinal + texto


def celula_csv(v):
    """Como o celulaCsv() do painel."""
    if v is None:
        return ""
    if isinstance(v, bool):
        s = "true" if v else "false"
    elif isinstance(v, (int, float)):
        s = numero_js(v)
    else:
        s = str(v)
    return '"' + s.replace('"', '""') + '"' if any(c in s for c in '",\r\n') else s


def linha_csv(registro):
    return ",".join(celula_csv(ler(registro)) for _, ler in COLUNAS)


# ---------------------------------------------------------------- juntador

@dataclass
class Juntador:
    """Junta as duas placas numa linha por intervalo, como o registrar() do painel."""
    record_ms: int = REGISTRO_PADRAO_MS
    condicao: str = ""
    amostra: dict = field(default_factory=lambda: {"command": None, "sensor": None})
    chegou: dict = field(default_factory=lambda: {"command": 0.0, "sensor": 0.0})
    ultimo: float = 0.0

    def receber(self, qual, amostra, agora_ms):
        """Guarda a amostra; devolve a linha a gravar ou None."""
        self.amostra[qual], self.chegou[qual] = amostra, agora_ms
        recente = lambda x: self.amostra[x] is not None and agora_ms - self.chegou[x] <= JUNTAR_MS
        # O quadro dita o ritmo; sem ele, os sensores.
        if qual == "sensor" and recente("command"):
            return None
        if agora_ms - self.ultimo < self.record_ms * FOLGA_REGISTRO:
            return None
        self.ultimo = agora_ms
        return registro_csv(self.amostra["command"] if recente("command") else None,
                            self.amostra["sensor"] if recente("sensor") else None,
                            agora_ms, self.condicao)


# ------------------------------------------------------------------ arquivo

class Gravador:
    """Um CSV por dia (UTC), com o cabeçalho do painel e BOM para o Excel."""

    def __init__(self, pasta: Path):
        self.pasta = pasta
        self.pasta.mkdir(parents=True, exist_ok=True)
        self.dia = None
        self.arquivo = None
        self.linhas = 0

    def _abrir(self, dia):
        self.fechar()
        caminho = self.pasta / f"iotmotor-coleta-{dia}.csv"
        n = 1
        # Arquivo do mesmo dia com outras colunas (versão anterior): não mistura.
        while caminho.exists() and caminho.stat().st_size and self._cabecalho(caminho) != CABECALHO:
            n += 1
            caminho = self.pasta / f"iotmotor-coleta-{dia}-{n}.csv"
        novo = not caminho.exists() or caminho.stat().st_size == 0
        self.arquivo = open(caminho, "a", encoding="utf-8", newline="")
        if novo:
            self.arquivo.write("﻿" + CABECALHO + "\r\n")
        self.dia = dia
        log.info("gravando em %s", caminho)

    @staticmethod
    def _cabecalho(caminho):
        with open(caminho, encoding="utf-8-sig") as f:
            return f.readline().rstrip("\r\n")

    def gravar(self, registro):
        dia = registro["at"][:10]
        if dia != self.dia:
            self._abrir(dia)
        self.arquivo.write(linha_csv(registro) + "\r\n")
        self.arquivo.flush()  # Uma queda de energia perde no máximo a linha em curso.
        self.linhas += 1

    def fechar(self):
        if self.arquivo:
            self.arquivo.close()
            self.arquivo = None


# --------------------------------------------------------------------- MQTT

class Coletor:
    def __init__(self, args):
        self.args = args
        self.prefixo = args.prefixo
        self.topicos = {
            f"{self.prefixo}/{args.quadro}/telemetry": "command",
            f"{self.prefixo}/{args.sensores}/telemetry": "sensor",
        }
        self.ids = {"command": args.quadro, "sensor": args.sensores}
        self.t_aquisicao = f"{self.prefixo}/system/acquisition"
        self.t_condicao = f"{self.prefixo}/system/condition"
        self.juntador = Juntador(record_ms=args.registro_ms or REGISTRO_PADRAO_MS)
        self.gravador = Gravador(Path(args.saida))
        self.trava = threading.Lock()
        self.caiu_em = None

    def ao_conectar(self, cliente, _dados, _flags, codigo, _props):
        if codigo.is_failure:
            log.error("broker recusou a conexão: %s", codigo)
            return
        if self.caiu_em is not None:
            log.warning("reconectado; %.0f s sem dados (buraco na coleta)", time.time() - self.caiu_em)
            self.caiu_em = None
        else:
            log.info("conectado ao broker")
        cliente.subscribe([(t, 0) for t in (*self.topicos, self.t_aquisicao, self.t_condicao)])

    def ao_desconectar(self, _cliente, _dados, _flags, codigo, _props):
        if self.caiu_em is None:
            self.caiu_em = time.time()
        log.warning("desconectado do broker (%s); tentando de novo", codigo)

    def ao_receber(self, _cliente, _dados, msg):
        texto = msg.payload.decode("utf-8", "replace")
        with self.trava:
            if msg.topic == self.t_condicao:
                condicao = ler_condicao(texto)
                if condicao is not None and condicao != self.juntador.condicao:
                    self.juntador.condicao = condicao
                    log.info("condição do ensaio: %s", condicao or "(não informada)")
                return
            if msg.topic == self.t_aquisicao:
                self._aquisicao(texto)
                return
            qual = self.topicos.get(msg.topic)
            if not qual or msg.retain:  # Telemetria retida é velha: o painel também ignora.
                return
            try:
                amostra = ler_telemetria(json.loads(texto))
            except ValueError:
                return
            if not amostra or amostra["deviceId"] != self.ids[qual]:
                return
            registro = self.juntador.receber(qual, amostra, time.time() * 1000)
            if registro:
                self.gravador.gravar(registro)

    def _aquisicao(self, texto):
        # Segue o "Registro de dados" do painel, a menos que --registro-ms mande.
        if self.args.registro_ms:
            return
        try:
            ms = json.loads(texto).get("record_ms")
        except (ValueError, AttributeError):
            return
        if isinstance(ms, int) and not isinstance(ms, bool) and 100 <= ms <= 600000 \
                and ms != self.juntador.record_ms:
            self.juntador.record_ms = ms
            log.info("registro a cada %d ms (configuração do painel)", ms)

    def situacao(self):
        with self.trava:
            agora = time.time() * 1000
            idade = lambda q: f"{(agora - self.juntador.chegou[q]) / 1000:.0f} s" \
                if self.juntador.chegou[q] else "nunca"
            return (f"{self.gravador.linhas} linhas gravadas; quadro há {idade('command')}, "
                    f"sensores há {idade('sensor')}; condição: {self.juntador.condicao or '(não informada)'}")


def criar_cliente(url):
    import paho.mqtt.client as mqtt  # Só aqui: os testes rodam sem a biblioteca.

    u = urlparse(url)
    esquema = u.scheme.lower()
    if esquema not in ("mqtt", "mqtts", "ws", "wss") or not u.hostname:
        raise SystemExit(f"broker inválido: {url} (use mqtt://, mqtts://, ws:// ou wss://)")
    web = esquema in ("ws", "wss")
    porta = u.port or {"mqtt": 1883, "mqtts": 8883, "ws": 80, "wss": 443}[esquema]
    cliente = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                          client_id=f"iotmotor_coletor_{uuid.uuid4().hex[:9]}",
                          transport="websockets" if web else "tcp")
    if web:
        cliente.ws_set_options(path=u.path or "/mqtt")
    if esquema in ("mqtts", "wss"):
        cliente.tls_set()
    cliente.reconnect_delay_set(min_delay=1, max_delay=30)
    return cliente, u.hostname, porta


def main(argv=None):
    p = argparse.ArgumentParser(description="Grava a telemetria do IoTMotor em CSV, continuamente.")
    p.add_argument("--broker", default="wss://iotmotor.pages.dev/mqtt",
                   help="padrão: a ponte do painel na Cloudflare (porta 443, passa em rede que bloqueia o broker)")
    p.add_argument("--prefixo", default="iotmotor")
    p.add_argument("--quadro", default="esp32-01", help="id da placa do quadro de comando")
    p.add_argument("--sensores", default="esp32-02", help="id da placa dos sensores do motor")
    p.add_argument("--saida", default=str(Path(__file__).resolve().parent / "dados"),
                   help="pasta dos CSV (um por dia, em UTC)")
    p.add_argument("--registro-ms", type=int, default=None,
                   help="intervalo entre linhas; sem isso, segue o 'Registro de dados' do painel")
    p.add_argument("--situacao-s", type=int, default=60, help="a cada quantos segundos mostrar a situação")
    args = p.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s",
                        datefmt="%Y-%m-%d %H:%M:%S")
    coletor = Coletor(args)
    cliente, host, porta = criar_cliente(args.broker)
    cliente.on_connect = coletor.ao_conectar
    cliente.on_disconnect = coletor.ao_desconectar
    cliente.on_message = coletor.ao_receber

    parar = threading.Event()
    signal.signal(signal.SIGINT, lambda *_: parar.set())
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, lambda *_: parar.set())

    log.info("conectando a %s", args.broker)
    cliente.connect_async(host, porta, keepalive=30)
    cliente.loop_start()
    try:
        # Espera de 1 s em 1 s: no Windows, uma espera longa só vê o Ctrl+C no fim.
        segundos = 0
        while not parar.wait(1):
            segundos += 1
            if segundos % max(1, args.situacao_s) == 0:
                log.info(coletor.situacao())
    finally:
        cliente.disconnect()
        cliente.loop_stop()
        with coletor.trava:
            coletor.gravador.fechar()
        log.info("encerrado. %s", coletor.situacao())
    return 0


if __name__ == "__main__":
    sys.exit(main())
