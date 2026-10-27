class_name HUD
extends Control
## Interfaz durante la jornada: barra superior (día, hora, cuota, IA), objetivos,
## avisos, botones táctiles (usar, correr, pausa) y joystick.

signal interact_pressed
signal pause_pressed
signal run_toggled(on: bool)
signal end_day_pressed

var touch: TouchControls
var top_day: Label
var top_clock: Label
var quota_bar: ProgressBar
var quota_label: Label
var ai_pill: Label
var obj_box: VBoxContainer
var toast_box: VBoxContainer
var interact_btn: Button
var run_btn: Button
var pause_btn: Button
var end_btn: Button
var ring_panel: PanelContainer
var ring_label: Label
var event_label: Label
var hint_label: Label
var _ring_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	touch = TouchControls.new()
	add_child(touch)
	_build_top()
	_build_side()
	_build_buttons()
	Game.money_changed.connect(func(_v: int) -> void: refresh())
	Game.notify.connect(toast)
	Game.event_started.connect(func(_id: String) -> void: _refresh_event())
	Game.event_ended.connect(func(_id: String) -> void: _refresh_event())
	AI.status_changed.connect(func(_s: String) -> void: _refresh_ai())
	refresh()
	_refresh_ai()


func _build_top() -> void:
	var bar := UIKit.panel(Color(0.11, 0.13, 0.2, 0.88), 0, 10)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 74
	add_child(bar)
	var h := UIKit.hbox(18)
	bar.add_child(h)
	top_day = UIKit.label("Día 1", 28, UIKit.C_ACCENT)
	top_day.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(top_day)
	top_clock = UIKit.label("09:00", 30)
	top_clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(top_clock)
	var qv := UIKit.vbox(2)
	qv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quota_label = UIKit.label("Cuota", 20, UIKit.C_MUTED)
	quota_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	quota_label.clip_text = true
	qv.add_child(quota_label)
	quota_bar = UIKit.bar(0, 100, UIKit.C_GOOD, 18)
	qv.add_child(quota_bar)
	h.add_child(qv)
	ai_pill = UIKit.label("", 18, UIKit.C_MUTED)
	ai_pill.custom_minimum_size = Vector2(190, 0)
	h.add_child(ai_pill)
	end_btn = UIKit.button("Fin", func() -> void: end_day_pressed.emit(), UIKit.C_PANEL2, 54, 22)
	end_btn.custom_minimum_size = Vector2(80, 54)
	end_btn.visible = false
	h.add_child(end_btn)
	pause_btn = UIKit.button("II", func() -> void: pause_pressed.emit(), UIKit.C_PANEL2, 54, 26)
	pause_btn.custom_minimum_size = Vector2(70, 54)
	h.add_child(pause_btn)
	touch.exclusions.append(bar)
	event_label = UIKit.label("", 22, Color("ffd6a5"), HORIZONTAL_ALIGNMENT_CENTER)
	event_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	event_label.offset_top = 84
	event_label.offset_left = -360
	event_label.offset_right = 360
	add_child(event_label)


