# TeleTimo 3D

**Sátira de oficina en 3D para Android.** Trabajas en *TeleTimo*, un call center ficticio que vende productos absurdos: seguros contra abducciones, herencias del Príncipe de Patatonia o parcelas en la cara oculta de la Luna. Tus clientes son personajes controlados por IA que escuchan lo que dices (por micrófono o por texto), recuerdan la conversación, ponen objeciones, te pillan las contradicciones y reaccionan según su personalidad. Tu jefe, Don Ramiro Billetes, exige una cuota diaria.

> Todo es ficticio: clientes, empresas, ofertas, dinero y tarjetas. Las tarjetas del juego empiezan por `0000`, no pasan la comprobación de Luhn y caducan el mes 13: no sirven para nada fuera del juego. El juego nunca pide datos financieros reales. Es una parodia: las estafas telefónicas reales hacen daño de verdad.

*(Nombre provisional del encargo: «Scam Call Center 3D». Propuesto: **TeleTimo 3D**.)*

---

## Características

- **Oficina 3D explorable**: zona de cubículos, despacho acristalado del jefe, sala de descanso (cafetera, sofá, nevera, dispensador), tablón de objetivos en tiempo real, reloj de pared, ventanales con ciudad, pósteres, plantas, fotocopiadora y compañeros que trabajan y comentan cosas.
- **24 personajes 3D distintos** generados por código: tipo de cuerpo (delgado, ancho, alto, bajo), 13 peinados, ropa y colores propios, accesorios (gafas, sombreros, gorro de papel de aluminio, bigote, barba, pajarita, chistera, bastón…), cara expresiva (cejas, párpados, boca con comisuras, rubor), y cada uno con su casa en la «videollamada».
- **Animación procedural**: respirar, parpadear, caminar, sentarse a teclear, hablar por teléfono, gestos al hablar, boca sincronizada con la voz, emociones (alegría, sorpresa, confusión, enfado, desconfianza, tristeza) y gestos (asentir, negar, señalar, rascarse la cabeza, cruzar brazos, colgar…).
- **20 personalidades** con efectos reales en las reglas (desconfiado, impaciente, bromista, hablador, distraído, literal, experto, indeciso, paranoico, educado pero firme, cambia de tema, malinterpreta, preguntón, quiere colgar, necesita sencillez, competitivo, dramático, sarcástico, detector de contradicciones, preguntas inesperadas). Cada una cambia valores iniciales, multiplicadores, lo que le gusta y lo que odia, rarezas de comportamiento, objeciones típicas, voz y probabilidad de aceptar.
- **Conversación con IA** (Claude) a través de un servidor propio, con **memoria estructurada por llamada**: confianza, paciencia, humor, comprensión, sospecha, objeciones pendientes y resueltas, cifras mencionadas, promesas, contradicciones, preguntas del cliente, decisiones e historial resumido.
- **Modo sin conexión** con un motor de diálogo local (no generativo) que analiza intenciones, cifras, preguntas y referencias personales, y responde según la personalidad y la memoria de la llamada. El juego indica siempre si responde la **IA remota** o el **diálogo local**.
- **Voz**: micrófono con estados claros (preparado, escuchando, transcribiendo, procesando, cliente hablando, error, sin conexión), fin automático por silencio, cancelar, repetir y modo texto. Transcripción en el servidor y voces del sistema Android (gratis) o voces remotas (opcional).
- **Economía autoritativa**: la IA no puede tocar el dinero. El importe sale del catálogo de ofertas y de las reglas; la probabilidad de cierre la calculan las reglas con el estado de la llamada. La IA solo puede sugerir ajustes pequeños y acotados.
- **Jornadas** con cuota, reloj de 09:00 a 17:00, llamadas entrantes (y perdidas), lista de clientes para llamar, objetivos extra, gastos ficticios, bonificaciones, multas y **evaluación del jefe** con nota S–F basada en datos reales (con IA si está disponible).
- **Eventos**: llamada urgente VIP, inspección del jefe, fallo informático («pantalla azul»), avería de la centralita, compañero pesado que interrumpe, cliente extremadamente complicado, oportunidad especial (×2), aclaración inesperada y pizza gratis.
- **Ordenador «TimoOS 98»** con 11 aplicaciones que funcionan: Teléfono (lista de llamadas), Clientes (CRM), Calendario, Estadísticas y logros, Objetivos, Transacciones, Mejoras (tienda), Correo, Evaluaciones, Herramientas cómicas y Ajustes.
- **Campaña de 12 días** con dificultad creciente y modo infinito; 14 ofertas que se desbloquean; 18 mejoras con efectos reales; 20 prendas y accesorios; 17 logros; estadísticas persistentes.
- **Guardado local versionado** con escritura atómica, copia de seguridad, migración de versiones anteriores y validación.
- **Interfaz táctil**: joystick dinámico, arrastre de cámara, botón de usar, correr, pausa, botón grande de micrófono; ajustes de sensibilidad, tamaño del joystick y modo zurdo. Botón «Atrás» de Android.
- **Audio original generado por código**: música lounge de oficina y del menú, teléfonos, teclados, notificaciones, caja registradora, trombón triste, aplausos, risas; buses separados de música, efectos y voces.
- **Rendimiento**: renderizador Compatibility (OpenGL ES 3), perfiles de calidad baja/media/alta, límite de 30/60 FPS, reducción automática de calidad si el dispositivo va lento, geometría y materiales compartidos.

