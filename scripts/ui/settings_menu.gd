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


var _refresh_cb: Callable
var _progress_cb: Callable


func _exit_tree() -> void:
	if _refresh_cb.is_valid() and Brain.state_changed.is_connected(_refresh_cb):
		Brain.state_changed.disconnect(_refresh_cb)
	if _progress_cb.is_valid() and Brain.download_progress.is_connected(_progress_cb):
		Brain.download_progress.disconnect(_progress_cb)


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
	var p := _page("IA y voz")
	p.add_child(UIKit.label("Los clientes los interpreta una IA que funciona dentro del móvil: no hace falta Internet ni ninguna cuenta. Solo la primera vez se descargan sus modelos.", 20, UIKit.C_MUTED))
	conn_label = UIKit.label("", 22, UIKit.C_TEXT)
	p.add_child(conn_label)
	var dl_bar := UIKit.bar(0, 100, UIKit.C_ACCENT, 18)
	p.add_child(dl_bar)
	var refresh := func() -> void:
		if not is_instance_valid(conn_label) or not is_instance_valid(dl_bar):
			return
		var lines := ["Conversación: " + Brain.status_text(), "Oído: " + Voice.stt_status_text(), "Voces: " + Voice.tts_status_text()]
		if Brain.downloading:
			lines.append("Descargando: %d %%" % int(Brain.download_percent()))
		elif not Brain.missing_packs().is_empty() and Brain.available:
			lines.append("Pendiente de descargar: %.2f GB" % (Brain.missing_bytes() / 1073741824.0))
		if Brain.last_error != "" and Brain.llm_state in ["error", "missing"]:
			lines.append("Último error: " + Brain.last_error)
		conn_label.text = "\n".join(PackedStringArray(lines))
		dl_bar.visible = Brain.downloading
		dl_bar.value = Brain.download_percent()
	refresh.call()
	_refresh_cb = refresh
	_progress_cb = func(_a: int, _b: int, _c: String) -> void: refresh.call()
	Brain.state_changed.connect(_refresh_cb)
	Brain.download_progress.connect(_progress_cb)
	var h := UIKit.hbox(10)
	p.add_child(h)
	var dl := UIKit.button("Descargar modelos de IA", func() -> void:
		if Brain.missing_packs().is_empty():
			Brain.load_all()
		else:
			Brain.download_all(), UIKit.C_GOOD, 60, 22)
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(dl)
	h.add_child(UIKit.button("Pausar", func() -> void: Brain.cancel_download(), UIKit.C_PANEL2, 60, 22))
	_option_row(p, "Tamaño del cerebro", "llm_size", ["auto", "normal", "ligero"], ["Automático según la memoria", "Normal: Gemma 4 E2B (mejor conversación, 3,1 GB, 6 GB de RAM)", "Ligero: Qwen3.5 0.8B (0,5 GB) — conversa con poca coherencia; solo para móviles con menos de 5 GB de RAM"])
	_check_row(p, "Usar la GPU para la conversación (EXPERIMENTAL: en muchos móviles Snapdragon/Adreno bloquea la IA; si la activas y falla, el juego vuelve solo al procesador)", "ai_gpu")
	_option_row(p, Loc.t("tts_engine"), "tts_mode", ["ia", "system", "off"], ["Voces neuronales (IA en el móvil)", "Voz del sistema Android", "Sin voz (solo subtítulos)"])
	_check_row(p, "Terminar de escuchar al detectar silencio", "vad_auto_stop")
	var consent := bool(Settings.get_value("mic_consent"))
	p.add_child(UIKit.label("Permiso de micrófono dentro del juego: %s" % ("aceptado" if consent else "no aceptado todavía"), 20, UIKit.C_MUTED))
	if consent:
		p.add_child(UIKit.button("Retirar consentimiento del micrófono", func() -> void: Settings.set_value("mic_consent", false), UIKit.C_PANEL2, 56, 20))
	p.add_child(UIKit.button("Probar voz de un cliente", func() -> void:
		if Brain.voice_state != "ready" and Brain.missing_packs().is_empty():
			await Brain.load_voice()
		Voice.speak("¡Hola! Soy un cliente de prueba y no pienso comprarle nada… o quizá sí.", {"id": "test", "female": true, "pitch": 1.05, "speed": 1.0}), UIKit.C_PANEL2, 56, 20))
	# Diagnóstico: comprobar archivos, probar la IA y ver/copiar el registro técnico
	p.add_child(UIKit.label("Diagnóstico", 24, UIKit.C_ACCENT))
	var diag := UIKit.label("", 19, UIKit.C_MUTED)
	p.add_child(diag)
	var dh := UIKit.hbox(8)
	p.add_child(dh)
	dh.add_child(UIKit.button("Comprobar archivos", func() -> void:
		var out := []
		for r in Brain.verify_packs():
			out.append("%s %s: %s" % ["✔" if r["ok"] else "✘", r["label"], r["detail"]])
		diag.text = "\n".join(PackedStringArray(out)), UIKit.C_PANEL2, 56, 19))
	dh.add_child(UIKit.button("Probar la IA", func() -> void:
		if Brain.llm_state != "ready":
			diag.text = "La IA no está cargada (%s). Pulsa «Descargar modelos de IA» para cargarla." % Brain.status_text()
			if Brain.missing_packs().is_empty() and Brain.llm_state != "loading":
				Brain.load_all()
			return
		diag.text = "Probando (máximo 45 s)…"
		var t: Dictionary = await Brain.self_test()
		if not is_instance_valid(diag):
			return
		if t["ok"]:
			diag.text = "✔ La IA responde. Primer token en %.1f s; %d tokens en %.1f s (%.1f tokens/s). Respuesta: %s" % [t["first_ms"] / 1000.0, t["tokens"], t["total_ms"] / 1000.0, t["tok_per_s"], AIResponse.sanitize_text(t["text"], 120)]
		else:
			diag.text = "✘ La IA no respondió bien: %s. Mira el registro y, si quieres, cópialo para enviarlo." % t["error_text"], UIKit.C_PANEL2, 56, 19))
	dh.add_child(UIKit.button("Ver registro", func() -> void: _show_log(), UIKit.C_PANEL2, 56, 19))
	p.add_child(UIKit.button("Borrar modelos descargados (libera espacio)", func() -> void:
		Brain.delete_models()
		refresh.call(), Color("7b241c"), 56, 20))


