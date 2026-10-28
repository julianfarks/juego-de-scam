#!/bin/bash
# Conversaciones libres con la IA local (mismo código que el juego) para varios
# clientes y guiones; guarda transcripciones en $1
OUT=${1:-eval_out}
mkdir -p $OUT
for model in $(ls models_local/*.gguf); do
  name=$(basename $model .gguf)
  for pair in chucho:queso remedios:queso profesor:queso maruja:queso brayan:queso ingeniera:jardin pilar:jardin oscar:jardin; do
    client=${pair%%:*}; script=${pair##*:}
    echo "=== $name / $client / $script"
    timeout 2400 godot --headless --path . -s tests/eval/call_eval.gd -- --model=$PWD/$model --client=$client --script=$script 2>&1 \
      | grep -E "^>|^<|^   \[|CLIENTE|Modelo|RESUMEN|MEMORIA|PROPUESTA FINAL|ERROR|SCRIPT ERROR" > $OUT/$name-$client-$script.txt
    grep RESUMEN $OUT/$name-$client-$script.txt
  done
done
