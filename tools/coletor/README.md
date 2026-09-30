# Coletor contínuo

Grava a telemetria das duas placas em CSV, sem painel aberto e sem o limite de
uma hora do navegador. Serve para montar o conjunto de dados de treino da
detecção e da classificação de falhas.

- **Uma linha por instante** com o quadro de comando e os sensores do motor,
  com as **mesmas colunas** do **Exportar CSV** do painel (veja o
  [guia de uso](../../docs/guia-de-uso.md)). O mesmo código de treino lê as duas.
- **Um arquivo por dia** (data em UTC, como a coluna `measured_at`) em
  `tools/coletor/dados/iotmotor-coleta-AAAA-MM-DD.csv`. A 1 linha por segundo,
  são ~86 mil linhas e ~17 MB por dia.
- O intervalo entre linhas segue o **Registro de dados** configurado no painel.

## Instalar

Só o [uv](https://docs.astral.sh/uv/getting-started/installation/). Ele baixa
o Python e a biblioteca MQTT na primeira execução, sem mexer no sistema:

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

## Rodar

Da raiz do repositório:

```powershell
uv run tools/coletor/coletor.py
```

A cada minuto ele mostra quantas linhas gravou, há quanto tempo cada placa
publicou e a condição em uso. **Ctrl+C** encerra. Para coletar sem parar,
deixe o PC sem suspender (Configurações › Energia).

| Opção | Padrão | Para quê |
|---|---|---|
| `--broker` | `wss://iotmotor.pages.dev/mqtt` | A ponte do painel, na porta 443: passa em rede que bloqueia o broker. Também aceita `mqtt://test.mosquitto.org:1883` |
| `--saida` | `tools/coletor/dados` | Pasta dos CSV |
| `--registro-ms` | o do painel | Fixa o intervalo entre linhas |
| `--quadro`, `--sensores`, `--prefixo` | `esp32-01`, `esp32-02`, `iotmotor` | Os mesmos do painel |

## Rotular os ensaios

A coluna `condition` vem do campo **Condição** do painel (cartão **Gráficos
em tempo real**). O painel publica o texto no tópico retido
`iotmotor/system/condition`, e o coletor passa a gravá-lo nas linhas seguintes.

1. Antes do ensaio, escreva a condição no painel (por exemplo, `desbalanceamento`)
   com ele **conectado** ao MQTT. O coletor mostra `condição do ensaio: ...` no log.
2. Rode o ensaio.
3. Ao terminar, troque para `normal` ou apague o campo.

Grave bastante operação `normal`, em cargas e temperaturas diferentes: é a
referência da detecção de anomalia.

## Buracos na coleta

Se a rede ou o broker caírem, o coletor reconecta sozinho e registra no log
quanto tempo ficou sem dados. As linhas não são inventadas: o buraco aparece
como um salto em `measured_at`.

O broker é público. O coletor só aceita telemetria com o `device_id` certo, como
o painel, mas qualquer pessoa pode publicar nos tópicos. Confira os dados antes
de treinar.

## Testes

```powershell
uv run --no-project python -m unittest discover -s tools/coletor -v
```

Um dos testes compara, linha a linha, o CSV do coletor com o do painel
(`dual-dashboard.js`, pelo Node). Se mudar as colunas de um, o teste exige
mudar o outro.
