extends Node
## Ajustes del jugador (separados del progreso). Se guardan en user://settings.cfg.
## El juego no usa servidores ni claves: toda la IA funciona en el dispositivo.

signal changed(key: String)
signal graphics_changed

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"lang": "es",
	"quality": 1,            # 0 baja, 1 media, 2 alta
	"fps_limit": 30,
	"auto_quality": true,
	"vol_master": 0.9,
	"vol_music": 0.45,
	"vol_sfx": 0.8,
	"vol_voice": 1.0,
	"subtitles": true,
	"tts_mode": "ia",        # ia (voces neuronales locales) | system (voz de Android) | off
	"vad_auto_stop": true,
	"voice_speed": 1.0,
	"llm_size": "auto",      # auto | normal | ligero
	"ai_gpu": true,          # aceleración por GPU del modelo de lenguaje
	"gpu_probe": false,      # marca interna: si queda a true, la carga con GPU falló
	"ai_enabled": true,
	"ai_setup_seen": false,
	"cam_sensitivity": 1.0,
	"joystick_scale": 1.0,
	"swap_sides": false,
	"shift_minutes": 9,
	"mic_consent": false,
}

var data: Dictionary = DEFAULTS.duplicate(true)


func _ready() -> void:
	load_settings()
	Loc.set_language(get_value("lang"))
	apply_engine()


func get_value(key: String) -> Variant:
	return data.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant, persist := true) -> void:
	if not DEFAULTS.has(key):
		push_warning("Ajuste desconocido: %s" % key)
		return
	data[key] = _sanitize(key, value)
	if key == "lang":
		Loc.set_language(data[key])
	if key in ["quality", "fps_limit", "auto_quality"]:
		apply_engine()
		graphics_changed.emit()
	changed.emit(key)
	if persist:
		save_settings()


func _sanitize(key: String, value: Variant) -> Variant:
	var def: Variant = DEFAULTS[key]
	match typeof(def):
		TYPE_INT:
			var v := int(value)
			if key == "quality":
				return clampi(v, 0, 2)
			if key == "fps_limit":
				return 60 if v >= 45 else 30
			if key == "shift_minutes":
				return clampi(v, 4, 15)
			return v
		TYPE_FLOAT:
			return clampf(float(value), 0.0, 2.0)
		TYPE_BOOL:
			return bool(value)
		TYPE_STRING:
			var s := str(value).strip_edges()
			if key == "tts_mode" and not s in ["ia", "system", "off"]:
				return "ia"
			if key == "llm_size" and not s in ["auto", "normal", "ligero"]:
				return "auto"
			if key == "lang" and not s in Loc.LANGS:
				return "es"
			return s.substr(0, 300)
	return value


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in DEFAULTS.keys():
		if cfg.has_section_key("settings", key):
			data[key] = _sanitize(key, cfg.get_value("settings", key))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in data.keys():
		cfg.set_value("settings", key, data[key])
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("No se pudieron guardar los ajustes (%d)" % err)


func apply_engine() -> void:
	Engine.max_fps = int(get_value("fps_limit"))
	var vp := get_viewport()
	if vp == null:
		return
	var q := int(get_value("quality"))
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X][q]
	vp.scaling_3d_scale = [0.75, 0.9, 1.0][q]


func shadows_enabled() -> bool:
	return int(get_value("quality")) >= 1


func ambient_npc_count() -> int:
	return [3, 5, 7][int(get_value("quality"))]

