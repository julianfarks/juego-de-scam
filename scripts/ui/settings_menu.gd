class_name SettingsMenu
extends Control
## Ajustes: idioma, gráficos, audio, voz/IA (servidor, prueba de conexión,
## micrófono, voces) y controles táctiles.

signal closed

var tabs: TabContainer
var conn_label: Label


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var v := UIKit.vbox(10)
	margin.add_child(v)
	var h := UIKit.hbox(10)
	var t := UIKit.label(Loc.t("settings"), 34, UIKit.C_ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(UIKit.button(Loc.t("close"), _close, UIKit.C_PANEL2, 60, 24))
	v.add_child(h)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 24)
	v.add_child(tabs)
	_tab_general()
	_tab_graphics()
	_tab_audio()
	_tab_voice()
	_tab_controls()


func _close() -> void:
	closed.emit()
	queue_free()


func _page(title: String) -> VBoxContainer:
	var inner := UIKit.vbox(14)
	var s := UIKit.scroll(inner)
	s.name = title
	tabs.add_child(s)
	return inner


func _slider_row(parent: Control, text: String, key: String, min_v: float, max_v: float, step := 0.05) -> void:
	var h := UIKit.hbox(12)
	var l := UIKit.label(text, 24)
	l.custom_minimum_size = Vector2(380, 0)
	h.add_child(l)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step
	sl.value = float(Settings.get_value(key))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(0, 48)
	var val := UIKit.label("%.2f" % sl.value, 22, UIKit.C_MUTED)
	val.custom_minimum_size = Vector2(80, 0)
	sl.value_changed.connect(func(x: float) -> void:
		val.text = "%.2f" % x
		Settings.set_value(key, x))
	h.add_child(sl)
	h.add_child(val)
	parent.add_child(h)


func _check_row(parent: Control, text: String, key: String) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = bool(Settings.get_value(key))
	c.add_theme_font_size_override("font_size", 24)
	c.custom_minimum_size = Vector2(0, 56)
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	parent.add_child(c)


func _option_row(parent: Control, text: String, key: String, options: Array, labels: Array) -> void:
	var h := UIKit.hbox(12)
	var l := UIKit.label(text, 24)
	l.custom_minimum_size = Vector2(380, 0)
	h.add_child(l)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(320, 56)
	ob.add_theme_font_size_override("font_size", 24)
	for i in options.size():
		ob.add_item(str(labels[i]), i)
		if options[i] == Settings.get_value(key):
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void: Settings.set_value(key, options[i]))
	h.add_child(ob)
	parent.add_child(h)


func _tab_general() -> void:
	var p := _page("General")
	_option_row(p, Loc.t("language"), "lang", ["es", "en"], ["Español", "English (interfaz)"])
	p.add_child(UIKit.label("Los diálogos locales están en español; con la IA remota los clientes responden en el idioma elegido.", 20, UIKit.C_MUTED))
	_option_row(p, Loc.t("shift_length"), "shift_minutes", [6, 9, 12], ["Corta (6 min)", "Normal (9 min)", "Larga (12 min)"])
	_check_row(p, Loc.t("subtitles"), "subtitles")


func _tab_graphics() -> void:
	var p := _page("Gráficos")
	_option_row(p, Loc.t("quality"), "quality", [0, 1, 2], [Loc.t("low"), Loc.t("medium"), Loc.t("high")])
	_option_row(p, Loc.t("fps_limit"), "fps_limit", [30, 60], ["30 FPS (ahorra batería)", "60 FPS"])
	_check_row(p, Loc.t("auto_quality"), "auto_quality")
	p.add_child(UIKit.label("Baja: sin sombras, menos compañeros y resolución 75 %. Media: sombras del sol. Alta: antialiasing, brillo y luces extra. Algunos cambios se aplican al volver a entrar en la oficina.", 20, UIKit.C_MUTED))


func _tab_audio() -> void:
	var p := _page("Audio")
	_slider_row(p, Loc.t("master"), "vol_master", 0, 1)
	_slider_row(p, Loc.t("music"), "vol_music", 0, 1)
	_slider_row(p, Loc.t("sfx"), "vol_sfx", 0, 1)
	_slider_row(p, Loc.t("voices"), "vol_voice", 0, 1)
	p.add_child(UIKit.button("Probar sonido", func() -> void: Audio.play("cash"), UIKit.C_PANEL2, 60, 22))