## Motor y tecnologías

| Parte | Tecnología |
|---|---|
| Juego | **Godot 4.3** (GDScript), renderizador *GL Compatibility* (OpenGL ES 3) |
| Plataforma | Android (arm64-v8a), apaisado |
| Servidor de IA | **Node.js ≥ 20**, sin dependencias externas |
| Conversación (LLM) | Claude, API Messages de Anthropic (modelo configurable, por defecto `claude-haiku-5-5`) |
| Transcripción | OpenAI `/audio/transcriptions` (`gpt-4o-mini-transcribe` por defecto) |
| Voz remota (opcional) | OpenAI `/audio/speech` (`gpt-4o-mini-tts`, MP3) |
| Voz sin servidor | TTS del sistema Android (`DisplayServer.tts_*`) |

**¿Por qué Godot y no Unity?** APK pequeño, arranque rápido, sin licencias ni cuentas, GDScript fácil de mantener, y exportación a Android automatizable en GitHub Actions. Todo el contenido 3D, la interfaz y el audio se generan por código, así que no hay recursos binarios que mantener ni problemas de derechos.

**¿Por qué Node.js y no FastAPI?** El encargo admitía ambos. Node 22 trae `fetch`, `FormData` y un servidor HTTP de serie, así que el backend funciona **sin instalar ni una dependencia** (más fácil de desplegar y de auditar). Además, en el entorno donde se desarrolló no había acceso a PyPI.

## Estructura

```
project.godot, export_presets.cfg    Proyecto Godot y exportación Android
scenes/main.tscn                     Escena principal
scripts/
  main.gd                            Estados: menú, jornada, pausa, botón Atrás
  autoload/                          Servicios globales
    loc.gd                           Textos de interfaz (es/en)
    settings.gd                      Ajustes (user://settings.cfg)
    save_system.gd                   Guardado versionado (user://save.json)
    audio_manager.gd                 Buses, efectos, música, ambiente
    game_state.gd                    Jornada, resultados, objetivos, logros, correo
    ai_service.gd                    Cliente HTTP del servidor IA (sesión, chat, STT, TTS, jefe)
    voice_service.gd                 Micrófono, detección de silencio, voces y boca
  core/                              Reglas del juego (sin dependencias de la escena 3D)
    personality_db.gd                20 personalidades y objeciones
    client_db.gd                     24 personajes (aspecto, casa, datos, gustos)
    offer_db.gd                      14 ofertas ficticias con precio base y máximo
    intent_classifier.gd             Análisis de la frase del jugador
    conversation_state.gd            Memoria estructurada de la llamada
    conversation_rules.gd            Reglas deterministas de cada turno
    local_dialogue.gd                Diálogo local (modo sin conexión)
    economy.gd                       Probabilidad de cierre e importes (autoritativo)
    fake_card.gd                     Tarjetas ficticias inservibles
    call_session.gd                  Orquesta una llamada (IA remota o local)
    campaign_db.gd, event_db.gd, upgrade_db.gd, achievement_db.gd, boss_lines.gd
    synth.gd                         Sintetizador de música y efectos
  ai/ai_response.gd                  Validación de respuestas de la IA
  voice/wav_util.gd                  Micrófono → WAV 16 kHz mono
  world/                             Oficina, jugador, NPC, personajes, videollamada
  ui/                                HUD, controles táctiles, llamada, ordenador, menús
  debug/                             Recorrido de capturas y prueba de resistencia
tests/                               Pruebas automáticas (headless) e integración
backend/                             Servidor de IA (Node.js)
.github/workflows/android.yml        Pruebas + compilación del APK + Release
```

