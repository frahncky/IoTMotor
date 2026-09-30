"""Testes do coletor. Rodar da raiz do repositório:

    uv run --no-project python -m unittest discover -s tools/coletor -v

O teste de equivalência compara, linha a linha, o CSV do coletor com o do
painel (dual-dashboard.js, pelo Node): as duas planilhas precisam sair iguais.
"""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import coletor as c

RAIZ = Path(__file__).resolve().parents[2]
PAINEL = RAIZ / "dashboard-cloudflare" / "dual-dashboard.js"

QUADRO = {"device_id": "esp32-01", "ts": 1790000000, "voltage": 220.4, "current": 3.1, "power": 540,
          "pf": 0.79, "frequency": 60, "energy": 1.2, "relays": [True, False, False, False],
          "motor_running": True, "mode": "direct", "profile": "direta", "session_s": 12, "pzem_ok": True}
SENSORES = {"device_id": "esp32-02", "ts": 1790000001, "vibration_mms": 2.4, "vibration_axis": "z",
            "temperature": 39.8, "mpu_ok": True, "temperature_ok": True, "sample_count": 1000,
            "vib": {"x": {"mms": 0.4, "a_rms": 0.3, "a_peak": 0.912, "crest": 3.04, "kurt": 3.2,
                          "pk_hz": 29.412, "pk_mms": 0.35, "bands": [i / 1000 for i in range(17)]},
                    "y": {"mms": 1.1, "a_rms": 1, "a_peak": 1.5, "crest": 1.5, "kurt": 1.5},
                    "z": {"mms": 2.4, "a_rms": 0.00001, "a_peak": "7,5", "crest": None, "kurt": 1e21,
                          "pk_hz": 120, "pk_mms": 2.3, "bands": [0.1] * 16}}}

# (quadro, sensores, chegada em ms, condição): casos que o painel e o coletor
# precisam gravar igual, inclusive números e textos difíceis.
CASOS = [
    (QUADRO, SENSORES, 0, "desbalanceamento"),
    (QUADRO, None, 0, ""),
    (None, SENSORES, 0, 'folga, base "solta"'),
    ({**QUADRO, "ts": None, "voltage": "219,5", "current": 0.00001, "power": None, "pf": 0.5,
      "energy": 1e21, "relays": None, "motor_running": None, "mode": 3}, None, 1790000123456, "  x  "),
    ({"device_id": "esp32-01", "data": {"tensao": 127, "i": 2, "w": 300, "motor_on": False, "demo": True}},
     {**SENSORES, "vibration_axis": "w", "temperature": -0.5, "sample_count": "998"}, 1790000000999, "normal"),
]


class TestLeitura(unittest.TestCase):
    def test_quadro(self):
        a = c.ler_telemetria(QUADRO)
        self.assertEqual(a["measuredAt"], 1790000000000)
        self.assertTrue(a["motorOn"])
        self.assertAlmostEqual(a["apparent"], 220.4 * 3.1)
        self.assertEqual(a["vibrationAxis"], "")

    def test_texto_com_virgula_e_invalido(self):
        self.assertEqual(c.numero("219,5"), 219.5)
        self.assertIsNone(c.numero("abc"))
        self.assertIsNone(c.numero(float("nan")))
        self.assertIsNone(c.ler_telemetria([1, 2]))

    def test_vibracao_por_eixo(self):
        v = c.ler_telemetria(SENSORES)["vib"]
        self.assertEqual(v["x"]["pkHz"], 29.412)
        self.assertEqual(len(v["x"]["bands"]), 17)
        self.assertIsNone(v["y"]["bands"])      # Sem espectro (anel enchendo).
        self.assertIsNone(v["z"]["bands"])      # 16 faixas: formato inválido.
        self.assertEqual(v["z"]["aPeak"], 7.5)
        self.assertIsNone(c.ler_vib([1]))
        colunas = c.CABECALHO.split(",")
        self.assertEqual(colunas[-1], "vib_z_b180")
        self.assertEqual(sum(col.startswith("vib_") for col in colunas), 3 * (7 + 17))

    def test_condicao(self):
        self.assertEqual(c.ler_condicao('{"v":1,"condition":"  falta de fase "}'), "falta de fase")
        self.assertEqual(len(c.ler_condicao(json.dumps({"condition": "x" * 60}))), 40)
        self.assertIsNone(c.ler_condicao('{"condition":3}'))
        self.assertIsNone(c.ler_condicao("não é json"))

    def test_numero_como_javascript(self):
        for valor, esperado in [(220.0, "220"), (220.4, "220.4"), (0.00001, "0.00001"),
                                (1e-7, "1e-7"), (1e21, "1e+21"), (1.5e16, "15000000000000000"),
                                (-0.5, "-0.5"), (0, "0"), (3, "3")]:
            self.assertEqual(c.numero_js(valor), esperado)


