class_name OfficeController
extends Node3D
## Mundo de la oficina y bucle de la jornada: jugador, compañeros, jefe, llamadas
## entrantes, eventos, tablón, reloj y evaluación final. También sirve de fondo
## animado del menú principal.

signal day_finished
signal request_pause
signal overlay_opened(node: Control)

const COWORKER_LINES := [
	"¿Alguien ha visto mi grapadora?", "Hoy vendo hasta la planta de plástico.", "Mi cliente me ha llamado 'majo'. Progreso.",
	"El café de la máquina sabe a lunes.", "¡Venta! Ah no, se colgó.", "¿Esto cuenta como horas extra?",
	"Le he vendido un crucero a un pirata.", "El jefe dice que sonría con la voz…", "Me han colgado tres veces seguidas. Récord.",
]
const COWORKERS := [
	{"name": "Rigo (Contabilidad)", "look": {"skin": "d9a37e", "body": "wide", "hair": "short", "hair_color": "1a1a1a", "shirt": "e9c46a", "pants": "3a3a3a", "acc": ["glasses", "tie"]}},
	{"name": "Vane", "look": {"skin": "f1c7a3", "body": "thin", "hair": "ponytail", "hair_color": "b5532a", "shirt": "2a9d8f", "pants": "264653", "acc": ["headphones"]}},
	{"name": "Toño", "look": {"skin": "b9825c", "body": "tall", "hair": "afro", "hair_color": "1a1410", "shirt": "e76f51", "pants": "2f3e46", "acc": ["headphones"]}},
	{"name": "Lupe", "look": {"skin": "e8b894", "body": "short", "hair": "bob", "hair_color": "2b1d14", "shirt": "8338ec", "pants": "3a2a4a", "acc": ["headphones", "earrings"]}},
	{"name": "Becario Kevin", "look": {"skin": "f3d2b5", "body": "thin", "hair": "messy", "hair_color": "e0c070", "shirt": "a8dadc", "pants": "457b9d", "acc": ["cap"]}},
	{"name": "Marisol", "look": {"skin": "c48a64", "body": "avg", "hair": "long", "hair_color": "1a0a0a", "shirt": "ff006e", "pants": "1d3557", "acc": ["headphones"]}},
	{"name": "Don Tito", "look": {"skin": "ecc5a5", "body": "wide", "hair": "bald", "hair_color": "aaaaaa", "shirt": "6b705c", "pants": "3a3a2a", "acc": ["mustache", "headphones"]}},
]
const BOSS_LOOK := {"skin": "f0c8a0", "body": "wide", "hair": "slick", "hair_color": "2a1a10", "shirt": "1e1e24", "pants": "15151a", "acc": ["tie_gold", "mustache", "sunglasses"]}

var builder: OfficeBuilder
var refs: Dictionary
var player: Player
var boss: NPC
var coworkers: Array = []
var hud: HUD
var ui_layer: CanvasLayer
var mode := "menu"
var menu_cam: Camera3D
var _menu_t := 0.0
var rng := RandomNumberGenerator.new()

var ringing := false
var ring_lead: Dictionary = {}
var ring_time_left := 0.0
var next_ring_in := 15.0
var ring_vip := false
var overlay: Control
var call_screen: CallScreen
var computer: ComputerScreen
var day_over := false
var _board_t := 0.0
var _fps_acc := 0.0
var _fps_frames := 0
var _fps_low_time := 0.0
var _coffee_cd := 0.0
var _idle_time := 0.0
var _inspection_phase := ""
var _rigo_phase := ""
var deco_root: Node3D
var sun: DirectionalLight3D


func _ready() -> void:
	rng.randomize()
	builder = OfficeBuilder.new()
	refs = builder.build(self, int(Settings.get_value("quality")))
	for c in get_node("Office").get_children():
		if c is DirectionalLight3D:
			sun = c
	_spawn_npcs()
	menu_cam = Camera3D.new()
	add_child(menu_cam)
	menu_cam.current = true
	Settings.graphics_changed.connect(_apply_runtime_quality)
	Game.event_started.connect(_on_event_started)
	Game.event_ended.connect(_on_event_ended)
	_place_deco()


