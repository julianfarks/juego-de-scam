class_name CallScreen
extends Control
## Pantalla de llamada: ficha del cliente, «videollamada» 3D, conversación LIBRE por
## voz o texto (el jugador propone lo que quiera; el catálogo de ideas es opcional),
## estado claro de cada fase (preparando, tu turno, pensando, escuchando,
## transcribiendo, hablando, error), errores recuperables (Reintentar / Seguir sin
## IA), cierre de venta por reglas, tarjeta ficticia y resumen con la transacción.

signal call_finished(result: Dictionary)

const QUICK_PHRASES := [
	"Hola, buenas tardes, le llamo de TeleTimo.",
	"Le entiendo perfectamente, no se preocupe.",
	"Es muy sencillo: es como un seguro, pero divertido.",
	"Le doy garantía de devolución por escrito.",
	"Solo hoy tiene un descuento especial.",
	"Sinceramente, le va a encantar.",
]

var lead: Dictionary
var flags: Dictionary
var session: CallSession
var stage: ClientStage
var opening_idea := ""          # texto propuesto antes de llamar (opcional, editable)
var last_client_line := ""
var silence_requested := false
var soundboard_left := 1
var summary_shown := false
var last_result: Dictionary = {}

# UI
var root_box: HBoxContainer
var left: VBoxContainer
var right: VBoxContainer
var video: TextureRect
var name_label: Label
var pers_label: Label
var source_label: Label
var meters := {}
var obj_label: Label
var timer_bar: ProgressBar
var transcript: VBoxContainer
var transcript_scroll: ScrollContainer
var mic_btn: Button
var mic_label: Label
var mic_level: ProgressBar
var text_edit: LineEdit
var send_btn: Button
var close_btn: Button
var laugh_btn: Button
var silence_btn: Button
var hang_btn: Button
var thinking_label: Label
var offer_panel: Control
var proposal_label: Label
var status_chip: PanelContainer
var status_label: Label
var error_panel: PanelContainer
var error_label: Label
var _think_t0 := 0


func open(p_lead: Dictionary, p_flags: Dictionary) -> void:
	lead = p_lead
	flags = p_flags
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	# La oficina 3D queda tapada durante la llamada: se deja de dibujar para que el
	# procesador y la GPU queden libres para la IA (el vídeo del cliente usa su propio
	# viewport y sigue funcionando).
	get_viewport().disable_3d = true
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	stage = ClientStage.new()
	add_child(stage)
	stage.show_client(lead["client_id"])
	session = CallSession.new()
	add_child(session)
	session.prepare(lead["client_id"], flags)
	_show_offer_picker()


# ------------------------------------------------------------ Ficha antes de llamar

func _short_name() -> String:
	var parts := String(ClientDB.get_c(lead["client_id"])["name"]).split(" ")
	if parts.size() > 1 and parts[0] in ["Doña", "Don", "Ing.", "Prof.", "Dr.", "Dra.", "Sr.", "Sra."]:
		return parts[0] + " " + parts[1]
	return parts[0]


