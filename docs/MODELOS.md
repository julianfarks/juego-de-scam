# Modelos de IA que usa TeleTimo 3D

Todo funciona **dentro del dispositivo** con la extensión [NobodyWho](https://github.com/nobodywho-ooo/nobodywho) (licencia EUPL‑1.2, permite uso comercial). No hay servidores, cuentas ni claves.

| Función | Modelo | Licencia | Tamaño de descarga |
|---|---|---|---|
| Conversación de los clientes y del jefe | **Gemma 4 E2B** instruido, Q4_K_M (`NobodyWho/Google_Gemma4-E2B-GGUF`) | Apache‑2.0 | 3,1 GB |
| Conversación en móviles con menos de 5 GB de RAM | Qwen3.5 0.8B, Q4_K_M (`NobodyWho/Qwen_Qwen3.5-0.8B-GGUF`) — peor calidad | Apache‑2.0 | 0,5 GB |
| Voz a texto | Whisper base (ONNX, `onnx-community/whisper-base`) | MIT | 145 MB |
| Detección de voz | Silero VAD (ONNX, `onnx-community/silero-vad`) | MIT | 2 MB |
| Voces | Kokoro‑82M (`NobodyWho/Kokoro-82M`, voces `ef_dora` y `em_alex`) | Apache‑2.0 | 327 MB |

## De dónde se descargan

1. **Release «modelos» de este repositorio** (copias exactas hechas por `.github/workflows/models.yml`). GitHub no admite archivos de más de 2 GB, así que Gemma se guarda en dos partes (`.001`, `.002`) que el juego une al terminar, comprobando el tamaño final.
2. Si falla, directamente de **Hugging Face** (repositorios públicos, sin cuenta).

La descarga se hace una sola vez, se puede pausar y continúa donde se quedó (cabecera HTTP `Range`). Los archivos se guardan en el almacenamiento privado de la app (`user://ia`). Desde *Ajustes → IA y voz* se pueden borrar.

## Cómo se eligió el modelo de conversación

Se evaluaron varios modelos con la misma conversación larga en español (presentación, preguntas del cliente, broma, pregunta personal inesperada, cambio de tema, contradicción de precio y petición de pago). Los guiones y transcripciones están en `tests/eval/` y los resultados de cada ejecución en la Release «evaluaciones».

### Resultados (CI, procesador de 4 núcleos sin GPU, 13 turnos × 3 clientes)

| Modelo | Tiempo medio por respuesta | Fallos de JSON | Calidad observada |
|---|---|---|---|
| **Gemma 4 E2B** (elegido) | 7,3–8,8 s | 0 | Frases cortas y coherentes, cada personaje habla distinto (el bromista hace chistes, la taquígrafa es seca y precisa, el abuelo pide que le hablen fácil), recuerda el primer precio y reacciona a la subida de 29 a 49. |
| Qwen3.5 2B | 11,9–13,4 s | 0 | Se repite y divaga («pan con rencor», nietos y gallina en cada frase); en un caso mezcló caracteres chinos. |
| Qwen3.5 4B | 21–22,5 s | 0 | Coherente, pero el triple de lento que Gemma. |

En un móvil el tiempo depende mucho del procesador: un móvil de gama alta suele igualar o superar a ese procesador de CI, uno de gama baja puede tardar varias veces más. **No se ha medido en un móvil real.**