## Requisitos

- **Para jugar**: un teléfono Android con procesador de 64 bits (arm64). Sin servidor, el juego funciona con diálogo local y texto.
- **Para la IA y la voz**: un servidor con Node.js ≥ 20 (o Docker) accesible por **HTTPS**, una clave de Anthropic (conversación) y, para el micrófono y las voces remotas, una clave de OpenAI. **Ambos servicios cobran por uso.**
- **Para desarrollar**: Godot 4.3 estable. Para compilar el APK en tu PC: Android SDK (build-tools 34, platform 34), JDK 17 y las plantillas de exportación de Godot 4.3.

## Instalación y ejecución

### Jugar (APK)
Cada subida a `main` compila el APK en GitHub Actions y lo publica en la Release **`ultima-version`** del repositorio. Descarga `TeleTimo3D-debug.apk` en el móvil e instálalo permitiendo orígenes desconocidos.

### Ejecutar en el ordenador
```bash
godot --path .            # o abre project.godot en el editor y pulsa F5
```
Controles en PC: WASD para moverte, botón derecho del ratón para girar la cámara, E para usar, Mayús para correr.

### Compilar el APK localmente
1. Instala Android SDK + JDK 17 y las plantillas de Godot 4.3 (*Editor → Manage Export Templates*).
2. En *Editor Settings → Export → Android*, indica las rutas del SDK, del JDK y un keystore de depuración.
3. Exporta:
```bash
godot --headless --path . --export-debug "Android" build/TeleTimo3D-debug.apk
```

## Configuración de la IA, la transcripción y las voces

1. Despliega el servidor (siguiente sección) y anota su URL HTTPS.
2. En el juego: **Ajustes → Voz e IA**
   - *URL del servidor IA*: p. ej. `https://teletimo.midominio.com`
   - *Código de acceso*: el valor de `APP_ACCESS_CODE` del servidor
   - Pulsa **Probar conexión**: verás qué proveedores tiene activos el servidor.
3. *Voz de los clientes*: **Voz del sistema** (gratis, sin conexión, depende de las voces instaladas en el móvil; en Android: Ajustes → Accesibilidad → Texto a voz), **Voz remota** (OpenAI, de pago, más natural) o **Sin voz**.
4. *Reconocimiento de voz*: **Servidor IA** (necesario para hablar por micrófono) o **Desactivado** (solo texto).
5. La primera vez que pulses el micrófono, el juego explica qué hace y pide tu consentimiento; después Android pide el permiso de micrófono.

Sin servidor configurado o si falla la conexión, los clientes responden con el **diálogo local**, la jornada continúa y el juego lo indica en pantalla. Tras un fallo espera 25 s antes de reintentar el servidor.

## Variables de entorno del servidor

Copia `backend/.env.example` como `backend/.env` y rellénalo. **No subas `.env` a GitHub** (está en `.gitignore`).

