#!/bin/bash
# Ejecuta las evaluaciones de la IA local y guarda las salidas en $1
OUT=${1:-eval_out}
mkdir -p $OUT
M=models_local
for model in qwen3.5-2b-q4km qwen3.5-0.8b-q4km; do
  for client in chucho remedios agata abuelo estrella; do
    echo "=== $model / $client"
    timeout 900 godot --headless --path . -s tests/eval/llm_eval.gd -- --model=$PWD/$M/$model.gguf --client=$client 2>&1 | grep -vE "^\s*$" > $OUT/$model-$client.txt
    tail -3 $OUT/$model-$client.txt
  done
done