func _build_side() -> void:
	var p := UIKit.panel(Color(0.11, 0.13, 0.2, 0.7), 14, 10)
	p.position = Vector2(12, 86)
	p.custom_minimum_size = Vector2(330, 0)
	add_child(p)
	obj_box = UIKit.vbox(4)
	p.add_child(obj_box)
	touch.exclusions.append(p)
	toast_box = UIKit.vbox(8)
	toast_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toast_box.offset_left = -470
	toast_box.offset_right = -12
	toast_box.offset_top = 86
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_box)
	ring_panel = UIKit.panel(Color("c0392b"), 20, 16)
	ring_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ring_panel.offset_top = 120
	ring_panel.offset_left = -300
	ring_panel.offset_right = 300
	ring_label = UIKit.label("¡LLAMADA ENTRANTE!", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	ring_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	ring_panel.add_child(ring_label)
	ring_panel.visible = false
	ring_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ring_panel)
	hint_label = UIKit.label("", 22, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.offset_top = -60
	hint_label.offset_bottom = -20
	hint_label.offset_left = -400
	hint_label.offset_right = 400
	add_child(hint_label)


func _build_buttons() -> void:
	interact_btn = UIKit.button("Usar", func() -> void: interact_pressed.emit(), UIKit.C_ACCENT, 150, 26)
	interact_btn.custom_minimum_size = Vector2(170, 150)
	interact_btn.add_theme_stylebox_override("normal", UIKit.flat(UIKit.C_ACCENT, 75))
	interact_btn.add_theme_stylebox_override("pressed", UIKit.flat(UIKit.C_ACCENT.darkened(0.2), 75))
	interact_btn.add_theme_stylebox_override("hover", UIKit.flat(UIKit.C_ACCENT.lightened(0.1), 75))
	interact_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(interact_btn)
	run_btn = UIKit.button("Correr", func() -> void: pass, UIKit.C_PANEL2, 90, 22)
	run_btn.toggle_mode = true
	run_btn.custom_minimum_size = Vector2(110, 90)
	run_btn.toggled.connect(func(on: bool) -> void: run_toggled.emit(on))
	add_child(run_btn)
	touch.exclusions.append(interact_btn)
	touch.exclusions.append(run_btn)
	_layout_buttons()
	get_viewport().size_changed.connect(_layout_buttons)
	Settings.changed.connect(func(k: String) -> void:
		if k == "swap_sides":
			_layout_buttons())
	set_focus_item({})


func _layout_buttons() -> void:
	var s := get_viewport_rect().size
	var swap := bool(Settings.get_value("swap_sides"))
	var ix := 40.0 if swap else s.x - 210.0
	interact_btn.position = Vector2(ix, s.y - 200.0)
	run_btn.position = Vector2(ix + (190.0 if swap else -130.0), s.y - 130.0)


func set_focus_item(item: Dictionary) -> void:
	if item.is_empty():
		interact_btn.visible = false
		hint_label.text = ""
		return
	interact_btn.visible = true
	interact_btn.text = "Usar\n" + str(item.get("label", ""))
	hint_label.text = "Toca «Usar» o pulsa E"


func set_ringing(on: bool, caller := "") -> void:
	ring_panel.visible = on
	if on:
		ring_label.text = "¡LLAMADA ENTRANTE! %s\nVe a tu mesa y contesta el teléfono" % caller


func set_controls_visible(on: bool) -> void:
	touch.enabled = on
	touch.visible = on
	if not on:
		touch.release_all()
	run_btn.visible = on
	if not on:
		interact_btn.visible = false


func toast(text: String, kind := "info") -> void:
	var col := UIKit.C_PANEL2
	match kind:
		"good", "achievement":
			col = Color("1e8449")
		"bad":
			col = Color("a93226")
		"boss":
			col = Color("6c3483")
		"event":
			col = Color("b9770e")
	var p := UIKit.panel(Color(col, 0.94), 14, 12)
	var l := UIKit.label(("Don Ramiro: " if kind == "boss" else "") + text, 21)
	l.custom_minimum_size = Vector2(430, 0)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_child(p)
	if kind in ["boss", "event", "achievement"]:
		Audio.play("notify", -4.0)
	while toast_box.get_child_count() > 4:
		toast_box.get_child(0).queue_free()
	var tw := create_tween()
	p.modulate.a = 0.0
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(5.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func refresh() -> void:
	top_day.text = "Día %d" % Game.day
	var q := Game.quota()
	var inc := int(Game.ledger.get("income", 0))
	quota_bar.max_value = q
	quota_bar.value = mini(inc, q)
	quota_label.text = "Cuota: %s / %s" % [UIKit.money(inc), UIKit.money(q)]
	quota_bar.add_theme_stylebox_override("fill", UIKit.flat(UIKit.C_GOOD if inc >= q else UIKit.C_ACCENT, 10, 0, Color.TRANSPARENT, 0))
	for c in obj_box.get_children():
		c.queue_free()
	obj_box.add_child(UIKit.label("Objetivos extra", 18, UIKit.C_MUTED))
	for o in Game.objectives:
		var done: bool = o["done"]
		var prog := "" if o["type"] == "no_hangups" else " (%d/%d)" % [mini(int(o["progress"]), int(o["target"])), int(o["target"])]
		obj_box.add_child(UIKit.label(("[OK] " if done else "[  ] ") + str(o["text"]) + prog, 18, UIKit.C_GOOD if done else UIKit.C_TEXT))


func _refresh_ai() -> void:
	match AI.status:
		"online":
			ai_pill.text = "IA remota: conectada"
			ai_pill.add_theme_color_override("font_color", UIKit.C_GOOD)
		"connecting":
			ai_pill.text = "IA remota: conectando…"
			ai_pill.add_theme_color_override("font_color", UIKit.C_ACCENT)
		"unconfigured":
			ai_pill.text = "Diálogo local\n(IA no configurada)"
			ai_pill.add_theme_color_override("font_color", UIKit.C_MUTED)
		_:
			ai_pill.text = "IA sin conexión:\ndiálogo local"
			ai_pill.add_theme_color_override("font_color", Color("ff9f43"))


func _refresh_event() -> void:
	if Game.active_event == "":
		event_label.text = ""
	else:
		event_label.text = "%s" % EventDB.EVENTS[Game.active_event]["name"]


func _process(delta: float) -> void:
	top_clock.text = Game.clock_text()
	end_btn.visible = Game.in_shift and Game.shift_left <= 0.0
	if Game.active_event != "" and float(EventDB.EVENTS[Game.active_event]["duration"]) > 0.0:
		event_label.text = "%s — %ds" % [EventDB.EVENTS[Game.active_event]["name"], int(ceil(Game.event_time_left))]
	if ring_panel.visible:
		_ring_t += delta
		ring_panel.modulate.a = 0.75 + 0.25 * sin(_ring_t * 8.0)
	if Input.is_key_pressed(KEY_E) and interact_btn.visible and not get_tree().paused:
		if not has_meta("e_held"):
			set_meta("e_held", true)
			interact_pressed.emit()
	elif has_meta("e_held"):
		remove_meta("e_held")
