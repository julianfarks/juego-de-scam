class_name CallScreen
extends Control
## Pantalla de llamada: selección de oferta, «videollamada» 3D del cliente,
## transcripción con subtítulos, micrófono con estados claros, modo texto, frases
## rápidas, cierre de venta (reglas), tarjeta ficticia y resumen final.

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
var offer_id := ""
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


func open(p_lead: Dictionary, p_flags: Dictionary) -> void:
	lead = p_lead
	flags = p_flags
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	stage = ClientStage.new()
	add_child(stage)
	stage.show_client(lead["client_id"])
	_show_offer_picker()


# ------------------------------------------------------------ Selección de oferta

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
	h.add_child(lv)
	var vid := TextureRect.new()
	vid.texture = stage.get_texture()
	vid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vid.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	vid.custom_minimum_size = Vector2(420, 340)
	lv.add_child(vid)
	lv.add_child(UIKit.label(c["name"], 30, UIKit.C_ACCENT))
	var stars := "★".repeat(int(lead["stars"])) + "☆".repeat(3 - int(lead["stars"]))
	lv.add_child(UIKit.label("Dificultad: " + stars, 22))
	if m.get("show_personality", 0):
		var p := PersonalityDB.get_p(c["personality"])
		lv.add_child(UIKit.label("CRM: %s — %s" % [p["name"], p["desc"]], 20, UIKit.C_BLUE))
	else:
		lv.add_child(UIKit.label("Compra el CRM para ver su personalidad.", 18, UIKit.C_MUTED))
	if m.get("show_likes", 0):
		lv.add_child(UIKit.label("Le gusta: %s\nOdia: %s" % [", ".join(PackedStringArray(c["likes"])), ", ".join(PackedStringArray(c["dislikes"])) if not c["dislikes"].is_empty() else "nada en especial"], 19, UIKit.C_GOOD))
	if lead.get("callback", false):
		lv.add_child(UIKit.label("Te pidió que le volvieras a llamar: empieza con más confianza.", 19, UIKit.C_GOOD))
	var rv := UIKit.vbox(10)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(rv)
	rv.add_child(UIKit.label("Elige qué oferta ficticia vas a proponer", 28))
	var list := UIKit.vbox(8)
	for oid in OfferDB.unlocked_for_day(Game.day):
		var o := OfferDB.get_o(oid)
		var row := UIKit.panel(UIKit.C_PANEL2 if oid != lead["offer"] else Color("3d5a80"), 14, 10)
		var rh := UIKit.hbox(10)
		row.add_child(rh)
		var info := UIKit.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UIKit.label("%s  —  ref. %s" % [o["name"], UIKit.money(int(o["price"]))], 22))
		var sub := String(o["pitch"])
		if oid == lead["offer"]:
			sub = "[Sugerida] " + sub
		if m.get("show_likes", 0):
			var aff := ClientDB.offer_affinity(lead["client_id"], oid)
			sub += "  (afinidad: %s)" % ("alta" if aff > 1.1 else ("baja" if aff < 0.9 else "normal"))
		info.add_child(UIKit.label(sub, 17, UIKit.C_MUTED))
		rh.add_child(info)
		var b := UIKit.button("Llamar", _begin_call.bind(oid), UIKit.C_GOOD, 60, 22)
		b.custom_minimum_size = Vector2(130, 60)
		rh.add_child(b)
		list.add_child(row)
	rv.add_child(UIKit.scroll(list))
	rv.add_child(UIKit.button("No llamar ahora", func() -> void: _abort(), UIKit.C_PANEL2, 60, 22))


func _abort() -> void:
	call_finished.emit({})
	queue_free()


# ------------------------------------------------------------ Llamada