func _show_log() -> void:
	var md := UIKit.modal(self, 900)
	var box: VBoxContainer = md["box"]
	box.add_child(UIKit.label("Registro técnico de la IA", 26, UIKit.C_ACCENT))
	box.add_child(UIKit.label("Solo tiempos, tamaños de archivos y errores; nunca lo que dices.", 17, UIKit.C_MUTED))
	var te := TextEdit.new()
	te.text = AILog.text().right(8000)
	te.editable = false
	te.custom_minimum_size = Vector2(840, 420)
	te.add_theme_font_size_override("font_size", 15)
	box.add_child(te)
	var h := UIKit.hbox(10)
	box.add_child(h)
	h.add_child(UIKit.button("Copiar", func() -> void: DisplayServer.clipboard_set(AILog.text()), UIKit.C_BLUE))
	h.add_child(UIKit.button("Cerrar", func() -> void: md["layer"].queue_free(), UIKit.C_PANEL2))


func _tab_controls() -> void:
	var p := _page("Controles")
	_slider_row(p, Loc.t("sensitivity"), "cam_sensitivity", 0.3, 2.0)
	_slider_row(p, Loc.t("joystick_size"), "joystick_scale", 0.6, 1.6)
	_check_row(p, Loc.t("swap_sides"), "swap_sides")
	p.add_child(UIKit.label("En ordenador: WASD para moverte, botón derecho del ratón para girar la cámara, E para usar, Mayús para correr.", 20, UIKit.C_MUTED))
