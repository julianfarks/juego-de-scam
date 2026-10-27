extends Node
## Localización ligera de la interfaz. El contenido de diálogo local está en español;
## la IA remota responde en el idioma elegido. Para añadir un idioma basta con
## añadir una columna a STRINGS (las claves que falten caen al español).

signal language_changed(lang: String)

const LANGS := ["es", "en"]
const LANG_NAMES := {"es": "Español", "en": "English"}

var lang := "es"

const STRINGS := {
	"play": {"es": "Nueva partida", "en": "New game"},
	"continue": {"es": "Continuar", "en": "Continue"},
	"days": {"es": "Jornadas", "en": "Workdays"},
	"settings": {"es": "Ajustes", "en": "Settings"},
	"stats": {"es": "Estadísticas", "en": "Statistics"},
	"credits": {"es": "Créditos", "en": "Credits"},
	"customize": {"es": "Personalizar", "en": "Customize"},
	"upgrades": {"es": "Mejoras", "en": "Upgrades"},
	"quit": {"es": "Salir", "en": "Quit"},
	"back": {"es": "Volver", "en": "Back"},
	"close": {"es": "Cerrar", "en": "Close"},
	"resume": {"es": "Reanudar", "en": "Resume"},
	"main_menu": {"es": "Menú principal", "en": "Main menu"},
	"pause": {"es": "Pausa", "en": "Paused"},
	"language": {"es": "Idioma", "en": "Language"},
	"graphics": {"es": "Gráficos", "en": "Graphics"},
	"audio": {"es": "Audio", "en": "Audio"},
	"voice": {"es": "IA y voz", "en": "AI & voice"},
	"controls": {"es": "Controles", "en": "Controls"},
	"quality": {"es": "Calidad", "en": "Quality"},
	"low": {"es": "Baja", "en": "Low"},
	"medium": {"es": "Media", "en": "Medium"},
	"high": {"es": "Alta", "en": "High"},
	"fps_limit": {"es": "Límite de FPS", "en": "FPS limit"},
	"auto_quality": {"es": "Bajar calidad si va lento", "en": "Lower quality when slow"},
	"master": {"es": "General", "en": "Master"},
	"music": {"es": "Música", "en": "Music"},
	"sfx": {"es": "Efectos", "en": "Effects"},
	"voices": {"es": "Voces", "en": "Voices"},
	"subtitles": {"es": "Subtítulos", "en": "Subtitles"},
	"tts_engine": {"es": "Voz de los clientes", "en": "Client voices"},
	"stt_engine": {"es": "Reconocimiento de voz", "en": "Speech recognition"},
	"sensitivity": {"es": "Sensibilidad de cámara", "en": "Camera sensitivity"},
	"joystick_size": {"es": "Tamaño del joystick", "en": "Joystick size"},
	"swap_sides": {"es": "Invertir lados (zurdo)", "en": "Swap sides (left-handed)"},
	"shift_length": {"es": "Duración de la jornada", "en": "Shift length"},
	"interact": {"es": "Usar", "en": "Use"},
	"run": {"es": "Correr", "en": "Run"},
	"answer": {"es": "Contestar", "en": "Answer"},
	"hang_up": {"es": "Colgar", "en": "Hang up"},
	"ask_payment": {"es": "Pedir datos", "en": "Ask payment"},
	"type": {"es": "Escribir", "en": "Type"},
	"send": {"es": "Enviar", "en": "Send"},
	"quota": {"es": "Cuota", "en": "Quota"},
	"time_left": {"es": "Tiempo", "en": "Time"},
	"day": {"es": "Día", "en": "Day"},
	"mic_ready": {"es": "Pulsa para hablar", "en": "Tap to talk"},
	"mic_listening": {"es": "Escuchando… (pulsa para terminar)", "en": "Listening… (tap to stop)"},
	"mic_transcribing": {"es": "Transcribiendo…", "en": "Transcribing…"},
	"mic_processing": {"es": "El cliente piensa…", "en": "Client is thinking…"},
	"mic_speaking": {"es": "El cliente habla…", "en": "Client is speaking…"},
	"mic_error": {"es": "Error de micrófono", "en": "Microphone error"},
	"mic_offline": {"es": "Micrófono no disponible: escribe", "en": "Mic unavailable: type"},
	"ai_on": {"es": "IA local (en el móvil)", "en": "On-device AI"},
	"ai_basic": {"es": "Diálogo básico (sin IA)", "en": "Basic dialogue (no AI)"},
	"start_day": {"es": "Empezar jornada", "en": "Start shift"},
	"end_day": {"es": "Terminar jornada", "en": "End shift"},
	"new_game_confirm": {"es": "¿Empezar de cero? Se borrará el progreso actual.", "en": "Start over? Current progress will be erased."},
	"yes": {"es": "Sí", "en": "Yes"},
	"no": {"es": "No", "en": "No"},
	"buy": {"es": "Comprar", "en": "Buy"},
	"owned": {"es": "Comprado", "en": "Owned"},
	"equip": {"es": "Equipar", "en": "Equip"},
	"equipped": {"es": "Equipado", "en": "Equipped"},
	"locked": {"es": "Bloqueado", "en": "Locked"},
	"call_summary": {"es": "Resumen de la llamada", "en": "Call summary"},
	"day_results": {"es": "Fin de la jornada", "en": "End of shift"},
	"next": {"es": "Siguiente", "en": "Next"},
	"retry_day": {"es": "Repetir jornada", "en": "Retry day"},
	"computer": {"es": "Ordenador", "en": "Computer"},
	"phone": {"es": "Teléfono", "en": "Phone"},
	"offer": {"es": "Oferta", "en": "Offer"},
	"repeat": {"es": "Repetir", "en": "Repeat"},
	"cancel": {"es": "Cancelar", "en": "Cancel"},
	"stop": {"es": "Detener", "en": "Stop"},
}


func t(key: String) -> String:
	if not STRINGS.has(key):
		return key
	var row: Dictionary = STRINGS[key]
	if row.has(lang):
		return row[lang]
	return row.get("es", key)


func set_language(new_lang: String) -> void:
	if not LANGS.has(new_lang):
		new_lang = "es"
	lang = new_lang
	TranslationServer.set_locale(new_lang)
	language_changed.emit(new_lang)