func _show_offer_picker() -> void:
	var c := ClientDB.get_c(lead["client_id"])
	var m := Game.mods()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	offer_panel = margin
	var h := UIKit.hbox(20)
	margin.add_child(h)
	var lv := UIKit.vbox(10)
	lv.custom_minimum_size = Vector2(420, 0)
	h.add_child(UIKit.scroll(lv))
	var vid := TextureRect.new()
	vid.texture = stage.get_texture()
	vid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vid.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	vid.custom_minimum_size = Vector2(420, 300)
	lv.add_child(vid)
	lv.add_child(UIKit.label(c["name"], 30, UIKit.C_ACCENT))
	var stars := "★".repeat(int(lead["stars"])) + "☆".repeat(3 - int(lead["stars"]))
	lv.add_child(UIKit.label("Dificultad: " + stars, 22))
	var pp := PersonalityDB.get_p(c["personality"])
	lv.add_child(UIKit.label("Carácter: %s — %s" % [pp["name"], pp["desc"]], 20, UIKit.C_BLUE))
	lv.add_child(UIKit.label(("IA local lista: el cliente entenderá lo que le digas." if Brain.is_ready() else "IA no disponible (%s): este cliente usará el diálogo básico." % Brain.status_text().to_lower()), 17, UIKit.C_GOOD if Brain.is_ready() else Color("ff9f43")))
	if m.get("show_situation", 0):
		var sit := UIKit.label("CRM: preparando ficha…", 18, UIKit.C_BLUE)
		lv.add_child(sit)
		var past := []
		for e in Save.data["crm"]:
			if e.get("client_id", "") == lead["client_id"]:
				past.append("día %d: %s" % [int(e["day"]), Economy.OUTCOMES.get(e["outcome"], e["outcome"])])
		var fill := func() -> void:
			if is_instance_valid(sit):
				sit.text = "CRM: %s\nLlamadas anteriores: %s" % [session.situation if session and session.situation != "" else "sin datos", ", ".join(PackedStringArray(past.slice(-3))) if not past.is_empty() else "ninguna"]
		get_tree().process_frame.connect(fill, CONNECT_ONE_SHOT)
	if m.get("show_likes", 0):
		lv.add_child(UIKit.label("Le gusta: %s\nOdia: %s" % [", ".join(PackedStringArray(c["likes"])), ", ".join(PackedStringArray(c["dislikes"])) if not c["dislikes"].is_empty() else "nada en especial"], 19, UIKit.C_GOOD))
	if lead.get("callback", false):
		lv.add_child(UIKit.label("Te pidió que le volvieras a llamar: empieza con más confianza.", 19, UIKit.C_GOOD))
	# Derecha: llamada libre + ideas opcionales
	var rv := UIKit.vbox(10)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(rv)
	rv.add_child(UIKit.label("Llamada libre", 30))
	rv.add_child(UIKit.label("Vende lo que quieras: un queso artesanal, hierbas, jardinería, un seguro absurdo… Puedes inventarlo sobre la marcha, cambiar de idea, negociar el precio o bromear. Habla por el micrófono o escribe.", 19, UIKit.C_MUTED))
	var idea := LineEdit.new()
	idea.placeholder_text = "Tu primera frase (opcional): «Le llamo para ofrecerle…»"
	idea.custom_minimum_size = Vector2(0, 60)
	idea.add_theme_font_size_override("font_size", 21)
	idea.max_length = 300
	idea.text_changed.connect(func(t: String) -> void: opening_idea = t)
	rv.add_child(idea)
	var call_btn := UIKit.button("Llamar", func() -> void: _begin_call(), UIKit.C_GOOD, 76, 30)
	rv.add_child(call_btn)
	rv.add_child(UIKit.label("¿Sin ideas? Catálogo opcional (toca uno para usarlo como primera frase; puedes editarla):", 18, UIKit.C_MUTED))
	var list := UIKit.vbox(6)
	for oid in OfferDB.unlocked_for_day(Game.day):
		var o := OfferDB.get_o(oid)
		var pitch := Persona.catalog_pitch(oid)
		var b := UIKit.button("%s — ref. %s" % [o["name"], UIKit.money(int(o["price"]))], func() -> void:
			idea.text = pitch
			opening_idea = pitch, UIKit.C_PANEL2, 52, 18)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	var sc := UIKit.scroll(list)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(sc)
	rv.add_child(UIKit.button("No llamar ahora", func() -> void: _abort(), UIKit.C_PANEL2, 56, 20))


func _abort() -> void:
	if session:
		session.cancel_pending()
	call_finished.emit({})
	queue_free()


# ------------------------------------------------------------ Llamada

func _begin_call() -> void:
	offer_panel.queue_free()
	Audio.play("pickup")
	_build_call_ui()
	session.client_spoke.connect(_on_client_spoke)
	session.client_partial.connect(_on_client_partial)
	session.client_text_ready.connect(_on_client_text_ready)
	session.state_updated.connect(_refresh_state)
	session.busy_changed.connect(_on_busy)
	session.phase_changed.connect(_on_phase)
	session.ai_error.connect(_on_ai_error)
	session.proposal_changed.connect(func(_t: String) -> void: _refresh_state())
	session.sale_completed.connect(_on_sale)
	session.ended.connect(_on_ended)
	session.notice.connect(func(t: String) -> void: _system_line(t))
	Voice.mic_state_changed.connect(_on_mic_state)
	Voice.transcription_ready.connect(_on_transcription)
	Voice.transcription_failed.connect(_on_transcription_failed)
	Voice.speech_finished.connect(_on_speech_finished)
	Voice.reset_state()
	Game.on_call = true
	if opening_idea.strip_edges() != "":
		text_edit.text = opening_idea.strip_edges()
	session.start(lead["client_id"], Game.day, Game.mods(), flags)
	_on_phase(session.phase)
	_on_mic_state(Voice.mic_state)
	if Game.is_event("phone_outage"):
		_system_line("La centralita está caída…")
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			if session and session.active:
				session.interrupt("tech_fail"))