func _spawn_npcs() -> void:
	var seats: Array = refs["coworker_seats"]
	var count := mini(Settings.ambient_npc_count(), seats.size())
	for i in count:
		var n := NPC.new()
		add_child(n)
		var cw: Dictionary = COWORKERS[i % COWORKERS.size()]
		n.setup(cw["look"], cw["name"], COWORKER_LINES, 100 + i)
		var seat: Dictionary = seats[i]
		n.sit_at(seat["pos"], seat["rot"])
		n.model.state = "sit"
		coworkers.append(n)
	boss = NPC.new()
	add_child(boss)
	boss.setup(BOSS_LOOK, BossLines.BOSS_NAME, [], 999)
	boss.speed = 1.4
	boss.global_position = Vector3(9.5, 0, -5.4)
	boss.model.rotation.y = 0.0


func _place_deco() -> void:
	if deco_root:
		deco_root.queue_free()
	deco_root = Node3D.new()
	add_child(deco_root)
	var slots: Array = refs.get("deco_slots", [])
	var owned: Array = Save.data["upgrades_owned"]
	var i := 0
	for id in ["planta", "lampara_lava", "poster", "pecera", "trofeo"]:
		if not owned.has(id) or i >= slots.size():
			continue
		var p: Vector3 = slots[i]
		i += 1
		match id:
			"planta":
				builder.mesh_at(deco_root, CharacterModel.cylinder(0.07, 0.05, 0.12), p + Vector3(0, 0.06, 0), CharacterModel.mat("b5651d"))
				builder.mesh_at(deco_root, CharacterModel.sphere(0.1), p + Vector3(0, 0.2, 0), CharacterModel.mat("43a047"))
			"lampara_lava":
				builder.mesh_at(deco_root, CharacterModel.cylinder(0.04, 0.07, 0.28), p + Vector3(0, 0.14, 0), OfficeBuilder.emissive("ff4d6d", 2.0))
			"poster":
				builder.box_at(deco_root, Vector3(0.4, 0.3, 0.01), p, CharacterModel.mat("ffd166"))
				builder.label3d(deco_root, "VENDE\nHUMO", p + Vector3(0, 0, 0.01), 24, Color("1b1b22"), 0.0, 0)
			"pecera":
				var glass := StandardMaterial3D.new()
				glass.albedo_color = Color(0.4, 0.7, 1.0, 0.45)
				glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				builder.box_at(deco_root, Vector3(0.3, 0.2, 0.18), p + Vector3(0, 0.1, 0), glass)
				builder.mesh_at(deco_root, CharacterModel.sphere(0.03), p + Vector3(0, 0.1, 0), CharacterModel.mat("ff9f1c"), Vector3(1.6, 1, 0.6))
			"trofeo":
				builder.mesh_at(deco_root, CharacterModel.cylinder(0.06, 0.03, 0.18), p + Vector3(0, 0.15, 0), CharacterModel.mat("e0b030", 0.3, 0.8))
				builder.box_at(deco_root, Vector3(0.1, 0.05, 0.1), p + Vector3(0, 0.03, 0), CharacterModel.mat("4a2e1a"))


func set_ui_layer(layer: CanvasLayer) -> void:
	ui_layer = layer


# ------------------------------------------------------------------ Modos

func enter_menu() -> void:
	mode = "menu"
	day_over = false
	_stop_ring()
	if player:
		player.queue_free()
		player = null
	if hud:
		hud.queue_free()
		hud = null
	menu_cam.current = true
	Audio.set_ambient(true)
	Audio.play_music("menu")
	boss.go([Vector3(9.5, 0, -5.4)])
	_place_deco()


