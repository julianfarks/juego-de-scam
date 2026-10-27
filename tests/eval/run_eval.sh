#!/bin/bash
# Ejecuta la evaluación de la IA local para varios modelos y clientes; guarda en $1
OUT=${1:-eval_out}
mkdir -p $OUT
for model in $(ls models_local/*.gguf); do
  name=$(basename $model .gguf)
  for client in chucho agata abuelo; do
    echo "=== $name / $client"
    timeout 1500 godot --headless --path . -s tests/eval/llm_eval.gd -- --model=$PWD/$model --client=$client 2>&1 \
      | grep -E "^>|^<|^   \[|CLIENTE|Modelo|RESUMEN|ERROR" > $OUT/$name-$client.txt
    grep RESUMEN $OUT/$name-$client.txt
  done
done
