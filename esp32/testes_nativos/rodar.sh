#!/usr/bin/env bash
# Testes da logica do firmware no PC, sem placa: compila os cabecalhos reais
# das duas placas com g++ contra um Arduino de mentira (fakes/) e roda.
#
#   bash esp32/testes_nativos/rodar.sh
#
# Precisa de g++ com C++17. Na primeira vez baixa o ArduinoJson 6.21.5 (a
# versao do firmware publicado) para .cache/.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .cache/bin
json=.cache/ArduinoJson-v6.21.5.h
if [ ! -f "$json" ]; then
  curl -sSfL -o "$json" \
    https://github.com/bblanchon/ArduinoJson/releases/download/v6.21.5/ArduinoJson-v6.21.5.h
fi
falhas=0
for fonte in teste_*.cpp; do
  nome="${fonte%.cpp}"
  echo "== $nome"
  g++ -std=gnu++17 -Wall -Wextra -Wno-unused-function -Wno-unused-parameter \
      -I fakes -o ".cache/bin/$nome" "$fonte"
  ".cache/bin/$nome" || falhas=$((falhas + 1))
done
[ "$falhas" -eq 0 ] || { echo "$falhas conjunto(s) com falha"; exit 1; }
