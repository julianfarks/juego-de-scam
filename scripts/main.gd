extends Node
## Punto de entrada: crea la oficina 3D y gestiona los estados (menú, jornada,
## pausa) y el botón «Atrás» de Android.

var office: OfficeController
var ui: CanvasLayer
var menu: MainMenu
var pause_layer: Control
var _splash: Control


func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	get_tree().set_auto_accept_quit(false)
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	_show_splash()
	await get_tree().process_frame
	await get_tree().process_frame
	office = OfficeController.new()
	add_child(office)
	office.set_ui_layer(ui)
	office.request_pause.connect(_pause)
	office.day_finished.connect(_to_menu)
	if _splash:
		var tw := create_tween()
		tw.tween_property(_splash, "modulate:a", 0.0, 0.6)
		tw.tween_callback(_splash.queue_free)
	_to_menu()
	# IA local: si los modelos ya están, se cargan en segundo plano; si no, se ofrece
	# descargarlos (una sola vez) en el primer inicio.
	if Brain.available and OS.get_cmdline_user_args().is_empty():
		if Brain.missing_packs().is_empty():
			Brain.load_all()
		elif not bool(Settings.get_value("ai_setup_seen")):
			var setup := AISetup.new()
			ui.add_child(setup)
			setup.open()
			setup.finished.connect(func() -> void:
				if menu:
					menu.refresh())
	# Modo de capturas/pruebas: --demo-day arranca directamente una jornada
	if "--demo-day" in OS.get_cmdline_user_args():
		_start_day(1)
	for a in OS.get_cmdline_user_args():
		if a == "--soak":
			add_child(load("res://scripts/debug/soak.gd").new())
		if a.begins_with("--tour="):
			var tour: Node = load("res://scripts/debug/tour.gd").new()
			add_child(tour)


func _show_splash() -> void:
	_splash = Control.new()
	_splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_splash.theme = UIKit.theme()
	var bg := ColorRect.new()
	bg.color = Color("1d2333")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_splash.add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_splash.add_child(c)
	var v := UIKit.vbox(10)
	c.add_child(v)
	v.add_child(UIKit.label("TELETIMO 3D", 64, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label("Montando la oficina…", 26, UIKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	ui.add_child(_splash)


func _to_menu() -> void:
	get_tree().paused = false
	if pause_layer:
		pause_layer.queue_free()
		pause_layer = null
	office.enter_menu()
	if menu:
		menu.queue_free()
	menu = MainMenu.new()
	ui.add_child(menu)
	menu.open()
	menu.start_day.connect(_start_day)
	menu.open_settings.connect(func() -> void: _open_settings(menu))
	menu.open_customize.connect(func() -> void:
		var c := CustomizeScreen.new()
		ui.add_child(c)
		c.open()
		c.closed.connect(menu.refresh))
	menu.open_shop.connect(func() -> void:
		var cs := ComputerScreen.new()
		ui.add_child(cs)
		cs.open()
		cs._open_app("shop")
		cs.closed.connect(menu.refresh))


func _start_day(d: int) -> void:
	if menu:
		menu.queue_free()
		menu = null
	office.start_day(d)


func _open_settings(after: Node = null) -> void:
	var s := SettingsMenu.new()
	ui.add_child(s)
	s.open()
	if after and after.has_method("refresh"):
		s.closed.connect(after.refresh)


func _pause() -> void:
	if pause_layer or office.mode != "play":
		return
	get_tree().paused = true
	Voice.stop_speaking()
	var md := UIKit.modal(ui, 640)
	pause_layer = md["layer"]
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var box: VBoxContainer = md["box"]
	box.add_child(UIKit.label(Loc.t("pause"), 36, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UIKit.label("Día %d · %s · %s de %s" % [Game.day, Game.clock_text(), UIKit.money(int(Game.ledger.get("income", 0))), UIKit.money(Game.quota())], 22, UIKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UIKit.button(Loc.t("resume"), _resume, UIKit.C_GOOD))
	box.add_child(UIKit.button(Loc.t("settings"), func() -> void: _open_settings(), UIKit.C_PANEL2))
	box.add_child(UIKit.button(Loc.t("retry_day"), func() -> void:
		_resume()
		office.abandon_day()
		office.start_day(Game.day), UIKit.C_PANEL2))
	box.add_child(UIKit.button("Abandonar jornada (menú)", func() -> void:
		office.abandon_day()
		_to_menu(), UIKit.C_BAD))
	box.add_child(UIKit.label("Si abandonas, el progreso de esta jornada se pierde (lo comprado y lo ganado en días anteriores se conserva).", 18, UIKit.C_MUTED))


func _resume() -> void:
	get_tree().paused = false
	if pause_layer:
		pause_layer.queue_free()
		pause_layer = null


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if pause_layer:
				_resume()
			elif office and office.mode == "play":
				if office.overlay == null:
					_pause()
			elif menu:
				get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			Save.save_game()
			if office and office.mode == "play" and not Game.on_call:
				_pause()
		NOTIFICATION_WM_CLOSE_REQUEST:
			Save.save_game()
			get_tree().quit()