func _build_call_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	root_box = UIKit.hbox(16)
	margin.add_child(root_box)
	left = UIKit.vbox(8)
	var left_scroll := UIKit.scroll(left)
	left_scroll.custom_minimum_size = Vector2(430, 0)
	left_scroll.size_flags_horizontal = Control.SIZE_FILL
	root_box.add_child(left_scroll)
	right = UIKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.add_child(right)
	# Vídeo del cliente
	var vid_panel := UIKit.panel(Color.BLACK, 16, 4)
	left.add_child(vid_panel)
	video = TextureRect.new()
	video.texture = stage.get_texture()
	video.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	video.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	video.custom_minimum_size = Vector2(410, 250)
	vid_panel.add_child(video)
	var c := ClientDB.get_c(lead["client_id"])
	var nh := UIKit.hbox(8)
	name_label = UIKit.label(c["name"], 24, UIKit.C_ACCENT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nh.add_child(name_label)
	source_label = UIKit.label("", 16, UIKit.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	source_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	nh.add_child(source_label)
	left.add_child(nh)
	var m := Game.mods()
	pers_label = UIKit.label("Carácter: " + PersonalityDB.get_p(c["personality"])["name"], 18, UIKit.C_BLUE)
	left.add_child(pers_label)
	var pp := UIKit.panel(Color("1d2a3a"), 12, 8)
	proposal_label = UIKit.label("Propuesta: todavía no le has ofrecido nada", 18, Color("cfe3ff"))
	pp.add_child(proposal_label)
	left.add_child(pp)
	for k in [["trust", "Confianza", UIKit.C_GOOD], ["patience", "Paciencia", UIKit.C_BLUE], ["suspicion", "Sospecha", UIKit.C_BAD], ["understanding", "Comprensión", UIKit.C_ACCENT]]:
		var row := UIKit.hbox(8)
		var l := UIKit.label(k[1], 18)
		l.custom_minimum_size = Vector2(150, 0)
		row.add_child(l)
		var b := UIKit.bar(50, 100, k[2], 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
		left.add_child(row)
		meters[k[0]] = [b, l, k[1]]
	obj_label = UIKit.label("", 17, Color("ffb3a7"))
	left.add_child(obj_label)
	timer_bar = UIKit.bar(100, 100, UIKit.C_ACCENT, 12)
	left.add_child(timer_bar)
	# Transcripción
	transcript = UIKit.vbox(8)
	transcript_scroll = UIKit.scroll(transcript)
	var tp := UIKit.panel(Color("161b29"), 16, 10)
	tp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tp.add_child(transcript_scroll)
	right.add_child(tp)
	# Estado de la llamada (siempre visible) + panel de error recuperable
	var sh := UIKit.hbox(10)
	status_chip = UIKit.panel(Color("34495e"), 12, 6)
	status_label = UIKit.label("Preparando al cliente…", 20, Color.WHITE)
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_chip.add_child(status_label)
	sh.add_child(status_chip)
	thinking_label = UIKit.label("", 18, UIKit.C_MUTED)
	thinking_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(thinking_label)
	right.add_child(sh)
	error_panel = UIKit.panel(Color("5b2c2c"), 12, 10)
	var ev := UIKit.vbox(6)
	error_panel.add_child(ev)
	error_label = UIKit.label("", 19, Color("ffd6d6"))
	ev.add_child(error_label)
	var eh := UIKit.hbox(8)
	ev.add_child(eh)
	var rb := UIKit.button("Reintentar", func() -> void:
		error_panel.visible = false
		session.retry(), UIKit.C_GOOD, 56, 20)
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eh.add_child(rb)
	eh.add_child(UIKit.button("Seguir sin IA", func() -> void:
		error_panel.visible = false
		session.continue_basic(), Color("b9770e"), 56, 18))
	eh.add_child(UIKit.button("Ver detalle", func() -> void: _show_ai_log(), UIKit.C_PANEL2, 56, 18))
	error_panel.visible = false
	right.add_child(error_panel)
	# Micrófono + texto
	var mic_row := UIKit.hbox(12)
	right.add_child(mic_row)
	mic_btn = UIKit.button("MIC", _on_mic_pressed, Color("e74c3c"), 100, 28)
	mic_btn.custom_minimum_size = Vector2(130, 100)
	mic_btn.add_theme_stylebox_override("normal", UIKit.flat(Color("e74c3c"), 55))
	mic_btn.add_theme_stylebox_override("pressed", UIKit.flat(Color("c0392b"), 55))
	mic_btn.add_theme_stylebox_override("hover", UIKit.flat(Color("ec7063"), 55))
	mic_row.add_child(mic_btn)
	var mv := UIKit.vbox(6)
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mic_row.add_child(mv)
	mic_label = UIKit.label(Loc.t("mic_ready"), 20)
	mic_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	mic_label.clip_text = true
	mv.add_child(mic_label)
	mic_level = UIKit.bar(0, 1.0, UIKit.C_GOOD, 10)
	mv.add_child(mic_level)
	var th := UIKit.hbox(8)
	text_edit = LineEdit.new()
	text_edit.placeholder_text = "Escribe lo que le dices al cliente…"
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.custom_minimum_size = Vector2(0, 60)
	text_edit.add_theme_font_size_override("font_size", 24)
	text_edit.max_length = 400
	text_edit.text_submitted.connect(func(_t: String) -> void: _send_text())
	th.add_child(text_edit)
	send_btn = UIKit.button(Loc.t("send"), _send_text, UIKit.C_BLUE, 60, 22)
	send_btn.custom_minimum_size = Vector2(120, 60)
	th.add_child(send_btn)
	mv.add_child(th)
	if m.get("quick_phrases", 0):
		var qp := HFlowContainer.new()
		qp.add_theme_constant_override("h_separation", 6)
		qp.add_theme_constant_override("v_separation", 6)
		for ph in QUICK_PHRASES:
			var b := UIKit.button(ph.substr(0, 26) + ("…" if ph.length() > 26 else ""), func() -> void: _say(ph, false), UIKit.C_PANEL2, 46, 16)
			qp.add_child(b)
		right.add_child(qp)
	# Acciones
	var act := UIKit.hbox(8)
	right.add_child(act)
	close_btn = UIKit.button("Pedir datos de pago", func() -> void: _ask_payment(), UIKit.C_GOOD, 66, 22)
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act.add_child(close_btn)
	if m.get("soundboard", 0):
		laugh_btn = UIKit.button("Risas", _laugh, Color("8e44ad"), 66, 22)
		act.add_child(laugh_btn)
	silence_btn = UIKit.button("Pedir silencio", _ask_silence, Color("b9770e"), 66, 20)
	silence_btn.visible = false
	act.add_child(silence_btn)
	act.add_child(UIKit.button(Loc.t("repeat"), _repeat, UIKit.C_PANEL2, 66, 20))
	act.add_child(UIKit.button(Loc.t("cancel"), _cancel, UIKit.C_PANEL2, 66, 20))
	hang_btn = UIKit.button(Loc.t("hang_up"), func() -> void: session.player_hangs_up(), UIKit.C_BAD, 66, 22)
	act.add_child(hang_btn)


func _bubble(text: String, who: String, extra := "") -> void:
	var p := UIKit.panel(Color("2f6690") if who == "player" else (Color("3a3f58") if who == "client" else Color(0.3, 0.25, 0.1, 0.8)), 14, 10)
	var v := UIKit.vbox(2)
	p.add_child(v)
	var head := "Tú" if who == "player" else (_short_name() if who == "client" else "Sistema")
	if extra != "":
		head += "  ·  " + extra
	v.add_child(UIKit.label(head, 16, UIKit.C_MUTED))
	v.add_child(UIKit.label(text, 22))
	var row := UIKit.hbox(0)
	if who == "player":
		row.add_child(UIKit.spacer(0, 60))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(p)
	if who == "client":
		row.add_child(UIKit.spacer(0, 60))
	transcript.add_child(row)
	while transcript.get_child_count() > 40:
		transcript.get_child(0).queue_free()
	await get_tree().process_frame
	if is_instance_valid(transcript_scroll):
		transcript_scroll.scroll_vertical = int(transcript_scroll.get_v_scroll_bar().max_value)


func _system_line(t: String) -> void:
	_bubble(t, "system")


func _voice_profile() -> Dictionary:
	return Persona.voice_for(lead["client_id"])


func _on_client_spoke(text: String, emotion: String, gesture: String, source: String) -> void:
	last_client_line = text
	_remove_partial()
	var src: String = {"ia": "IA local", "basico": "diálogo básico (sin IA)", "reglas": "reglas del juego"}.get(source, source)
	# Sin subtítulos solo se oculta el texto si de verdad hay voz que escuchar
	var shown := text if bool(Settings.get_value("subtitles")) or not Voice.can_speak() else "(habla — subtítulos desactivados; pulsa Repetir para volver a oírlo)"
	_bubble(shown, "client", src)
	if source != "reglas":
		source_label.text = Loc.t("ai_on") if source == "ia" else Loc.t("ai_basic")
		source_label.add_theme_color_override("font_color", UIKit.C_GOOD if source == "ia" else Color("ff9f43"))
	stage.set_emotion(emotion)
	stage.gesture(gesture)
	if _early_spoken != "" and _early_spoken == text:
		_early_spoken = ""
		return
	_early_spoken = ""
	stage.speaking = true
	Voice.speak(text, _voice_profile())


var _early_spoken := ""


## La frase ya está completa: la voz empieza sin esperar al resto de la respuesta.
func _on_client_text_ready(text: String) -> void:
	_early_spoken = text
	stage.speaking = true
	Voice.speak(text, _voice_profile())


## Subtítulo provisional mientras la IA genera la respuesta.
var _partial_label: Label = null


func _on_client_partial(text: String) -> void:
	if not bool(Settings.get_value("subtitles")):
		return
	if _partial_label == null or not is_instance_valid(_partial_label):
		var p := UIKit.panel(Color("2c3047"), 14, 10)
		_partial_label = UIKit.label("", 22, Color("d5d8e6"))
		p.add_child(_partial_label)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := UIKit.hbox(0)
		row.add_child(p)
		row.add_child(UIKit.spacer(0, 60))
		row.name = "Partial"
		transcript.add_child(row)
	_partial_label.text = text + " …"
	transcript_scroll.scroll_vertical = int(transcript_scroll.get_v_scroll_bar().max_value)


func _remove_partial() -> void:
	if _partial_label and is_instance_valid(_partial_label):
		_partial_label.get_parent().get_parent().queue_free()
	_partial_label = null


func _on_speech_finished(_who: String) -> void:
	if stage:
		stage.speaking = false


func _say(text: String, via_voice: bool) -> void:
	if session == null or not session.active:
		return
	text = text.strip_edges()
	if text == "":
		return
	if session.busy:
		_system_line("Espera: %s todavía está contestando (puedes pulsar Cancelar)." % _short_name())
		return
	if session.phase == "error":
		_system_line("La IA ha fallado: pulsa Reintentar o Seguir sin IA.")
		return
	Voice.stop_speaking()
	_bubble(text, "player", "voz" if via_voice else "texto")
	if not via_voice:
		Save.stat_add("text_turns")
	session.player_says(text, via_voice)


func _send_text() -> void:
	var t := text_edit.text
	text_edit.text = ""
	_say(t, false)


func _ask_payment() -> void:
	if session == null or not session.active or session.busy:
		return
	Voice.stop_speaking()
	if session.phase == "error":
		return
	_bubble("¿Entonces le apunto? ¿Me facilita los datos de pago para completar el pedido?", "player", "acción")
	session.attempt_close()


func _laugh() -> void:
	if soundboard_left <= 0:
		_system_line("Las risas enlatadas solo funcionan una vez por llamada.")
		return
	if session.use_soundboard():
		soundboard_left -= 1
		Audio.play("laugh", 0.0)
		_system_line("*Risas enlatadas de fondo*")
		_count_laugh()
		if laugh_btn:
			laugh_btn.disabled = true


func _count_laugh() -> void:
	var n := int(Save.data["stats"].get("laughs_used", 0)) + 1
	Save.data["stats"]["laughs_used"] = n
	if n >= 5:
		Game.unlock("comedian")


func _ask_silence() -> void:
	silence_requested = true
	silence_btn.visible = false
	_system_line("Le haces gestos a Rigo para que se calle. Funciona… más o menos.")


func _repeat() -> void:
	if last_client_line != "":
		stage.speaking = true
		Voice.speak(last_client_line, _voice_profile())


func _cancel() -> void:
	if Voice.mic_state == "listening":
		Voice.cancel_listening()
	elif session and session.busy:
		session.cancel_pending()
		_system_line("Respuesta cancelada. Puedes volver a intentarlo.")
	Voice.stop_speaking()


func _on_busy(b: bool) -> void:
	Voice.set_processing(b)
	close_btn.disabled = b or session.phase == "error"
	send_btn.disabled = b
	if b:
		_think_t0 = Time.get_ticks_msec()


## Fase de la llamada → texto y color del indicador de estado.
func _on_phase(p: String) -> void:
	if status_label == null:
		return
	var txt: String = {
		"preparando": "Preparando a %s…" % _short_name(),
		"listo": "Tu turno: habla o escribe",
		"pensando": "%s está pensando…" % _short_name(),
		"error": "La IA ha fallado",
		"terminada": "Llamada terminada",
	}.get(p, p)
	var col: Color = {"preparando": Color("7d6608"), "listo": Color("1e8449"), "pensando": Color("b9770e"), "error": Color("922b21"), "terminada": Color("34495e")}.get(p, Color("34495e"))
	status_label.text = txt
	status_chip.add_theme_stylebox_override("panel", UIKit.flat(col, 12))
	if p != "error" and error_panel:
		error_panel.visible = false
	if close_btn:
		close_btn.disabled = p != "listo"


func _on_ai_error(message: String, code: String) -> void:
	error_label.text = "%s.\nPuedes reintentar (se abre una conversación nueva con la memoria de esta llamada), seguir con el diálogo básico o colgar.\n(código: %s)" % [message, code]
	error_panel.visible = true
	_remove_partial()


func _show_ai_log() -> void:
	var md := UIKit.modal(self, 900)
	var box: VBoxContainer = md["box"]
	box.add_child(UIKit.label("Registro técnico de la IA", 26, UIKit.C_ACCENT))
	var te := TextEdit.new()
	te.text = AILog.text().right(6000)
	te.editable = false
	te.custom_minimum_size = Vector2(840, 420)
	te.add_theme_font_size_override("font_size", 15)
	box.add_child(te)
	var h := UIKit.hbox(10)
	box.add_child(h)
	h.add_child(UIKit.button("Copiar", func() -> void: DisplayServer.clipboard_set(AILog.text()), UIKit.C_BLUE))
	h.add_child(UIKit.button("Cerrar", func() -> void: md["layer"].queue_free(), UIKit.C_PANEL2))


# ------------------------------------------------------------ Micrófono

func _on_mic_pressed() -> void:
	match Voice.mic_state:
		"listening":
			Voice.stop_listening()
		"transcribing", "processing":
			pass
		_:
			if session and session.phase == "error":
				_system_line("La IA ha fallado: pulsa Reintentar o Seguir sin IA antes de hablar.")
				return
			if not bool(Settings.get_value("mic_consent")):
				_ask_mic_consent()
				return
			if not Voice.stt_available():
				if Brain.voice_state == "loading":
					_system_line("El oído de la IA se está cargando; prueba en unos segundos.")
				else:
					_system_line("Para hablar por micrófono hacen falta los modelos de voz (Ajustes → IA y voz → Descargar). Mientras tanto, escribe tus frases.")
				Voice._set_mic_state("offline")
				text_edit.grab_focus()
				return
			Voice.start_listening()


func _ask_mic_consent() -> void:
	var md := UIKit.modal(self, 760)
	var box: VBoxContainer = md["box"]
	box.add_child(UIKit.label("Usar el micrófono", 30, UIKit.C_ACCENT))
	box.add_child(UIKit.label("El micrófono solo graba mientras el botón está en rojo («Escuchando»). Tu voz se convierte en texto dentro del propio móvil: no se envía a ningún sitio ni se guarda. Puedes jugar siempre por texto.", 22))
	var h := UIKit.hbox(10)
	box.add_child(h)
	var yes := UIKit.button("Aceptar y usar micrófono", func() -> void:
		Settings.set_value("mic_consent", true)
		Voice.request_mic_permission()
		md["layer"].queue_free(), UIKit.C_GOOD)
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(yes)
	h.add_child(UIKit.button("Mejor por texto", func() -> void: md["layer"].queue_free(), UIKit.C_PANEL2))


func _on_mic_state(s: String) -> void:
	if mic_label == null:
		return
	var key: String = {"ready": "mic_ready", "listening": "mic_listening", "transcribing": "mic_transcribing", "processing": "mic_processing", "speaking": "mic_speaking", "error": "mic_error", "offline": "mic_offline"}.get(s, "mic_ready")
	mic_label.text = Loc.t(key)
	var col: Color = {"listening": Color("27ae60"), "transcribing": Color("f39c12"), "processing": Color("f39c12"), "speaking": Color("5dade2"), "error": Color("7f8c8d"), "offline": Color("7f8c8d")}.get(s, Color("e74c3c"))
	mic_btn.add_theme_stylebox_override("normal", UIKit.flat(col, 55))
	mic_btn.text = {"listening": "PARAR", "transcribing": "...", "processing": "...", "speaking": "HABLAR"}.get(s, "MIC")


func _on_transcription(text: String) -> void:
	if session and session.active:
		_say(text, true)
	else:
		Voice.reset_state()


func _on_transcription_failed(reason: String) -> void:
	_system_line(reason)


# ------------------------------------------------------------ Estado

func _refresh_state() -> void:
	if session == null or session.st == null:
		return
	var st := session.st
	var exact: bool = Game.mods().get("show_exact", 0) == 1
	for k in meters.keys():
		var v := float(st.get(k))
		meters[k][0].value = v
		var lvl := "baja" if v < 34 else ("media" if v < 67 else "alta")
		meters[k][1].text = "%s %d" % [meters[k][2], int(v)] if exact else "%s: %s" % [meters[k][2], lvl]
	var objs := []
	for o in st.pending_objections:
		objs.append(PersonalityDB.OBJECTIONS[o]["label"])
	var extra := ""
	if not st.pending_question.is_empty():
		extra = "\nTe preguntó: «%s»" % st.pending_question["text"]
	if st.unfulfilled_promises().size() > 0:
		extra += "\nPromesa pendiente de explicar"
	if st.ai_doubt != "":
		objs.append(st.ai_doubt)
	if st.ai_interest >= 0:
		extra += "\nGanas de comprar (según el cliente): %d/10" % st.ai_interest
	obj_label.text = ("Dudas: " + ", ".join(PackedStringArray(objs)) if not objs.is_empty() else "Sin dudas pendientes") + extra
	timer_bar.max_value = st.time_limit
	timer_bar.value = maxf(0.0, st.time_limit - st.elapsed)
	if proposal_label:
		var ptxt := "Propuesta: " + (st.proposal if st.proposal != "" else "todavía no le has ofrecido nada")
		if st.stated_price > 0:
			ptxt += "\nPrecio dicho: %s%s" % [UIKit.money(st.stated_price), ("  ×%d = %s" % [st.quantity, UIKit.money(st.stated_price * st.quantity)]) if st.quantity > 1 else ""]
		else:
			ptxt += "\nPrecio: aún no lo has dicho"
		if st.contradictions.size() > 0:
			ptxt += "\nContradicciones de precio: %d" % st.contradictions.size()
		proposal_label.text = ptxt


func _process(delta: float) -> void:
	if session and session.active:
		if not session.busy:
			session.tick(delta)
			# Compañero pesado: si no le pides silencio, el cliente se impacienta
			if Game.is_event("interruption") and not silence_requested:
				session.st.patience = maxf(0.0, session.st.patience - delta * 1.2)
				silence_btn.visible = true
		timer_bar.value = maxf(0.0, session.st.time_limit - session.st.elapsed)
	if mic_level:
		mic_level.value = Voice.mic_level
	if thinking_label and session:
		if session.busy:
			thinking_label.text = "%d s · Cancelar para cortar" % int((Time.get_ticks_msec() - _think_t0) / 1000.0)
		elif Voice.mic_state in ["listening", "transcribing", "speaking"]:
			thinking_label.text = {"listening": "Escuchando tu voz…", "transcribing": "Pasando tu voz a texto…", "speaking": "%s habla" % _short_name()}[Voice.mic_state]
		else:
			thinking_label.text = ""


func _on_sale(card: Dictionary, amount: int) -> void:
	Audio.play("cash")
	var md := UIKit.modal(self, 760)
	var box: VBoxContainer = md["box"]
	box.add_child(UIKit.label("¡TRANSACCIÓN FICTICIA COMPLETADA!", 30, UIKit.C_GOOD, HORIZONTAL_ALIGNMENT_CENTER))
	var cardp := UIKit.panel(Color("1f4e79"), 24, 24)
	var cv := UIKit.vbox(6)
	cardp.add_child(cv)
	cv.add_child(UIKit.label("%s   ·   %s" % [card.get("bank", ""), card.get("brand", "")], 22, Color("ffd166")))
	cv.add_child(UIKit.label(card.get("number", ""), 40, Color.WHITE))
	cv.add_child(UIKit.label("%s     VENCE %s     CVV %s" % [String(card.get("holder", "")).to_upper(), card.get("expiry", ""), card.get("cvv", "")], 20))
	cv.add_child(UIKit.label("TARJETA FICTICIA · SOLO EXISTE EN EL JUEGO · NO SIRVE PARA PAGAR", 16, Color("ff9f9f")))
	box.add_child(cardp)
	box.add_child(UIKit.label("Importe (dinero de mentira): " + UIKit.money(amount), 28, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	cardp.scale = Vector2(0.6, 0.6)
	cardp.pivot_offset = Vector2(350, 90)
	var tw := create_tween()
	tw.tween_property(cardp, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	set_meta("sale_modal", md["layer"])


func _on_ended(result: Dictionary) -> void:
	Game.on_call = false
	Voice.cancel_listening()
	Audio.play("hangup", -4.0)
	if result["outcome"] in ["hangup", "contradiction"]:
		Audio.play("wahwah", -2.0)
		stage.gesture("hangup")
	elif result["outcome"] != "success":
		Audio.play("fail", -8.0)
	result["lead"] = lead
	Game.apply_call_result(result)
	await get_tree().create_timer(1.4).timeout
	if has_meta("sale_modal") and is_instance_valid(get_meta("sale_modal")):
		await get_tree().create_timer(1.8).timeout
		get_meta("sale_modal").queue_free()
	Voice.stop_speaking()
	_show_summary(result)


func _show_summary(r: Dictionary) -> void:
	var md := UIKit.modal(self, 820)
	var box: VBoxContainer = md["box"]
	box.add_child(UIKit.label(Loc.t("call_summary"), 32, UIKit.C_ACCENT))
	var good: bool = r["outcome"] == "success"
	box.add_child(UIKit.label(r["outcome_text"], 28, UIKit.C_GOOD if good else UIKit.C_BAD))
	var lines := [
		"Cliente: %s" % r["client_name"],
		"Propuesta: %s" % r["offer_name"],
		"Duración: %d s  ·  Turnos: %d" % [r["duration"], r["turns"]],
		"Objeciones resueltas: %d (pendientes: %d)  ·  Contradicciones: %d" % [r["objections_resolved"], r["objections_pending"], r["contradictions"]],
	]
	if good:
		lines.append("Transacción ficticia: %s × %d = %s" % [UIKit.money(int(r.get("unit_price", 0))), int(r.get("quantity", 1)), UIKit.money(int(r.get("final_amount", 0)))])
		lines.append("Tu comisión: +%s  ·  Saldo: %s" % [UIKit.money(int(r.get("final_commission", 0))), UIKit.money(int(Save.data["money"]))])
	elif int(r.get("final_amount", 0)) == 0 and r["outcome"] in ["interested", "callback"]:
		lines.append("Sin venta, pero queda interesado (pequeño incentivo).")
	if r["mode"] == "ia" or int(r.get("ai_turns", 0)) > 0:
		lines.append("Respuestas: %d de la IA local (media %.1f s)%s%s" % [r["ai_turns"], r["avg_turn_ms"] / 1000.0, (" · %d del diálogo básico" % r["basic_turns"]) if int(r["basic_turns"]) > 0 else "", (" · %d errores de la IA" % r["ai_errors"]) if int(r.get("ai_errors", 0)) > 0 else ""])
	else:
		lines.append("Respuestas: diálogo básico por reglas (sin IA)")
	for l in lines:
		box.add_child(UIKit.label(l, 21))
	var q := Game.quota()
	var inc := int(Game.ledger["income"])
	box.add_child(UIKit.label("Progreso de la cuota: %s / %s" % [UIKit.money(inc), UIKit.money(q)], 22, UIKit.C_ACCENT))
	box.add_child(UIKit.bar(mini(inc, q), q, UIKit.C_GOOD, 20))
	var cp := UIKit.panel(UIKit.C_PANEL2, 14, 12)
	cp.add_child(UIKit.label("«%s»" % r["comment"], 22, Color("ffe8a3")))
	box.add_child(cp)
	box.add_child(UIKit.button(Loc.t("next"), finish))
	last_result = r
	summary_shown = true


func finish() -> void:
	call_finished.emit(last_result)
	queue_free()


func _exit_tree() -> void:
	Game.on_call = false
	if get_viewport():
		get_viewport().disable_3d = false
	if Voice.transcription_ready.is_connected(_on_transcription):
		Voice.transcription_ready.disconnect(_on_transcription)
		Voice.transcription_failed.disconnect(_on_transcription_failed)
		Voice.mic_state_changed.disconnect(_on_mic_state)
		Voice.speech_finished.disconnect(_on_speech_finished)
	Voice.cancel_listening()
	Voice.stop_speaking()
