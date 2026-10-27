class_name MainMenu
extends Control
## Menú principal sobre la oficina 3D animada de fondo.

signal start_day(day: int)
signal open_settings
signal open_customize
signal open_shop

var panel_box: VBoxContainer
var sub_layer: Control


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := ColorRect.new()
	grad.color = Color(0.05, 0.06, 0.1, 0.35)
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grad)
	var p := UIKit.panel(Color(0.1, 0.12, 0.19, 0.9), 26, 26)
	p.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	p.offset_left = 40
	p.offset_right = 520
	p.offset_top = 30
	p.offset_bottom = -30
	add_child(p)
	panel_box = UIKit.vbox(10)
	p.add_child(UIKit.scroll(panel_box))
	_build_main()


func _build_main() -> void:
	for c in panel_box.get_children():
		c.queue_free()
	var title := UIKit.label("TELETIMO 3D", 46, UIKit.C_ACCENT)
	panel_box.add_child(title)
	panel_box.add_child(UIKit.label("Call center del caos · clientes con IA en tu móvil", 18, UIKit.C_MUTED))
	var camp: Dictionary = Save.data["campaign"]
	var has := Save.has_progress()
	if has:
		var d := mini(int(camp["current_day"]), int(camp["max_day_unlocked"]))
		panel_box.add_child(UIKit.button("%s (Día %d)" % [Loc.t("continue"), d], func() -> void: start_day.emit(d), UIKit.C_GOOD, 76, 30))
	panel_box.add_child(UIKit.button(Loc.t("play"), _confirm_new, UIKit.C_ACCENT if not has else UIKit.C_PANEL2, 70, 26))
	panel_box.add_child(UIKit.button(Loc.t("days"), _show_days, UIKit.C_PANEL2, 64, 24))
	if Brain.available and not Brain.missing_packs().is_empty():
		var label := "Descargando IA… %d %%" % int(Brain.download_percent()) if Brain.downloading else "Activar IA de los clientes (%.1f GB, una vez)" % (Brain.missing_bytes() / 1073741824.0)
		var ai_btn := UIKit.button(label, func() -> void:
			var setup := AISetup.new()
			get_parent().add_child(setup)
			setup.open()
			setup.finished.connect(refresh), Color("8e44ad"), 64, 20)
		panel_box.add_child(ai_btn)
	var h := UIKit.hbox(10)
	var b1 := UIKit.button(Loc.t("customize"), func() -> void: open_customize.emit(), UIKit.C_PANEL2, 64, 22)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b2 := UIKit.button(Loc.t("upgrades"), func() -> void: open_shop.emit(), UIKit.C_PANEL2, 64, 22)
	b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(b1)
	h.add_child(b2)
	panel_box.add_child(h)
	var h2 := UIKit.hbox(10)
	var b3 := UIKit.button(Loc.t("stats"), _show_stats, UIKit.C_PANEL2, 64, 22)
	b3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b4 := UIKit.button(Loc.t("settings"), func() -> void: open_settings.emit(), UIKit.C_PANEL2, 64, 22)
	b4.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h2.add_child(b3)
	h2.add_child(b4)
	panel_box.add_child(h2)
	var h3 := UIKit.hbox(10)
	var b5 := UIKit.button(Loc.t("credits"), _show_credits, UIKit.C_PANEL2, 60, 22)
	b5.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h3.add_child(b5)
	if OS.get_name() != "Web":
		var b6 := UIKit.button(Loc.t("quit"), func() -> void: get_tree().quit(), UIKit.C_PANEL2, 60, 22)
		b6.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h3.add_child(b6)
	panel_box.add_child(h3)
	panel_box.add_child(UIKit.spacer(0, 0, true))
	var ai_txt := Brain.status_text()
	panel_box.add_child(UIKit.label("Saldo ficticio: %s · %s" % [UIKit.money(int(Save.data["money"])), ai_txt], 18, UIKit.C_MUTED))
	panel_box.add_child(UIKit.label("Todo es ficticio: clientes, ofertas, dinero y tarjetas.", 16, Color("ff9f9f")))


func refresh() -> void:
	_build_main()