func _begin_call(oid: String) -> void:
	offer_id = oid
	offer_panel.queue_free()
	Audio.play("pickup")
	_build_call_ui()
	session = CallSession.new()
	add_child(session)
	session.use_remote = true
	session.client_spoke.connect(_on_client_spoke)
	session.state_updated.connect(_refresh_state)
	session.busy_changed.connect(_on_busy)
	session.sale_completed.connect(_on_sale)
	session.ended.connect(_on_ended)
	session.notice.connect(func(t: String) -> void: _system_line(t))
	Voice.mic_state_changed.connect(_on_mic_state)
	Voice.transcription_ready.connect(_on_transcription)
	Voice.transcription_failed.connect(_on_transcription_failed)
	Voice.speech_finished.connect(_on_speech_finished)
	Voice.reset_state()
	Game.on_call = true
	session.start(lead["client_id"], offer_id, Game.day, Game.mods(), flags)
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
	pers_label = UIKit.label(("Personalidad: " + PersonalityDB.get_p(c["personality"])["name"]) if m.get("show_personality", 0) else "Personalidad: ??? (CRM)", 18, UIKit.C_BLUE)
	left.add_child(pers_label)
	left.add_child(UIKit.label("Oferta: " + OfferDB.get_o(offer_id)["name"], 18, UIKit.C_MUTED))
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
	thinking_label = UIKit.label("", 20, UIKit.C_ACCENT)
	right.add_child(thinking_label)
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
	var c := ClientDB.get_c(lead["client_id"])
	var head := "Tú" if who == "player" else (String(c["name"]).split(" ")[0] if who == "client" else "Sistema")
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
	var c := ClientDB.get_c(lead["client_id"])
	var p := PersonalityDB.get_p(c["personality"])
	var female: bool = c["gender"] == "f"
	var fv := ["coral", "nova", "shimmer", "sage"]
	var mv := ["ash", "onyx", "echo", "verse", "ballad"]
	var h := absi(hash(lead["client_id"]))
	return {
		"id": lead["client_id"], "gender": c["gender"],
		"pitch": float(p["voice"]["pitch"]) * (1.12 if female else 0.88),
		"rate": float(p["voice"]["rate"]),
		"remote_voice": fv[h % fv.size()] if female else mv[h % mv.size()],
		"instructions": "Habla en español neutro, natural y expresivo. Personaje: %s. %s" % [p["name"], p["prompt"]],
	}


func _on_client_spoke(text: String, emotion: String, gesture: String, source: String) -> void:
	last_client_line = text
	var src: String = {"remote": "IA remota", "local": "diálogo local", "rules": "reglas"}.get(source, source)
	# Sin subtítulos solo se oculta el texto si de verdad hay voz que escuchar
	var shown := text if bool(Settings.get_value("subtitles")) or not Voice.can_speak() else "(habla — subtítulos desactivados; pulsa Repetir para volver a oírlo)"
	_bubble(shown, "client", src)
	source_label.text = Loc.t("ai_remote") if source == "remote" else Loc.t("ai_local")
	source_label.add_theme_color_override("font_color", UIKit.C_GOOD if source == "remote" else UIKit.C_MUTED)
	stage.set_emotion(emotion)
	stage.gesture(gesture)
	stage.speaking = true
	Voice.speak(text, _voice_profile())


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
		_system_line("Espera, el cliente todavía está pensando.")
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
	_bubble("¿Me facilita los datos de pago para completar el pedido?", "player", "acción")
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
	thinking_label.text = Loc.t("mic_processing") if b else ""
	close_btn.disabled = b
	send_btn.disabled = b


# ------------------------------------------------------------ Micrófono

func _on_mic_pressed() -> void:
	match Voice.mic_state:
		"listening":
			Voice.stop_listening()
		"transcribing", "processing":
			pass
		_:
			if not bool(Settings.get_value("mic_consent")):
				_ask_mic_consent()
				return
			if not Voice.stt_available():
				_system_line("El reconocimiento de voz necesita el servidor IA (Ajustes → Voz e IA). Mientras tanto, escribe tus frases.")
				Voice._set_mic_state("offline")
				text_edit.grab_focus()
				return
			Voice.start_listening()


func _ask_mic_consent() -> void:
	var md := UIKit.modal(self, 760)
	var box: VBoxContainer = md["box"]
	box.add_child(UIKit.label("Usar el micrófono", 30, UIKit.C_ACCENT))
	box.add_child(UIKit.label("El micrófono solo graba mientras el botón está en rojo («Escuchando»). El audio se envía a TU servidor de IA para convertirlo en texto y no se guarda en el juego. Puedes jugar siempre por texto.", 22))
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
	obj_label.text = ("Objeciones: " + ", ".join(PackedStringArray(objs)) if not objs.is_empty() else "Sin objeciones pendientes") + extra
	timer_bar.max_value = st.time_limit
	timer_bar.value = maxf(0.0, st.time_limit - st.elapsed)


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
		"Oferta: %s" % r["offer_name"],
		"Duración: %d s  ·  Turnos: %d" % [r["duration"], r["turns"]],
		"Objeciones resueltas: %d (pendientes: %d)" % [r["objections_resolved"], r["objections_pending"]],
		"Contradicciones: %d" % r["contradictions"],
		"Cantidad ficticia: %s" % UIKit.money(int(r.get("final_amount", 0))),
		"Respuestas: %d con IA remota, %d con diálogo local" % [r["remote_turns"], r["local_turns"]],
	]
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
	if Voice.transcription_ready.is_connected(_on_transcription):
		Voice.transcription_ready.disconnect(_on_transcription)
		Voice.transcription_failed.disconnect(_on_transcription_failed)
		Voice.mic_state_changed.disconnect(_on_mic_state)
		Voice.speech_finished.disconnect(_on_speech_finished)
	Voice.cancel_listening()
	Voice.stop_speaking()
