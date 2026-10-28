extends Node
## Prueba de resistencia (--soak): juega varias jornadas aceleradas contestando
## llamadas con frases variadas, fuerza todos los eventos y comprueba que el juego
## no se bloquea, que el dinero cuadra y que la memoria no crece sin control.

const LINES := [
	"Hola, buenas tardes, le llamo de TeleTimo.", "Le ofrezco algo increíble, es como un seguro pero divertido.",
	"Le entiendo perfectamente, no se preocupe.", "Cuesta 49 euros al mes.", "Le doy garantía de devolución por escrito.",
	"¿Usted tiene mascota?", "Jajaja, es broma.", "Hoy tiene un descuento especial: 39 euros.", "Sinceramente, le va a encantar.",
	"Tiene que pagar ya o se arrepentirá.", "asdf qwer", "Su vecino ya lo compró.",
]

var main: Node
var days := 3
var calls_done := 0
var errors := 0


func _ready() -> void:
	main = get_parent()
	Save.path_override = "user://soak_save.json"
	Save.data = Save.default_data()
	Settings.set_value("shift_minutes", 4, false)
	_run()


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	var start_mem := OS.get_static_memory_usage()
	var start_nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	Engine.time_scale = 6.0
	for d in days:
		var day: int = int(Save.data["campaign"]["current_day"])
		main._start_day(mini(day, int(Save.data["campaign"]["max_day_unlocked"])))
		var office: OfficeController = main.office
		await get_tree().create_timer(1.0).timeout
		# Fuerza los eventos uno a uno
		for ev in ["boss_inspection", "interruption", "pizza", "pc_crash", "special_opportunity", "phone_outage", "urgent_call", "hard_client", "weird_clarification"]:
			if Game.active_event == "":
				Game.start_event(ev)
			await get_tree().create_timer(1.5).timeout
		var guard := 0
		while Game.in_shift and Game.shift_left > 0.0 and guard < 4000:
			guard += 1
			if office.ringing:
				office._answer_ring()
				await _play_call(office)
			elif office.call_screen == null and office.overlay == null and randf() < 0.02:
				var lead: Dictionary = Game.next_incoming_lead()
				office._start_call(lead, false)
				await _play_call(office)
			await get_tree().process_frame
		# Espera la evaluación
		var w := 0
		while not office.day_over and w < 600:
			w += 1
			await get_tree().process_frame
		await get_tree().create_timer(3.0).timeout
		print("SOAK día %d: llamadas=%d ingresos=%d cuota=%d" % [Game.day, Game.ledger["calls"], Game.ledger["income"], Game.quota()])
		var sum := 0
		for r in Game.ledger["results"]:
			sum += int(r.get("final_amount", 0))
		if sum != int(Game.ledger["income"]):
			print("SOAK ERROR: el dinero no cuadra ", sum, " vs ", Game.ledger["income"])
			errors += 1
		office._after_results("next" if Game.ledger["income"] >= Game.quota() else "retry")
		await get_tree().create_timer(1.0).timeout
	Engine.time_scale = 1.0
	office_cleanup()
	await get_tree().create_timer(1.0).timeout
	var end_nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	print("SOAK nodos: inicio=%d fin=%d  memoria estática: %.1f → %.1f MB" % [start_nodes, end_nodes, start_mem / 1048576.0, OS.get_static_memory_usage() / 1048576.0])
	if end_nodes > start_nodes + 800:
		print("SOAK ERROR: posible fuga de nodos")
		errors += 1
	print("SOAK llamadas jugadas: %d, errores: %d" % [calls_done, errors])
	print("SOAK OK" if errors == 0 and calls_done > 0 else "SOAK FALLO")
	get_tree().quit(0 if errors == 0 and calls_done > 0 else 1)


func office_cleanup() -> void:
	main._to_menu()


func _play_call(office: OfficeController) -> void:
	var w := 0
	while office.call_screen == null and w < 30:
		w += 1
		await get_tree().process_frame
	var cs: CallScreen = office.call_screen
	if cs == null:
		return
	var offers := OfferDB.unlocked_for_day(Game.day)
	cs.opening_idea = Persona.catalog_pitch(offers[randi() % offers.size()])
	cs._begin_call()
	calls_done += 1
	for i in randi_range(3, 7):
		if not is_instance_valid(cs) or cs.session == null or not cs.session.active:
			break
		cs._say(LINES[randi() % LINES.size()], false)
		await get_tree().create_timer(0.3).timeout
	if is_instance_valid(cs) and cs.session and cs.session.active:
		if randf() < 0.7:
			cs._ask_payment()
		if is_instance_valid(cs) and cs.session and cs.session.active:
			cs.session.player_hangs_up()
	# Espera al resumen y pulsa «Siguiente»
	w = 0
	while is_instance_valid(cs) and not cs.summary_shown and w < 2000:
		w += 1
		await get_tree().process_frame
	if is_instance_valid(cs):
		if not cs.summary_shown:
			print("SOAK ERROR: la llamada no llegó al resumen")
			errors += 1
		cs.finish()
