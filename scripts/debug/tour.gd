extends Node
## Recorrido automático para capturas y pruebas de humo (solo con --tour=<carpeta>).
## Recorre: menú → oficina → llamada (con diálogo local) → venta → ordenador →
## personalización → evaluación del jefe. Guarda PNG en la carpeta indicada.

var out_dir := ""
var main: Node


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tour="):
			out_dir = a.substr(7)
	main = get_parent()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("captura: ", name)


func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	Save.path_override = "user://tour_save.json"
	Save.data = Save.default_data()
	Save.data["money"] = 2500
	Save.data["campaign"]["max_day_unlocked"] = 3
	Save.data["upgrades_owned"] = ["crm", "crm_pro", "monitor_doble", "frases", "risas", "planta", "lampara_lava", "trofeo"]
	await wait(3.0)
	await shot("01_menu")
	main._start_day(3)
	var office: OfficeController = main.office
	await wait(2.5)
	await shot("02_oficina")
	office.player.global_position = Vector3(-4.5, 0, 6.0)
	office.player.yaw = 2.6
	office.player.pitch = -0.55
	await wait(1.0)
	await shot("03_oficina_mesa")
	office.player.global_position = Vector3(3.0, 0, 1.0)
	office.player.yaw = -2.2
	office.player.pitch = -0.3
	await wait(1.2)
	await shot("04_jefe_y_descanso")
	# Llamada
	var lead: Dictionary = Game.leads[0].duplicate()
	lead["client_id"] = "estrella"
	lead["name"] = "Estrella del Drama"
	office._start_call(lead, true)
	await wait(1.5)
	await shot("05_elegir_oferta")
	office.call_screen.opening_idea = Persona.catalog_pitch("herencia_patatonia")
	office.call_screen._begin_call()
	await wait(1.5)
	var cs: CallScreen = office.call_screen
	for line in ["Hola, buenas tardes, me llamo Julián y le llamo de TeleTimo.", "Imagine: un príncipe de Patatonia le ha dejado una herencia increíble, ¡es su destino!", "Le entiendo, no se preocupe: le doy garantía de devolución por escrito."]:
		cs._say(line, false)
		await wait(1.2)
	await shot("06_llamada")
	cs.session.st.trust = 90
	cs.session.st.understanding = 85
	cs.session.st.suspicion = 5
	cs.session.st.offer_explained = true
	cs.session.st.pending_objections.clear()
	cs._ask_payment()
	await wait(1.0)
	await shot("07_venta_o_rechazo")
	await wait(4.5)
	await shot("08_resumen_llamada")
	if is_instance_valid(cs):
		cs.call_finished.emit({})
		cs.queue_free()
	office.call_screen = null
	office._close_overlay()
	await wait(0.5)
	office._open_computer("")
	await wait(1.0)
	await shot("09_ordenador")
	office.computer._open_app("shop")
	await wait(0.8)
	await shot("10_tienda")
	office.computer.queue_free()
	office._close_overlay()
	var cz := CustomizeScreen.new()
	main.ui.add_child(cz)
	cz.open()
	await wait(1.5)
	await shot("11_personalizar")
	cz.queue_free()
	Game.shift_left = 0.0
	await wait(3.5)
	await shot("12_evaluacion_jefe")
	print("TOUR OK")
	get_tree().quit()