func start_day(d: int) -> void:
	mode = "play"
	day_over = false
	Game.start_day(d)
	_place_deco()
	if player == null:
		player = Player.new()
		add_child(player)
		player.setup(CustomizeScreen.player_look())
	else:
		player.rebuild_look(CustomizeScreen.player_look())
	player.global_position = refs["player_spawn"]
	player.yaw = PI * 0.95
	player.frozen = false
	player.interactables = refs["interactables"]
	player.speed_mult = float(Game.mods().get("move_speed_mult", 1.0))
	player.camera.current = true
	for n in coworkers:
		n.player = player
	boss.player = player
	if hud:
		hud.queue_free()
	hud = HUD.new()
	ui_layer.add_child(hud)
	hud.interact_pressed.connect(_on_interact)
	hud.pause_pressed.connect(func() -> void: request_pause.emit())
	hud.run_toggled.connect(func(on: bool) -> void: player.running = on)
	hud.end_day_pressed.connect(_finish_day)
	hud.touch.move.connect(func(v: Vector2) -> void: player.move_input = v)
	hud.touch.look.connect(func(v: Vector2) -> void: player.look_delta += v)
	player.focus_changed.connect(func(it: Dictionary) -> void: hud.set_focus_item(it))
	next_ring_in = rng.randf_range(10.0, 18.0)
	_idle_time = 0.0
	_inspection_phase = ""
	_rigo_phase = ""
	_set_pizza(false)
	Audio.set_ambient(true)
	Audio.play_music("office")
	# El jefe sale a dar la bienvenida
	boss.global_position = Vector3(9.5, 0, -5.4)
	boss.go([refs["waypoints"]["boss_door"], refs["waypoints"]["aisle_w"] + Vector3(1.5, 0, 0)])
	boss.say(CampaignDB.day_info(d)["boss"], 7.0)
	get_tree().create_timer(9.0).timeout.connect(func() -> void:
		if mode == "play" and _inspection_phase == "":
			boss.go([refs["waypoints"]["boss_door"], refs["waypoints"]["boss_desk"]]))
	Game.notify.emit(CampaignDB.day_info(d)["boss"], "boss")
	Game.notify.emit("Cuota de hoy: %s. Contesta el teléfono de tu mesa o llama desde el ordenador." % UIKit.money(Game.quota()), "info")


# ------------------------------------------------------------------ Interacción

func _on_interact() -> void:
	if player == null or overlay != null or day_over:
		return
	var it := player.focus
	if it.is_empty():
		return
	Audio.play("click")
	_idle_time = 0.0
	match str(it["kind"]):
		"phone":
			if ringing:
				_answer_ring()
			else:
				_open_computer("phone")
		"computer":
			_open_computer("")
		"board":
			_show_board()
		"boss_desk":
			boss.say(_pick(["¿Qué haces en mi despacho? ¡A vender!", "Si vienes a pedir aumento, la respuesta es una risa.", "Mi sillón cuesta más que tu sueldo imaginario."]), 4.0)
		"coffee":
			if _coffee_cd > 0.0:
				Game.notify.emit("Otro café y empezarás a vender en morse. Espera un poco.", "info")
			else:
				_coffee_cd = 90.0
				Game.buffs["pizza"] = maxf(float(Game.buffs["pizza"]), 6.0)
				Audio.play("pickup")
				Game.notify.emit("Café de máquina: +6 de paciencia del cliente en tu próxima llamada (tu calma se contagia).", "good")
		"pizza":
			if Game.is_event("pizza"):
				Game.buffs["pizza"] = 15.0
				_set_pizza(false)
				Game.end_event()
				Audio.play("coin")
				Game.notify.emit("¡Pizza! +15 de paciencia inicial en la próxima llamada.", "good")
		"cooler":
			Game.notify.emit(_pick(["Rumor del dispensador: dicen que Don Ramiro tiene miedo a las palomas.", "Bebes agua. Hidratación: 100 %. Ventas: igual.", "Alguien ha escrito 'socorro' en el vaso de plástico."]), "info")
		"plant":
			Game.notify.emit("La planta de plástico cree en ti. Es la única.", "info")
		"printer":
			Audio.play("type", 0.0, 0.0, 0.0)
			Game.notify.emit("La fotocopiadora imprime: «Certificado de vendedor honrado». Ironía nivel experto.", "info")


func _pick(arr: Array) -> String:
	return str(arr[rng.randi() % arr.size()])


func _show_board() -> void:
	var md := UIKit.modal(ui_layer, 820)
	_set_overlay(md["layer"])
	var box: VBoxContainer = md["box"]
	box.add_child(UIKit.label("Tablón de objetivos · Día %d" % Game.day, 30, UIKit.C_ACCENT))
	box.add_child(UIKit.label(CampaignDB.day_info(Game.day)["title"], 22, UIKit.C_MUTED))
	box.add_child(UIKit.label("Cuota: %s / %s" % [UIKit.money(int(Game.ledger["income"])), UIKit.money(Game.quota())], 24))
	for o in Game.objectives:
		box.add_child(UIKit.label(("[X] " if o["done"] else "[  ] ") + str(o["text"]), 22, UIKit.C_GOOD if o["done"] else UIKit.C_TEXT))
	box.add_child(UIKit.label("Ranking de la oficina (inventado): 1. Rigo · 2. Vane · 3. Tú (si te esfuerzas)", 19, UIKit.C_MUTED))
	box.add_child(UIKit.button(Loc.t("close"), func() -> void: _close_overlay()))


