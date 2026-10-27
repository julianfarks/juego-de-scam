# TeleTimo 3D

**Sátira de oficina en 3D para Android con clientes que piensan, escuchan y hablan gracias a una IA que funciona dentro del propio móvil.** Trabajas en *TeleTimo*, un call center ficticio que vende productos absurdos (seguros contra abducciones, herencias del Príncipe de Patatonia, parcelas en la cara oculta de la Luna…). Llamas a clientes con personalidades muy distintas, les hablas por el micrófono en español y ellos te contestan con su propia voz, recordando lo que les has dicho. Tu jefe, Don Ramiro Billetes, exige una cuota diaria.

> Todo es ficticio: personas, empresas, ofertas, dinero y tarjetas. Las tarjetas del juego empiezan por `0000`, no pasan la comprobación de Luhn y caducan el mes 13. El juego nunca pide datos financieros reales. Es una parodia: las estafas telefónicas reales hacen daño de verdad.

## Estado (27/10/2026)

| Qué | Resultado | Dónde se comprobó |
|---|---|---|
| Pruebas unitarias (reglas, memoria, economía, guardado…) | 240 / 240 | PC (Linux) |
| Prueba completa dentro del juego con IA real (descarga en dos partes, carga de Gemma, llamada con 4 respuestas de la IA, voz Kokoro, Whisper, venta, fin de jornada, guardado) | 16 / 16 | PC (Linux, 2 núcleos) |
| La misma prueba en Android | 17 / 17 con la IA respondiendo en personaje (traductor gráfico SwiftShader, pantalla en blanco) · 18 / 19 con gráficos ANGLE: todo se ve, pero la IA no llegó a tiempo y respondió el diálogo básico | Emulador Android 12 x86_64 en GitHub Actions |
| Conversación larga (13 turnos × 3 personalidades): preguntas, bromas, pregunta personal, contradicción de precio, pago | 0 fallos de formato; recuerda precios y contradicciones | CI, 4 núcleos |

**No se ha probado en un móvil real.** El emulador no tiene micrófono real ni GPU: dibuja con el procesador, el mismo que usa la IA, y por eso las respuestas tardaron 35–150 s. En un móvil la GPU dibuja y el procesador queda para la IA; en CI (4 núcleos, sin gráficos) Gemma tarda unos 8 s por respuesta, pero en un móvil concreto puede ser más o menos. Si un móvil tarda más de 40 s, el juego lo dice y sugiere el cerebro ligero.


## Cómo se juega (sin configurar nada)

1. Instala el APK (Release **`ultima-version`** de este repositorio) y ábrelo.
2. La primera vez, el juego ofrece **descargar la IA** (una sola vez; se recomienda Wi‑Fi). No hay cuentas, claves, servidores ni campos que rellenar. Puedes jugar mientras se descarga, pero hasta que termine los clientes usan un **diálogo básico por reglas**, y el juego lo indica.
3. Empieza la jornada, camina hasta tu mesa con el joystick y contesta el teléfono (o llama desde el ordenador).
4. Elige la oferta ficticia, pulsa el **micrófono** y habla con naturalidad. El cliente te escucha, piensa y te contesta con su voz; también puedes escribir.
5. Cuando lo veas convencido, pide los datos de pago. Si acepta o no lo deciden las **reglas del juego** según cómo ha ido la conversación (la IA no puede decidir el dinero).
6. Al final del día, el jefe te evalúa con datos reales de tu jornada.

## Arquitectura de la IA (todo en el dispositivo)

| Pieza | Qué hace | Tecnología |
|---|---|---|
| Cerebro de los clientes y del jefe | Entiende lo que dices y contesta en personaje, con memoria de la llamada | Modelo de lenguaje local (GGUF) con **NobodyWho** (llama.cpp) |
| Oído | Convierte tu voz en texto (español) | **Whisper** (ONNX) |
| Detector de voz | Sabe cuándo empiezas y terminas de hablar | **Silero VAD** |
| Voz de los clientes | Voz neuronal en español, tono distinto por personaje | **Kokoro‑82M** |
| Árbitro | Memoria verificable, paciencia, tiempo, venta e importes | Código del juego (GDScript) |

