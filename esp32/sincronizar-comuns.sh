#!/usr/bin/env bash
# Copia os cabecalhos comuns (mesmo nome nas duas placas: Wi-Fi, OTA, selo,
# vigia, relogio...) de uma pasta para a outra. O CI recusa as duas copias
# diferentes; editar de um lado e rodar isto evita esquecer a outra placa.
#
#   bash esp32/sincronizar-comuns.sh            # do quadro para os sensores
#   bash esp32/sincronizar-comuns.sh sensores   # dos sensores para o quadro
#
# Nao toca em wifi_local.h nem comando_local.h: sao de cada gravacao.
set -euo pipefail
cd "$(dirname "$0")/iotmotor_esp32"
quadro=iotmotor_esp32_comandos
sensores=iotmotor_esp32_s3_sensores
if [ "${1:-quadro}" = sensores ]; then origem=$sensores; destino=$quadro; else origem=$quadro; destino=$sensores; fi
copiados=0
for arquivo in "$origem"/*.h; do
  nome=$(basename "$arquivo")
  case "$nome" in *_local.h) continue ;; esac
  [ -f "$destino/$nome" ] || continue
  if ! cmp -s "$arquivo" "$destino/$nome"; then
    cp "$arquivo" "$destino/$nome"
    echo "copiado: $nome ($origem -> $destino)"
    copiados=$((copiados + 1))
  fi
done
echo "$copiados arquivo(s) atualizado(s)."