func _set_overlay(c: Control) -> void:
	overlay = c
	if hud:
		hud.set_controls_visible(false)
	if player:
		player.frozen = true
	overlay_opened.emit(c)


func _close_overlay() -> void:
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null
	if hud and not day_over:
		hud.set_controls_visible(true)
		hud.refresh()
	if player and not day_over:
		player.frozen = false


func _open_computer(app: String) -> void:
	computer = ComputerScreen.new()
	ui_layer.add_child(computer)
	computer.open()
	_set_overlay(computer)
	computer.request_call.connect(func(lead: Dictionary) -> void:
		overlay = null
		_start_call(lead, false))
	computer.closed.connect(func() -> void:
		overlay = null
		_close_overlay())
	computer.open_settings.connect(func() -> void:
		var s := SettingsMenu.new()
		ui_layer.add_child(s)
		s.open())
	if app == "phone":
		computer._open_app("phone")


# ------------------------------------------------------------------ Llamadas

func _answer_ring() -> void:
	var lead := ring_lead
	var vip := ring_vip
	_stop_ring()
	if vip:
		Game.buffs["vip_mult"] = 1.5
	_start_call(lead, true)


func _start_call(lead: Dictionary, incoming: bool) -> void:
	if lead.is_empty():
		return
	_stop_ring()
	call_screen = CallScreen.new()
	ui_layer.add_child(call_screen)
	_set_overlay(call_screen)
	var flags := Game.call_flags_for(lead)
	call_screen.open(lead, flags)
	if player:
		player.model.state = "phone"
		player.model.set_phone(true)
	call_screen.call_finished.connect(func(_r: Dictionary) -> void:
		call_screen = null
		if player:
			player.model.state = "idle"
			player.model.set_phone(false)
		_close_overlay()
		next_ring_in = rng.randf_range(20.0, 40.0)
		if hud:
			hud.refresh())


func _start_ring(vip := false) -> void:
	if ringing or Game.on_call or day_over:
		return
	ring_lead = Game.next_incoming_lead()
	ring_vip = vip
	ringing = true
	ring_time_left = 20.0 if vip else 18.0
	if hud:
		hud.set_ringing(true, ("[VIP] " if vip else "") + str(ring_lead.get("name", "")))
	Audio.play("ring", 0.0, 0.0, 0.0)


func _stop_ring() -> void:
	ringing = false
	ring_vip = false
	Audio.stop("ring")
	if hud:
		hud.set_ringing(false)


# ------------------------------------------------------------------ Eventos

func _on_event_started(id: String) -> void:
	if mode != "play":
		return
	match id:
		"urgent_call":
			_stop_ring()
			_start_ring(true)
		"boss_inspection":
			_inspection_phase = "going"
			boss.go([refs["waypoints"]["boss_door"], refs["waypoints"]["aisle_w"], refs["waypoints"]["player_desk"] + Vector3(1.6, 0, 0.6)])
			boss.say("Voy a ver qué hace el novato…", 3.0)
		"interruption":
			if not coworkers.is_empty():
				var rigo: NPC = coworkers[0]
				_rigo_phase = "going"
				rigo.go([rigo.global_position + Vector3(0.0, 0, 0.6), Vector3(rigo.global_position.x, 0, 0.3), refs["waypoints"]["aisle_w"], refs["waypoints"]["player_desk"] + Vector3(1.0, 0, 1.4)])
		"pizza":
			_set_pizza(true)
		"phone_outage":
			_stop_ring()
			if Game.on_call and call_screen and call_screen.session and call_screen.session.active and rng.randf() < 0.5:
				call_screen._system_line("¡La centralita se ha caído!")
				call_screen.session.interrupt("tech_fail")