func _confirm_new() -> void:
	if not Save.has_progress():
		Save.reset_game()
		start_day.emit(1)
		return
	var md := UIKit.modal(self, 700)
	var box: VBoxContainer = md["box"]
	box.add_child(UIKit.label(Loc.t("new_game_confirm"), 28))
	var h := UIKit.hbox(10)
	box.add_child(h)
	var y := UIKit.button(Loc.t("yes"), func() -> void:
		md["layer"].queue_free()
		Save.reset_game()
		start_day.emit(1), UIKit.C_BAD)
	y.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(y)
	var n := UIKit.button(Loc.t("no"), func() -> void: md["layer"].queue_free(), UIKit.C_PANEL2)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)


func _show_days() -> void:
	var md := UIKit.modal(self, 980, 600)
	var box: VBoxContainer = md["box"]
	box.add_child(UIKit.label("Selección de jornada", 30, UIKit.C_ACCENT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var camp: Dictionary = Save.data["campaign"]
	var max_d := int(camp["max_day_unlocked"])
	for d in range(1, maxi(CampaignDB.DAYS.size(), max_d) + 1):
		var info := CampaignDB.day_info(d)
		var grade := str(camp["day_grades"].get(str(d), ""))
		var txt := "Día %d%s\n%s\nCuota %s" % [d, ("  [" + grade + "]") if grade != "" else "", info["title"], UIKit.money(int(info["quota"]))]
		var b := UIKit.button(txt, func() -> void:
			md["layer"].queue_free()
			start_day.emit(d), UIKit.C_GOOD if camp["completed_days"].has(d) else UIKit.C_ACCENT, 120, 18)
		b.disabled = d > max_d
		b.custom_minimum_size = Vector2(290, 120)
		grid.add_child(b)
	box.add_child(UIKit.scroll(grid))
	box.add_child(UIKit.button(Loc.t("back"), func() -> void: md["layer"].queue_free(), UIKit.C_PANEL2))


func _show_stats() -> void:
	var md := UIKit.modal(self, 900, 600)
	var box: VBoxContainer = md["box"]
	var s: Dictionary = Save.data["stats"]
	box.add_child(UIKit.label(Loc.t("stats"), 30, UIKit.C_ACCENT))
	var calls := maxi(1, int(s["calls_made"]))
	var inner := UIKit.vbox(6)
	for r in [["Jornadas completadas", s["days_completed"]], ["Llamadas", s["calls_made"]], ["Transacciones ficticias", s["transactions"]],
			["Tasa de éxito", "%d %%" % int(100.0 * int(s["transactions"]) / calls)], ["Dinero ficticio acumulado", UIKit.money(int(s["money_total"]))],
			["Récord en un día", UIKit.money(int(s["record_day_income"]))], ["Clientes atendidos", s["clients_served"].size()],
			["Objetivos completados", s["objectives_completed"]], ["Mejor nota", s["best_grade"] if s["best_grade"] != "" else "-"],
			["Logros", "%d / %d" % [Save.data["achievements"].size(), AchievementDB.ACHIEVEMENTS.size()]]]:
		inner.add_child(UIKit.label("%s: %s" % [r[0], r[1]], 22))
	for id in Save.data["achievements"]:
		inner.add_child(UIKit.label("Logro: " + AchievementDB.ACHIEVEMENTS.get(id, {"name": id})["name"], 19, UIKit.C_GOOD))
	box.add_child(UIKit.scroll(inner))
	box.add_child(UIKit.button(Loc.t("back"), func() -> void: md["layer"].queue_free(), UIKit.C_PANEL2))


func _show_credits() -> void:
	var md := UIKit.modal(self, 900)
	var box: VBoxContainer = md["box"]
	box.add_child(UIKit.label("TeleTimo 3D", 34, UIKit.C_ACCENT))
	box.add_child(UIKit.label("Idea y dirección: julianfarks\nDesarrollo: julianfarks con Claude (Anthropic)\nMotor: Godot Engine 4.3 (licencia MIT)\nModelos, música y efectos: generados por código, originales.\n\nSátira de oficina. Personajes, empresas, productos, dinero y tarjetas son ficticios. No intentes nada de esto con personas reales: las estafas telefónicas causan daño de verdad.", 22))
	box.add_child(UIKit.button(Loc.t("back"), func() -> void: md["layer"].queue_free(), UIKit.C_PANEL2))
