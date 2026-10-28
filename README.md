# TeleTimo 3D

**Sátira de oficina en 3D para Android con clientes que piensan, escuchan y hablan gracias a una IA que funciona dentro del propio móvil.** Trabajas en *TeleTimo*, un call center ficticio que vende productos absurdos (seguros contra abducciones, herencias del Príncipe de Patatonia, parcelas en la cara oculta de la Luna…). Llamas a clientes con personalidades muy distintas, les hablas por el micrófono en español y ellos te contestan con su propia voz, recordando lo que les has dicho. Tu jefe, Don Ramiro Billetes, exige una cuota diaria.

> Todo es ficticio: personas, empresas, ofertas, dinero y tarjetas. Las tarjetas del juego empiezan por `0000`, no pasan la comprobación de Luhn y caducan el mes 13. El juego nunca pide datos financieros reales. Es una parodia: las estafas telefónicas reales hacen daño de verdad.

## Estado

<!--ESTADO-->

## Cómo se juega (sin configurar nada)

1. Instala el APK (Release **`ultima-version`** de este repositorio) y ábrelo.
2. La primera vez, el juego ofrece **descargar la IA** (una sola vez; se recomienda Wi‑Fi). No hay cuentas, claves, servidores ni campos que rellenar. Si ya la descargaste, no se vuelve a bajar: el juego comprueba los archivos (tamaño y cabecera) y los reutiliza.
3. Empieza la jornada, camina hasta tu mesa con el joystick y contesta el teléfono (o llama desde el ordenador).
4. **Llamada libre**: vende lo que quieras (un queso artesanal, hierbas, un servicio de jardinería, un seguro absurdo…). Puedes escribir tu primera frase antes de llamar, usar una idea del catálogo opcional o improvisar directamente por micrófono o texto. Puedes cambiar de producto, añadir servicios, negociar el precio, bromear o cambiar de tema: el cliente lo entiende y lo recuerda.
5. Arriba ves siempre en qué fase está la llamada: *Preparando*, *Tu turno*, *X está pensando… (segundos)*, *Escuchando tu voz*, *Pasando tu voz a texto*, *X habla* o *La IA ha fallado*. A la izquierda, la propuesta tal como la ha entendido el cliente, el precio y la cantidad.
6. Cuando lo veas convencido, pulsa **Pedir datos de pago** (o pídeselo con tus palabras). Si acepta o no lo deciden las **reglas del juego** (confianza, dudas, contradicciones, precio frente a su presupuesto…), nunca la IA. Sin precio dicho, el cliente te lo pregunta.
7. La venta queda registrada en la app **Transacciones** del ordenador y tu comisión se suma al saldo al momento. Al final del día, el jefe te evalúa y se pagan los gastos.

### Si la IA falla

La IA nunca puede dejar la llamada «pensando» para siempre: cada respuesta tiene límites reales (primer token: 60 s; atasco a mitad: 25 s; total: 120 s), igual que la voz (Whisper 30 s, Kokoro 25 s por frase). Si se pasa, aparece **«La IA ha fallado»** con tres botones:
- **Reintentar**: abre una conversación nueva reconstruida con la memoria del juego (por si el motor anterior quedó bloqueado).
- **Seguir sin IA**: el resto de la llamada usa el diálogo básico, y así se indica en cada respuesta.
- **Ver detalle**: muestra el registro técnico.

En **Ajustes → IA y voz → Diagnóstico** puedes *Comprobar archivos*, *Probar la IA* (mide el primer token y los tokens por segundo) y *Ver registro* → **Copiar**, para enviar el registro si algo va mal. El registro solo contiene tiempos, tamaños y errores, nunca lo que dices.

**La GPU está desactivada por defecto.** En móviles con GPU Adreno (Snapdragon), NobodyWho descarta Vulkan y usa el backend OpenCL de llama.cpp, que con Gemma 4 puede no devolver nunca el primer token: esa era la causa de que el cliente se quedara «pensando». El procesador de un móvil actual basta. Si activas la GPU y no responde, el juego lo detecta al cargar y vuelve solo al procesador.

### Dinero del juego (todo ficticio)

- **Importe de una venta** = el precio que tú dijiste (el número pegado a «pesos») × la cantidad que propusiste («dos piezas», «tres botes»), con un tope según el presupuesto del cliente. La IA no puede cambiarlo.
- La venta suma a la **cuota del día**; tú cobras una **comisión** (50 %, más con mejoras) que entra en el saldo al instante.
- **Movimientos del saldo**: comisiones, incentivos por clientes interesados, bonos, multas del jefe, recompensas de objetivos, bono por cumplir la cuota, gastos diarios y compras. Todo se ve en *Transacciones → Movimientos del saldo* y se guarda.
- Las tarjetas que aparecen al cerrar una venta son de demostración (prefijo `0000`, inservibles). El juego nunca pide datos reales.

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

1. Mientras ves la ficha del cliente, se prepara su conversación (personalidad, situación aleatoria —«estás cocinando»—, presupuesto) y piensa su saludo.
2. Cada frase tuya se manda al modelo junto con **notas verificables del juego**: precio que dijiste y si lo bajaste o lo subiste, cantidad, contradicciones, promesas pendientes, paciencia, tiempo que queda y, cada pocos turnos, un recordatorio de la propuesta y de las dudas. Así las conversaciones largas no pierden el hilo.
3. El modelo responde con un JSON forzado por gramática: lo que dice, su emoción, cómo le ha sentado tu frase, su interés (0‑10), su duda principal, **qué entiende que le estás vendiendo** y si quiere colgar. Ves los subtítulos mientras escribe y la voz empieza en cuanto la frase está completa.
4. El juego aplica ese juicio de forma **acotada y según la personalidad**. Si el modelo repite una frase, se regenera.
5. Si pides el pago, decide `Economy` con reglas fijas y después se le dice al modelo la decisión para que la exprese a su manera.
6. El juego guarda su propia copia de la conversación: si el motor de IA se bloquea, «Reintentar» la reconstruye en una conversación nueva.

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
| Unitarias (307) | Reglas, memoria, propuestas libres, precios y cantidades, economía, transacciones y saldo, guardado, tiempos límite con una IA falsa que se cuelga, reintento y «seguir sin IA» | `godot --headless --path . tests/test_runner.tscn` |
| Conversaciones libres con la IA | El MISMO código de la llamada con 8 clientes y 2 guiones (queso con entrega y negociación; jardinería que cambia a hierbas): memoria, cambio de propuesta, tema, broma, pago | `tests/eval/run_eval.sh` (CI: `eval-ia.yml`) |
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