| Variable | Para qué sirve | Por defecto |
|---|---|---|
| `APP_ACCESS_CODE` | Código que el jugador escribe en el juego. **Obligatorio en la práctica** | (vacío = sin protección) |
| `TOKEN_SECRET` | Secreto para firmar sesiones | aleatorio en cada arranque |
| `LLM_PROVIDER` | `anthropic` o `mock` (pruebas sin IA) | `anthropic` |
| `ANTHROPIC_API_KEY` | Clave de Anthropic | — |
| `ANTHROPIC_MODEL` | Modelo de Claude | `claude-haiku-5-5` |
| `MAX_REPLY_TOKENS` | Límite de tokens por respuesta | `400` |
| `STT_PROVIDER` / `TTS_PROVIDER` | `openai`, `none` (y `mock` para STT) | `openai` |
| `OPENAI_API_KEY` | Clave de OpenAI (transcripción y voz) | — |
| `OPENAI_STT_MODEL` / `OPENAI_TTS_MODEL` | Modelos de voz | `gpt-4o-mini-transcribe` / `gpt-4o-mini-tts` |
| `UPSTREAM_TIMEOUT_MS` | Tiempo máximo de espera al proveedor | `12000` |
| `RATE_LIMIT_PER_MIN` | Peticiones por minuto y dispositivo | `40` |
| `DAILY_REQUESTS_PER_DEVICE` | Peticiones diarias por dispositivo | `800` |
| `DAILY_TTS_CHARS_PER_DEVICE` / `DAILY_STT_SECONDS_PER_DEVICE` | Topes diarios de voz | `40000` / `1800` |
| `MAX_JSON_BYTES` / `MAX_AUDIO_BYTES` | Tamaño máximo de las peticiones | `32768` / `1048576` |

## Despliegue del backend

### Con Node.js
```bash
cd backend
cp .env.example .env       # y edítalo
npm start                  # o: node server.js
```

### Con Docker
```bash
cd backend
docker build -t teletimo-backend .
docker run -d -p 8787:8787 --env-file .env teletimo-backend
```

Ponlo detrás de HTTPS (Caddy, Nginx, o un servicio tipo Render/Railway/Fly.io que ya da HTTPS). **Android bloquea por defecto las conexiones `http://` sin cifrar**, así que usa `https://`.

### Endpoints
| Método y ruta | Descripción |
|---|---|
| `GET /health` | Estado y proveedores activos (sin secretos) |
| `POST /v1/session` | `{device_id, access_code}` → `{token, expires_in}` |
| `POST /v1/chat` | Turno de conversación: personaje, oferta, estado, historial y frase → `{reply, emotion, gesture, deltas, receptive, wants_to_hang_up, usage}` |
| `POST /v1/stt` | `multipart/form-data` con `file` (WAV) y `language` → `{text}` |
| `POST /v1/tts` | `{text, voice, instructions}` → `audio/mpeg` |
| `POST /v1/boss` | `{stats}` → `{comment}` |
| `GET /v1/usage` | Consumo de hoy del dispositivo |

Protección incluida: código de acceso, tokens HMAC con caducidad, límites por minuto y diarios por dispositivo, tamaño máximo de petición, validación y recorte de todos los campos, tiempos de espera, cancelación de la llamada al proveedor si el juego cancela, deduplicación de peticiones repetidas, eliminación de secuencias largas de dígitos en entradas y salidas, y registros mínimos (ruta, código y duración; nunca el contenido de las conversaciones).