func _on_event_ended(id: String) -> void:
	match id:
		"interruption":
			if not coworkers.is_empty():
				var rigo: NPC = coworkers[0]
				_rigo_phase = "back"
				rigo.say("Bueno, te dejo trabajar. ¡Luego te cuento lo de mi tortuga!", 3.0)
				var seat: Vector3 = rigo.seat_pos
				rigo.go([refs["waypoints"]["aisle_w"], Vector3(seat.x, 0, 0.3), seat])
				rigo.arrived.connect(func() -> void:
					if _rigo_phase == "back":
						rigo.sit_at(rigo.seat_pos, rigo.seat_rot)
						_rigo_phase = "", CONNECT_ONE_SHOT)
		"pizza":
			_set_pizza(false)
		"boss_inspection":
			if _inspection_phase != "":
				_inspection_phase = ""
				boss.go([refs["waypoints"]["aisle_w"], refs["waypoints"]["boss_door"], refs["waypoints"]["boss_desk"]])


func _set_pizza(on: bool) -> void:
	for m in refs.get("pizza_meshes", []):
		m.visible = on
	for it in refs["interactables"]:
		if it["kind"] == "pizza":
			it["disabled"] = not on
	if on and not refs["interactables"].any(func(it): return it["kind"] == "pizza"):
		builder.add_interactable(refs["pizza_node"], "pizza", "Pizza gratis", 1.5)


# ------------------------------------------------------------------ Bucle

func _process(delta: float) -> void:
	if mode == "menu":
		_menu_t += delta
		var a := _menu_t * 0.08
		menu_cam.global_position = Vector3(cos(a) * 9.0 - 1.0, 4.6, sin(a) * 6.0 + 1.0)
		menu_cam.look_at(Vector3(-1.0, 0.8, 0.0))
		return
	if player == null:
		return
	_coffee_cd = maxf(0.0, _coffee_cd - delta)
	_update_board(delta)
	_auto_quality(delta)
	if day_over:
		return
	# Llamadas entrantes
	if ringing:
		ring_time_left -= delta
		if ring_time_left <= 0.0:
			_stop_ring()
			Game.register_missed_call()
			next_ring_in = rng.randf_range(25.0, 45.0)
		elif not Audio.is_playing("ring"):
			Audio.play("ring", 0.0, 0.0, 0.0)
	elif not Game.on_call and overlay == null or (overlay == computer and computer != null):
		if not Game.is_event("phone_outage") and Game.shift_left > 15.0:
			next_ring_in -= delta
			if next_ring_in <= 0.0:
				_start_ring(false)
	# Jefe: inspección
	if _inspection_phase == "going" and boss.path.is_empty():
		_inspection_phase = "judging"
		var working := Game.on_call or (overlay != null and overlay == computer)
		if working:
			boss.say(BossLines.remark("inspection_good", rng), 4.0)
			Game.add_bonus(10, "El jefe te vio trabajando")
			boss.model.play_gesture("nod")
		else:
			boss.say(BossLines.remark("inspection_bad", rng), 4.0)
			Game.add_fine(15, "El jefe te pilló sin trabajar")
			boss.model.set_emotion("angry")
			boss.model.play_gesture("point")
		get_tree().create_timer(4.5).timeout.connect(func() -> void:
			boss.model.set_emotion("neutral")
			if Game.is_event("boss_inspection"):
				Game.end_event())
	# Rigo interrumpiendo
	if _rigo_phase == "going" and not coworkers.is_empty() and coworkers[0].path.is_empty():
		_rigo_phase = "talking"
		coworkers[0].say("¡Ey! ¿Sabes qué hice el finde? Le enseñé a mi tortuga a ladrar…", 5.0)
	# El jefe te recuerda que trabajes si llevas mucho rato sin hacer nada
	if overlay == null and not Game.on_call and player.velocity.length() < 0.1:
		_idle_time += delta
		if _idle_time > 45.0:
			_idle_time = 0.0
			Game.notify.emit(BossLines.remark("idle", rng), "boss")
	# Fin de la jornada
	if Game.in_shift and Game.shift_left <= 0.0 and not Game.on_call and call_screen == null:
		_finish_day()


