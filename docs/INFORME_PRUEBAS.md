# Informe de pruebas — TeleTimo 3D

Todas las pruebas de esta tabla se **ejecutaron** (no son revisiones de código). Fecha: 28/10/2026.

## 1. Diagnóstico del bloqueo «el cliente está pensando»

| Comprobación | Resultado |
|---|---|
| Archivos descargados | Gemma 4 E2B: 3.106.736.256 bytes, cabecera `GGUF` v3, coincide con el tamaño esperado. Whisper, Silero y Kokoro: completos. Se comprueban sin volver a descargarlos (*Ajustes → IA y voz → Comprobar archivos*). |
| Formato y arquitectura | Gemma 4 E2B Q4_K_M carga y genera con NobodyWho 12.1.0 en procesador (Linux x86_64, Android x86_64 en emulador). |
| GPU en Android | El código de NobodyWho (`core/src/memory.rs`) descarta Vulkan en GPU Adreno y usa el backend **OpenCL** de llama.cpp, que sus autores califican de «calidad cuestionable». El juego activaba la GPU por defecto: en un Snapdragon (Adreno) la IA corría por ese camino, que no se probó en ningún entorno sin GPU Adreno. Es la causa más probable de que no llegara nunca el primer token. **Corregido**: GPU desactivada por defecto (con migración de ajustes), prueba real del modelo al cargarlo y vuelta automática al procesador si falla. |
| Espera infinita en el juego | `await stream.next_token()` sin límite real: si no llegaba ningún token, la llamada no salía nunca de «pensando». El comentario del jefe al final del día tenía el mismo problema. **Corregido**: límites reales (primer token, atasco, total) en IA, Whisper y Kokoro (`Timed`, `AIStream`). |
| Hilo principal | La inferencia corre en el hilo de NobodyWho; el juego solo espera fotograma a fotograma, no se bloquea. |
| Error recuperable | Fase «error» con Reintentar (conversación nueva reconstruida con la memoria del juego), Seguir sin IA y registro técnico copiable. |

**Pendiente**: confirmarlo en el RedMagic 9 Pro.

## 2. Pruebas automáticas (`tests/test_runner.tscn`) — 320 / 320

Incluyen: reglas de conversación y memoria; categorías, cantidad y precio de propuestas libres (el precio es el número pegado a «pesos», no la cantidad); negociar a la baja no es contradicción y subir el precio sí; «a domicilio» ya no se confunde con pedir el pago; economía (sin precio no se cobra, presupuesto, importe = precio × cantidad, comisión); transacciones, movimientos del saldo, gastos y guardado; migración del guardado v2 → v3; **IA falsa que nunca responde** (la llamada pasa a «error» sin inventar respuestas), atasco a mitad de respuesta, Cancelar, Reintentar, «Seguir sin IA», propuesta que cambia a mitad de llamada; límites de tiempo adaptados a la velocidad.

## 3. Partida completa con IA real (`scripts/debug/autotest.gd`)

| Entorno | Resultado | Notas |
|---|---|---|
| PC Linux, 2 núcleos, gráficos por software | **23 / 23** | 11 respuestas de la IA, 0 errores, ≈ 50 s por respuesta (máquina lenta). Memoria: «¡Claro que lo recuerdo! Queso de cabra, dos piezas por dieciocho». Transacción: 18 × 2 = 36; saldo 150 → 168. |
| Emulador Android 12 x86_64 (GitHub Actions, gráficos ANGLE) | **24 / 24** | Instala el APK, descarga 3,3 GB, carga Gemma, voz y Whisper; oficina y llamada visibles; 11 respuestas de la IA, 0 errores; ≈ 4 min por respuesta (el emulador dibuja con el mismo procesador). |

## 4. Conversaciones libres (`tests/eval/call_eval.tscn`, CI)

8 clientes de personalidades distintas × 2 guiones (queso artesanal con entrega, negociación y pregunta de memoria; jardinería que cambia a hierbas medicinales y vuelta al tema), con el **mismo código de llamada** del juego. Gemma: 0 errores, 0 «no entiendo», 6,4–9,1 s por respuesta. Ejemplos:

- Bromista: sigue la broma del queso «curado», habla de su pez Ronaldiño, compra.
- Desconfiada: «¿A domicilio? ¿Y cómo sé que no es una trampa?» … «No me prepare nada».
- Impaciente: «¿Quién? Habla ya.» … «No tengo tiempo.» … cuelga.
- Ingeniera literal: «Eso suma treinta y seis pesos», pide «la especie exacta y las dimensiones de la maceta», recuerda que lo primero fue jardinería.

## 5. Lo que NO se ha podido probar

- **Un móvil Android físico** (no hay ninguno disponible en este entorno): velocidad real, GPU Adreno, micrófono real, rendimiento térmico.
- **Micrófono real**: el emulador no tiene; se probó la cadena de voz sintetizando una frase con Kokoro y transcribiéndola con Whisper.
