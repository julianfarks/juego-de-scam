# Modelos de IA que usa TeleTimo 3D

Todo funciona **dentro del dispositivo** con la extensión [NobodyWho](https://github.com/nobodywho-ooo/nobodywho) (licencia EUPL‑1.2, permite uso comercial). No hay servidores, cuentas ni claves.

| Función | Modelo | Licencia | Tamaño de descarga |
|---|---|---|---|
| Conversación de los clientes y del jefe | ver `PACKS` en `scripts/autoload/brain.gd` | ver la página del modelo | ver tabla del README |
| Voz a texto | Whisper base (ONNX, `onnx-community/whisper-base`) | MIT | 145 MB |
| Detección de voz | Silero VAD (ONNX, `onnx-community/silero-vad`) | MIT | 2 MB |
| Voces | Kokoro‑82M (`NobodyWho/Kokoro-82M`, voces `ef_dora` y `em_alex`) | Apache‑2.0 | 327 MB |

## De dónde se descargan

1. **Release «modelos» de este repositorio** (copias exactas hechas por `.github/workflows/models.yml`).
2. Si falla, directamente de **Hugging Face** (repositorios públicos, sin cuenta).

La descarga se hace una sola vez, se puede pausar y continúa donde se quedó (cabecera HTTP `Range`). Los archivos se guardan en el almacenamiento privado de la app (`user://ia`). Desde *Ajustes → IA y voz* se pueden borrar.

## Cómo se eligió el modelo de conversación

Se evaluaron varios modelos con la misma conversación larga en español (presentación, preguntas del cliente, broma, pregunta personal inesperada, cambio de tema, contradicción de precio y petición de pago). Los guiones y transcripciones están en `tests/eval/` y los resultados de cada ejecución en la Release «evaluaciones».