func _tab_voice() -> void:
	var p := _page("Voz e IA")
	p.add_child(UIKit.label("Servidor de IA (backend de TeleTimo). Sin él, el juego usa el diálogo local y el modo texto. Las claves de los proveedores viven en el servidor, nunca en el teléfono.", 20, UIKit.C_MUTED))
	var url := LineEdit.new()
	url.placeholder_text = "https://mi-servidor.ejemplo.com"
	url.text = str(Settings.get_value("backend_url"))
	url.custom_minimum_size = Vector2(0, 60)
	url.add_theme_font_size_override("font_size", 22)
	url.text_changed.connect(func(s: String) -> void: Settings.set_value("backend_url", s))
	p.add_child(UIKit.label(Loc.t("backend_url"), 24))
	p.add_child(url)
	var code := LineEdit.new()
	code.placeholder_text = "Código que configuraste en el servidor (APP_ACCESS_CODE)"
	code.secret = true
	code.text = str(Settings.get_value("access_code"))
	code.custom_minimum_size = Vector2(0, 60)
	code.add_theme_font_size_override("font_size", 22)
	code.text_changed.connect(func(s: String) -> void: Settings.set_value("access_code", s))
	p.add_child(UIKit.label(Loc.t("access_code"), 24))
	p.add_child(code)
	conn_label = UIKit.label("Estado: " + AI.status, 22, UIKit.C_MUTED)
	p.add_child(UIKit.button(Loc.t("test_connection"), _test_conn, UIKit.C_BLUE, 60, 22))
	p.add_child(conn_label)
	_option_row(p, Loc.t("tts_engine"), "tts_mode", ["system", "remote", "off"], ["Voz del sistema (gratis, sin conexión)", "Voz remota del servidor (de pago)", "Sin voz (solo subtítulos)"])
	p.add_child(UIKit.label(Voice.tts_status_text(), 20, UIKit.C_MUTED))
	_slider_row(p, "Velocidad de las voces", "voice_speed", 0.7, 1.6)
	_option_row(p, Loc.t("stt_engine"), "stt_mode", ["remote", "off"], ["Servidor IA (requiere conexión)", "Desactivado (solo texto)"])
	_check_row(p, "Terminar de escuchar al detectar silencio", "vad_auto_stop")
	var consent := bool(Settings.get_value("mic_consent"))
	p.add_child(UIKit.label("Permiso de micrófono dentro del juego: %s" % ("aceptado" if consent else "no aceptado todavía"), 20, UIKit.C_MUTED))
	if consent:
		p.add_child(UIKit.button("Retirar consentimiento del micrófono", func() -> void: Settings.set_value("mic_consent", false), UIKit.C_PANEL2, 56, 20))
	p.add_child(UIKit.button("Probar voz del cliente", func() -> void:
		Voice.speak("¡Hola! Soy un cliente de prueba y no pienso comprarle nada… o quizá sí.", {"id": "test", "gender": "f", "pitch": 1.1, "rate": 1.0, "remote_voice": "coral", "instructions": "Tono divertido"}), UIKit.C_PANEL2, 56, 20))


func _test_conn() -> void:
	conn_label.text = "Probando…"
	var r := await AI.health()
	if not is_instance_valid(conn_label):
		return
	if r.get("ok", false):
		var d: Dictionary = r.get("data", {})
		conn_label.text = "Servidor OK. LLM: %s · STT: %s · TTS: %s · Sesión: %s" % [d.get("llm", "?"), d.get("stt", "?"), d.get("tts", "?"), "OK" if r.get("session", false) else "rechazada (¿código de acceso?)"]
		conn_label.add_theme_color_override("font_color", UIKit.C_GOOD if r.get("session", false) else UIKit.C_ACCENT)
	else:
		conn_label.text = "Sin conexión: " + str(r.get("error", ""))
		conn_label.add_theme_color_override("font_color", UIKit.C_BAD)


func _tab_controls() -> void:
	var p := _page("Controles")
	_slider_row(p, Loc.t("sensitivity"), "cam_sensitivity", 0.3, 2.0)
	_slider_row(p, Loc.t("joystick_size"), "joystick_scale", 0.6, 1.6)
	_check_row(p, Loc.t("swap_sides"), "swap_sides")
	p.add_child(UIKit.label("En ordenador: WASD para moverte, botón derecho del ratón para girar la cámara, E para usar, Mayús para correr.", 20, UIKit.C_MUTED))
