class_name DayResults
extends Control
## Evaluación de fin de jornada: el jefe (en 3D, en su despacho) comenta los datos
## reales de la partida. Comentario con IA si está disponible; si no, local.

signal next_day
signal retry_day
signal to_menu
signal open_shop
signal boss_reaction(grade: String, comment: String)

var box: VBoxContainer
var btn_row: HBoxContainer
var comment_label: Label
var _typing := ""
var _typed := 0.0


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var p := UIKit.panel(Color(0.1, 0.12, 0.19, 0.94), 24, 22)
	p.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	p.offset_left = -640
	p.offset_right = -24
	p.offset_top = 24
	p.offset_bottom = -24
	add_child(p)
	var outer := UIKit.vbox(10)
	p.add_child(outer)
	box = UIKit.vbox(10)
	outer.add_child(UIKit.scroll(box))
	btn_row = UIKit.hbox(8)
	outer.add_child(btn_row)
	box.add_child(UIKit.label(Loc.t("day_results"), 34, UIKit.C_ACCENT))
	box.add_child(UIKit.label("Don Ramiro Billetes está revisando tus números…", 22, UIKit.C_MUTED))
	_evaluate()


func _evaluate() -> void:
	var stats := Game.day_stats_preview()
	var comment := ""
	if Brain.is_ready():
		comment = await Brain.boss_comment(stats)
	var rep := Game.end_day(comment)
	_show(rep, comment != "")


func _show(rep: Dictionary, from_ai: bool) -> void:
	for c in box.get_children():
		c.queue_free()
	box.add_child(UIKit.label("%s · Día %d" % [Loc.t("day_results"), rep["day"]], 30, UIKit.C_ACCENT))
	var h := UIKit.hbox(16)
	var grade := UIKit.label(rep["grade"], 96, UIKit.C_GOOD if rep["passed"] else UIKit.C_BAD)
	grade.custom_minimum_size = Vector2(120, 0)
	h.add_child(grade)
	var gv := UIKit.vbox(4)
	gv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gv.add_child(UIKit.label("CUOTA SUPERADA" if rep["passed"] else "CUOTA NO ALCANZADA", 26, UIKit.C_GOOD if rep["passed"] else UIKit.C_BAD))
	gv.add_child(UIKit.label("%s de %s" % [UIKit.money(rep["income"]), UIKit.money(rep["quota"])], 24))
	gv.add_child(UIKit.label("Llamadas: %d · Ventas: %d · Colgadas: %d" % [rep["calls"], rep["successes"], rep["hangups"]], 19, UIKit.C_MUTED))
	h.add_child(gv)
	box.add_child(h)
	var cp := UIKit.panel(Color("4a235a"), 16, 14)
	var cv := UIKit.vbox(4)
	cp.add_child(cv)
	cv.add_child(UIKit.label("Don Ramiro Billetes" + ("  (IA local)" if from_ai else "  (frase predefinida)"), 18, UIKit.C_MUTED))
	comment_label = UIKit.label("", 23, Color("f9e79f"))
	cv.add_child(comment_label)
	box.add_child(cp)
	_typing = "«%s»" % rep["comment"]
	_typed = 0.0
	boss_reaction.emit(rep["grade"], rep["comment"])
	box.add_child(UIKit.label("Ingresos ficticios: +%s" % UIKit.money(rep["income"]), 20))
	for o in rep["objectives"]:
		box.add_child(UIKit.label(("Objetivo cumplido: +%s · %s" % [UIKit.money(int(o["reward"])), o["text"]]) if o["done"] else ("Objetivo fallido: %s" % o["text"]), 19, UIKit.C_GOOD if o["done"] else UIKit.C_MUTED))
	if rep["day_bonus"] > 0:
		box.add_child(UIKit.label("Bonus por cumplir la cuota: +%s" % UIKit.money(rep["day_bonus"]), 20, UIKit.C_GOOD))
	if int(rep["bonuses"]) > 0:
		box.add_child(UIKit.label("Bonificaciones: +%s" % UIKit.money(rep["bonuses"]), 20, UIKit.C_GOOD))
	for e in rep["expenses"]:
		box.add_child(UIKit.label("%s: -%s" % [e["label"], UIKit.money(int(e["amount"]))], 19, Color("f1948a")))
	if int(rep["fines"]) > 0:
		box.add_child(UIKit.label("Multas: -%s" % UIKit.money(rep["fines"]), 19, Color("f1948a")))
	box.add_child(UIKit.label("Neto del día: %s   ·   Saldo: %s" % [UIKit.money(rep["net"]), UIKit.money(rep["money"])], 24, UIKit.C_ACCENT))
	if rep["fired"]:
		box.add_child(UIKit.label("¡TERCER AVISO! El jefe te despide… y te vuelve a contratar al minuto porque nadie más quiere el puesto. Repite la jornada.", 21, UIKit.C_BAD))
	elif not rep["passed"]:
		box.add_child(UIKit.label("Avisos: %d/3. Repite la jornada para seguir avanzando." % rep["strikes"], 21, UIKit.C_BAD))
	elif CampaignDB.is_campaign_end(rep["day"]):
		box.add_child(UIKit.label("¡CAMPAÑA COMPLETADA! Eres Empleado del Mes Eterno. Se desbloquea el modo infinito.", 24, UIKit.C_GOOD))
	var bh := btn_row
	if rep["passed"]:
		var nb := UIKit.button("Día %d" % (int(rep["day"]) + 1), func() -> void: next_day.emit(), UIKit.C_GOOD, 70, 24)
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bh.add_child(nb)
	else:
		var rb := UIKit.button(Loc.t("retry_day"), func() -> void: retry_day.emit(), UIKit.C_ACCENT, 70, 24)
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bh.add_child(rb)
	bh.add_child(UIKit.button(Loc.t("upgrades"), func() -> void: open_shop.emit(), UIKit.C_BLUE, 70, 22))
	bh.add_child(UIKit.button(Loc.t("main_menu"), func() -> void: to_menu.emit(), UIKit.C_PANEL2, 70, 22))
	Audio.play("applause" if rep["passed"] else "wahwah")


func _process(delta: float) -> void:
	if comment_label and _typed < _typing.length():
		_typed += delta * 45.0
		comment_label.text = _typing.substr(0, int(_typed))