func _update_board(delta: float) -> void:
	_board_t -= delta
	if _board_t > 0.0:
		return
	_board_t = 1.0
	if refs.has("clock_label"):
		refs["clock_label"].text = Game.clock_text()
	if refs.has("board_label"):
		var txt := "OBJETIVO DEL DÍA %d\n%s / %s\n" % [Game.day, UIKit.money(int(Game.ledger.get("income", 0))), UIKit.money(Game.quota())]
		for o in Game.objectives:
			txt += ("[x] " if o["done"] else "[ ] ") + str(o["text"]) + "\n"
		refs["board_label"].text = txt
	if refs.has("player_screen_label"):
		refs["player_screen_label"].text = "¡RIIING!" if ringing else ("EN LLAMADA" if Game.on_call else "TimoOS\n%d leads" % Game.leads.filter(func(l): return not l["called"]).size())
	for s in refs["monitors"]:
		if rng.randf() < 0.15:
			var mt := (s as MeshInstance3D).material_override as StandardMaterial3D
			mt.emission_energy_multiplier = rng.randf_range(0.8, 1.6)


func _finish_day() -> void:
	if day_over:
		return
	day_over = true
	_stop_ring()
	if overlay and is_instance_valid(overlay) and overlay != call_screen:
		overlay.queue_free()
		overlay = null
	if hud:
		hud.set_controls_visible(false)
	player.frozen = true
	Audio.play("ding")
	# Cámara al despacho del jefe
	boss.path.clear()
	boss.global_position = Vector3(9.0, 0, -5.3)
	if hud:
		hud.visible = false
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(9.9, 1.65, -2.6)
	cam.look_at(Vector3(10.05, 1.35, -5.3))
	var to_cam := cam.global_position - boss.global_position
	boss.model.rotation.y = atan2(to_cam.x, to_cam.z)
	cam.current = true
	set_meta("eval_cam", cam)
	var dr := DayResults.new()
	ui_layer.add_child(dr)
	overlay = dr
	dr.boss_reaction.connect(func(grade: String, comment: String) -> void:
		var e: String = {"S": "joy", "A": "happy", "B": "neutral", "C": "distrust", "D": "angry", "F": "angry"}.get(grade, "neutral")
		boss.model.set_emotion(e)
		boss.model.play_gesture("laugh" if grade in ["S", "A"] else ("angry" if grade in ["D", "F"] else "think"))
		boss.talk_for(minf(12.0, 1.0 + comment.length() / 15.0))
		if not Game.on_call:
			Voice.speak(comment, {"id": "boss", "gender": "m", "pitch": 0.75, "rate": 1.05, "remote_voice": "onyx", "instructions": "Jefe sarcástico y exagerado de una oficina cómica."}))
	dr.next_day.connect(func() -> void: _after_results("next"))
	dr.retry_day.connect(func() -> void: _after_results("retry"))
	dr.to_menu.connect(func() -> void: _after_results("menu"))
	dr.open_shop.connect(func() -> void: _open_computer_shop())
	dr.open()


func _open_computer_shop() -> void:
	var c := ComputerScreen.new()
	ui_layer.add_child(c)
	c.open()
	c._open_app("shop")


func _after_results(what: String) -> void:
	Voice.stop_speaking()
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null
	if has_meta("eval_cam"):
		(get_meta("eval_cam") as Camera3D).queue_free()
		remove_meta("eval_cam")
	boss.model.set_emotion("neutral")
	match what:
		"next":
			start_day(int(Save.data["campaign"]["current_day"]))
		"retry":
			start_day(Game.day)
		"menu":
			day_finished.emit()


func abandon_day() -> void:
	Game.in_shift = false
	_stop_ring()
	if call_screen and is_instance_valid(call_screen):
		call_screen.queue_free()
	call_screen = null
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null
	Game.on_call = false


func _auto_quality(delta: float) -> void:
	if not Settings.get_value("auto_quality"):
		return
	_fps_acc += delta
	_fps_frames += 1
	if _fps_acc >= 4.0:
		var fps := _fps_frames / _fps_acc
		_fps_acc = 0.0
		_fps_frames = 0
		var target := float(Settings.get_value("fps_limit"))
		if fps < target * 0.7:
			_fps_low_time += 4.0
		else:
			_fps_low_time = 0.0
		if _fps_low_time >= 12.0 and int(Settings.get_value("quality")) > 0:
			_fps_low_time = 0.0
			Settings.set_value("quality", int(Settings.get_value("quality")) - 1)
			Game.notify.emit("Rendimiento bajo: calidad gráfica reducida automáticamente.", "info")


func _apply_runtime_quality() -> void:
	var q := int(Settings.get_value("quality"))
	if sun:
		sun.shadow_enabled = q >= 1
	var keep := Settings.ambient_npc_count()
	for i in coworkers.size():
		coworkers[i].visible = i < keep