### Costes
Claude y OpenAI cobran por uso. Para orientarte: cada turno de conversación envía un prompt compacto (personaje, estado resumido y los últimos 8 mensajes) y pide como mucho `MAX_REPLY_TOKENS` tokens; cada frase por micrófono son unos segundos de audio; las voces remotas se cobran por carácter. Consulta los precios actuales en las webs de [Anthropic](https://docs.claude.com) y [OpenAI](https://developers.openai.com). El ordenador del juego (*Estadísticas*) muestra el consumo de la sesión. Usa la voz del sistema si quieres ahorrar.

## Pruebas

```bash
# Juego: 240 comprobaciones de reglas, memoria, personalidades, economía, guardado, diálogo local, etc.
godot --headless --path . tests/test_runner.tscn

# Backend: 19 pruebas (auth, límites, validación, formato exacto de las llamadas a Claude y OpenAI…)
cd backend && npm test

# Integración real juego ↔ servidor (servidor en modo mock)
(cd backend && APP_ACCESS_CODE=prueba LLM_PROVIDER=mock STT_PROVIDER=mock TTS_PROVIDER=none node server.js &)
godot --headless --path . tests/e2e_runner.tscn -- --backend=http://127.0.0.1:8787 --code=prueba

# Resistencia: varias jornadas aceleradas con eventos y ~50 llamadas automáticas
godot --headless --path . -- --soak

# Recorrido con capturas de pantalla
godot --path . -- --tour=/ruta/capturas
```

GitHub Actions ejecuta las pruebas del juego, las del backend y la integración antes de compilar el APK.

## Limitaciones conocidas

- **No probado en un teléfono real** durante el desarrollo: el micrófono, el permiso de Android, la voz del sistema y el rendimiento (FPS) hay que validarlos en el dispositivo. Las capturas y pruebas se hicieron en Linux (OpenGL por software).
- La **transcripción** necesita el servidor; no hay reconocimiento de voz local integrado (las opciones locales tipo Whisper requieren plugins nativos y aumentan mucho el APK).
- La **voz del sistema** depende de las voces instaladas en el móvil; algunos dispositivos solo tienen una voz por idioma, así que varios clientes pueden sonar parecido (se les cambia tono y velocidad).
- La animación de boca con la voz del sistema es aproximada (Android no informa de los fonemas); con la voz remota se sincroniza con el volumen real del audio.
- Los diálogos locales y el contenido están en español; la interfaz tiene también inglés y, con la IA remota, los clientes hablan el idioma elegido.
- Los personajes son low-poly procedurales (sin modelos ni esqueletos importados): expresivos pero sencillos.

## Solución de problemas

| Problema | Qué hacer |
|---|---|
| «IA sin conexión: diálogo local» | Revisa la URL (con `https://`), el código de acceso y pulsa *Probar conexión*. Mira los registros del servidor. |
| «Sesión rechazada» | El código de acceso no coincide con `APP_ACCESS_CODE`. |
| El micrófono no hace nada | Acepta el consentimiento del juego y el permiso de Android (*Ajustes del móvil → Apps → TeleTimo 3D → Permisos*). Necesita servidor con `STT_PROVIDER=openai`. |
| «No te he oído» | Habla más cerca; el audio de menos de 0,4 s o muy bajo se descarta. |
| Los clientes no hablan | Activa una voz en español en *Ajustes de Android → Texto a voz*, o elige *Voz remota* en el juego. |
| Va lento | *Ajustes → Gráficos → Calidad baja* y 30 FPS. La opción «Bajar calidad si va lento» lo hace sola. |
| Error 429 del servidor | Se alcanzó un límite de uso; ajusta `RATE_LIMIT_PER_MIN` o los topes diarios. |
| El APK no aparece en Releases | Mira la pestaña *Actions* del repositorio: si fallan las pruebas, no se publica. |

## Continuar el desarrollo

- **Nuevo cliente**: añade una entrada a `ClientDB.CLIENTS` (personalidad, aspecto, casa, datos, gustos). No hay que tocar nada más.
- **Nueva personalidad**: añade una entrada a `PersonalityDB.P` (valores base, multiplicadores, gustos, rarezas, objeciones, voz y frases). Si inventas una rareza nueva, impleméntala en `ConversationRules._apply_quirks`.
- **Nueva oferta / mejora / evento / logro**: `OfferDB`, `UpgradeDB`, `EventDB`, `AchievementDB`.
- **Otro proveedor de IA**: implementa un archivo en `backend/src/providers/` y selecciónalo en `app.js`; el juego no cambia.
- **Otro idioma**: añade la columna en `Loc.STRINGS`; con la IA remota los clientes ya responden en ese idioma.

## Créditos

Idea y dirección: **julianfarks** · Desarrollo: julianfarks con Claude (Anthropic) · Motor: Godot Engine (MIT). Todos los modelos, la música y los efectos se generan por código y son originales; no se usa ningún recurso, nombre ni diálogo de otros juegos.