- [NobodyWho](https://github.com/nobodywho-ooo/nobodywho) es una extensión de Godot (EUPL‑1.2) que ejecuta estos modelos en Android (arm64), Windows, Linux y macOS.
- Por qué local y no en la nube: la nube exige un servidor pagado por alguien y claves que el jugador no debe gestionar. La IA local funciona sin conexión, gratis y sin enviar tu voz a ningún sitio. A cambio, ocupa espacio y necesita un móvil razonable.
- Detalles de los modelos, licencias y tamaños: [docs/MODELOS.md](docs/MODELOS.md).

### Cómo funciona una llamada

1. Al abrir la llamada, el cliente (personalidad + situación aleatoria, p. ej. «estás cocinando») empieza a pensar su saludo mientras eliges la oferta.
2. Cada frase tuya se manda al modelo junto con **notas verificables del juego** (precio dicho antes, contradicciones, promesas pendientes, paciencia baja, tiempo que queda).
3. El modelo responde con un JSON forzado por gramática: lo que dice, su emoción, cómo le ha sentado tu frase, su interés (0‑10), su duda principal y si quiere colgar. Mientras escribe, ves los subtítulos; en cuanto termina la frase, empieza a hablar.
4. El juego aplica ese juicio de forma **acotada y según la personalidad** (confianza, paciencia, sospecha…). Si el modelo repite una frase, se regenera.
5. Si pides el pago, decide `Economy` con el estado de la llamada y el interés (máx. ±0,15). Luego se le dice al modelo la decisión para que la exprese a su manera.

## Características del juego

- Oficina 3D explorable (cubículos, despacho del jefe, sala de descanso, tablón de objetivos, reloj, ciudad en las ventanas) con compañeros animados.
- 24 personajes 3D distintos y 20 personalidades con forma de hablar, humor, conocimientos, y cosas que les convencen o molestan.
- Caras expresivas, gestos, boca sincronizada con el volumen real de la voz.
- Jornadas con reloj, cuota, objetivos extra, eventos (inspección del jefe, pantalla azul, avería telefónica, compañero pesado, pizza, cliente VIP…).
- Ordenador «TimoOS 98» con 11 aplicaciones que funcionan (teléfono, CRM, calendario, estadísticas, objetivos, transacciones, mejoras, correo, evaluaciones, herramientas, ajustes).
- 12 días de campaña + modo infinito, mejoras con efectos reales, ropa, logros, guardado versionado.
- Controles táctiles (joystick, cámara por arrastre, botón de usar), modo zurdo, calidad gráfica y FPS ajustables.

## Requisitos

- **Móvil Android de 64 bits (arm64)**. Para la IA: **6 GB de RAM** para el cerebro normal (Gemma 4 E2B); con 4–5 GB el juego elige el ligero (Qwen3.5 0.8B), que conversa peor. Espacio: **unos 5 GB libres durante la descarga** y 3,6 GB después (1,1 GB con el ligero).
- Conexión a Internet **solo la primera vez** para descargar los modelos.

## Desarrollo

- Motor: **Godot 4.6.2** (renderizador Compatibility).
- Las bibliotecas nativas de NobodyWho pesan más de 100 MB y no se guardan en Git: `tools/fetch_nobodywho.sh linux` (o `android`, `all`) las descarga en `addons/nobodywho/`.
- Ejecutar en PC: `tools/fetch_nobodywho.sh linux && godot --path .`
- Compilar el APK: el flujo `.github/workflows/android.yml` lo hace en cada subida a `main` y lo publica en la Release `ultima-version`. Localmente: Android SDK + JDK 17 + plantillas de Godot 4.6.2, `tools/fetch_nobodywho.sh android` y `godot --headless --path . --export-debug "Android" build/TeleTimo3D-debug.apk`.

### Pruebas

| Prueba | Qué comprueba | Cómo |
|---|---|---|
| Unitarias (240) | Reglas, memoria, personalidades, economía, guardado, diálogo básico | `godot --headless --path . tests/test_runner.tscn` |
| Evaluación del modelo | Conversación larga en español (preguntas, bromas, contradicción, pago) | `tests/eval/run_eval.sh` (CI: `eval-ia.yml`) |
| Voz ida y vuelta | Kokoro → Whisper en español, detector de voz | `godot --headless --path . -s tests/eval/voice_eval.gd -- --models=RUTA` |
| Prueba dentro del juego | Descarga, carga, jornada, llamada con IA, voz, venta, guardado | se activa con `user://autotest.flag` |
| Emulador Android | Instala el APK y ejecuta la prueba anterior en Android | `android-test.yml` (resultados en la Release `evaluaciones`) |

## Limitaciones conocidas

- **Sin prueba en un móvil físico**: no se ha medido la velocidad real de la IA ni probado el micrófono real (en el emulador la voz se comprobó sintetizando una frase con Kokoro y pasándola a Whisper).
- **Descarga grande la primera vez**: 3,3 GB con el cerebro normal (1,1 GB con el ligero). Sin descargarla, el juego funciona con diálogo básico por reglas y lo indica en pantalla.
- **Móviles con menos de 6 GB de RAM**: usan el cerebro ligero, que conversa bastante peor.
- **La IA es un modelo pequeño**: a veces contesta con frases algo raras o se va por las ramas. Lo importante (dinero, venta, colgar, memoria de precios) lo controla el código, no la IA.
- **Tiempo límite por respuesta**: 150 s. Si la IA no termina, contesta el diálogo básico y se avisa en el chat («La IA no respondió a tiempo»).
- **Solo arm64**: el APK publicado es para móviles de 64 bits ARM (casi todos los actuales). El APK x86_64 de la Release «evaluaciones» es solo para el emulador.
- **Voz del sistema**: si las voces neuronales no se pueden cargar, se usa la voz de Android, que no es generativa y así se indica en Ajustes.


## Créditos

Idea y dirección: **julianfarks** · Desarrollo: julianfarks con Claude (Anthropic) · Motor: Godot Engine (MIT) · IA local: NobodyWho (EUPL‑1.2), modelos abiertos indicados en [docs/MODELOS.md](docs/MODELOS.md). Modelos 3D, música y efectos generados por código y originales.