class TestJuntador(unittest.TestCase):
    def test_uma_linha_por_intervalo_com_as_duas_placas(self):
        j = c.Juntador(record_ms=1000, condicao="normal")
        q, s = c.ler_telemetria(QUADRO), c.ler_telemetria(SENSORES)
        self.assertIsNotNone(j.receber("command", q, 10_000))       # Primeira linha.
        self.assertIsNone(j.receber("sensor", s, 10_200))           # Quadro recente: espera ele.
        linha = j.receber("command", q, 10_950)                     # Folga de 10 %.
        self.assertEqual(linha["vibration_mms"], 2.4)
        self.assertEqual(linha["condicao"], "normal")
        self.assertIsNone(j.receber("command", q, 11_500))          # Cedo demais.

    def test_quadro_fora_do_ar_os_sensores_ditam_o_ritmo(self):
        j = c.Juntador(record_ms=1000)
        j.receber("command", c.ler_telemetria(QUADRO), 0)
        linha = j.receber("sensor", c.ler_telemetria(SENSORES), 5_000)
        self.assertIsNotNone(linha)
        self.assertNotIn("voltage", linha)


class TestGravador(unittest.TestCase):
    def test_um_arquivo_por_dia_com_cabecalho_e_sem_misturar_formato(self):
        with tempfile.TemporaryDirectory() as pasta:
            g = c.Gravador(Path(pasta))
            g.gravar(c.registro_csv(c.ler_telemetria(QUADRO)))
            g.fechar()
            arquivo = Path(pasta) / "iotmotor-coleta-2026-09-21.csv"
            linhas = arquivo.read_text(encoding="utf-8-sig").splitlines()
            self.assertEqual(linhas[0], c.CABECALHO)
            self.assertEqual(len(linhas), 2)
            # Mesmo dia, reabrindo: continua no mesmo arquivo, sem repetir o cabeçalho.
            g = c.Gravador(Path(pasta))
            g.gravar(c.registro_csv(c.ler_telemetria(QUADRO)))
            g.fechar()
            self.assertEqual(len(arquivo.read_text(encoding="utf-8-sig").splitlines()), 3)
            # Arquivo do dia com outro cabeçalho (versão antiga): abre outro.
            arquivo.write_text("outra,coisa\r\n", encoding="utf-8")
            g = c.Gravador(Path(pasta))
            g.gravar(c.registro_csv(c.ler_telemetria(QUADRO)))
            g.fechar()
            self.assertTrue((Path(pasta) / "iotmotor-coleta-2026-09-21-2.csv").exists())


@unittest.skipUnless(shutil.which("node"), "Node não instalado")
class TestIgualAoPainel(unittest.TestCase):
    def test_mesmo_csv_que_o_painel(self):
        script = (
            "const d=require(process.argv[1]);let t='';process.stdin.on('data',x=>t+=x);"
            "process.stdin.on('end',()=>{const casos=JSON.parse(t);"
            "const regs=casos.map(([q,s,at,cond])=>d.registroCsv({command:q&&d.parseTelemetry(q),"
            "sensor:s&&d.parseTelemetry(s),at,condicao:cond}));"
            "process.stdout.write(JSON.stringify(d.linhasCsv(regs)));});"
        )
        saida = subprocess.run(["node", "-e", script, str(PAINEL)], input=json.dumps(CASOS),
                               capture_output=True, text=True, encoding="utf-8", check=True)
        do_painel = json.loads(saida.stdout)
        do_coletor = [c.CABECALHO] + [
            c.linha_csv(c.registro_csv(q and c.ler_telemetria(q), s and c.ler_telemetria(s), at, cond))
            for q, s, at, cond in CASOS]
        self.assertEqual(do_coletor, do_painel)


if __name__ == "__main__":
    unittest.main()
