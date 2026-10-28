class_name ComputerScreen
extends Control
## Escritorio ficticio «TimoOS 98» con aplicaciones que afectan a la partida:
## lista de llamadas, CRM, calendario, estadísticas, objetivos, transacciones,
## tienda de mejoras, correo, evaluaciones, herramientas cómicas y ajustes.

signal request_call(lead: Dictionary)
signal open_settings
signal closed

const APPS := [
	["phone", "Teléfono", "1d8348"], ["crm", "Clientes", "2e86c1"], ["calendar", "Calendario", "a04000"],
	["stats", "Estadísticas", "7d3c98"], ["goals", "Objetivos", "b7950b"], ["tx", "Transacciones", "117a65"],
	["shop", "Mejoras", "c0392b"], ["mail", "Correo", "2874a6"], ["evals", "Evaluaciones", "6c3483"],
	["tools", "Herramientas", "d35400"], ["settings", "Ajustes", "566573"],
]

const EXCUSES := [
	"«Disculpe, se me cortó porque pasó un camión de silencio.»",
	"«No es una estafa, es un regalo con factura.»",
	"«Mi jefe me obliga a ser amable, no lo tome personal.»",
	"«Esta llamada se graba para mejorar mi autoestima.»",
	"«Le llamo desde el futuro: usted ya lo compró.»",
	"«Si cuelga ahora, un gatito llora en Patatonia.»",
	"«No vendo nada, comparto oportunidades con precio.»",
]

var content: VBoxContainer
var title_label: Label
var crash_layer: Control
var crash_progress := 0.0
var rng := RandomNumberGenerator.new()


func open() -> void:
	rng.randomize()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color("0b6e6e")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color("0f8b8d"))
	g.set_color(1, Color("143642"))
	gt.gradient = g
	gt.fill_to = Vector2(1, 1)
	grad.texture = gt
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(grad)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var v := UIKit.vbox(10)
	margin.add_child(v)
	var top := UIKit.panel(Color(0.05, 0.1, 0.15, 0.85), 12, 10)
	top.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var th := UIKit.hbox(10)
	top.add_child(th)
	title_label = UIKit.label("TimoOS 98", 26, UIKit.C_ACCENT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(title_label)
	th.add_child(UIKit.label("Saldo: %s" % UIKit.money(int(Save.data["money"])), 22))
	th.add_child(UIKit.button("Escritorio", _show_desktop, UIKit.C_PANEL2, 54, 20))
	th.add_child(UIKit.button("Apagar", func() -> void:
		closed.emit()
		queue_free(), UIKit.C_BAD, 54, 20))
	v.add_child(top)
	content = UIKit.vbox(10)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(content)
	Audio.play("ding", -8.0)
	_show_desktop()
	if Game.is_event("pc_crash"):
		_show_crash()
	Game.event_started.connect(_on_event)


func _on_event(id: String) -> void:
	if id == "pc_crash" and is_inside_tree():
		_show_crash()


func _clear() -> void:
	for c in content.get_children():
		c.queue_free()


func _show_desktop() -> void:
	_clear()
	title_label.text = "TimoOS 98 — Escritorio"
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for a in APPS:
		var label: String = a[1]
		if a[0] == "mail" and Game.unread_emails() > 0:
			label += " (%d)" % Game.unread_emails()
		var b := UIKit.button(label, _open_app.bind(a[0]), Color(a[2]), 110, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	content.add_child(UIKit.scroll(grid))
	content.add_child(UIKit.label("Consejo del día: %s" % ["Responde a las preguntas del cliente: lo recuerdan.", "No cambies el precio sin explicar un descuento.", "Presentarte baja la sospecha.", "Si prometes explicar algo, explícalo.", "Cada personalidad odia cosas distintas. El CRM ayuda."][rng.randi() % 5], 20, Color("d6eaf8")))


func _app_header(t: String) -> VBoxContainer:
	_clear()
	title_label.text = "TimoOS 98 — " + t
	var body := UIKit.vbox(10)
	var p := UIKit.panel(Color(0.96, 0.95, 0.92, 0.97), 16, 16)
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner := UIKit.vbox(10)
	p.add_child(UIKit.scroll(inner))
	content.add_child(p)
	inner.add_child(body)
	return body


func _dark(text: String, size := 22, color := Color("1b1b22")) -> Label:
	return UIKit.label(text, size, color)


func _open_app(id: String) -> void:
	Audio.play("click")
	match id:
		"phone":
			_app_phone()
		"crm":
			_app_crm()
		"calendar":
			_app_calendar()
		"stats":
			_app_stats()
		"goals":
			_app_goals()
		"tx":
			_app_tx()
		"shop":
			_app_shop()
		"mail":
			_app_mail()
		"evals":
			_app_evals()
		"tools":
			_app_tools()
		"settings":
			open_settings.emit()


func _app_phone() -> void:
	var b := _app_header("Teléfono · Lista de llamadas")
	if not Game.in_shift:
		b.add_child(_dark("La jornada no ha empezado."))
		return
	b.add_child(_dark("Llama a quien quieras. Los ★ indican dificultad. Las llamadas entrantes también suenan en tu mesa.", 20, Color("444444")))
	var m := Game.mods()
	for lead in Game.leads:
		var row := UIKit.panel(Color("e8e4da") if not lead["called"] else Color("cfcfcf"), 12, 10)
		var h := UIKit.hbox(10)
		row.add_child(h)
		var info := UIKit.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c := ClientDB.get_c(lead["client_id"])
		var tag := " [LE DEBES UNA LLAMADA]" if lead.get("callback", false) else ""
		info.add_child(_dark("%s  %s%s" % [lead["name"], "★".repeat(int(lead["stars"])), tag], 22))
		var sub: String = "Llamada libre · idea opcional: " + OfferDB.get_o(lead["offer"])["name"]
		sub += "  ·  " + PersonalityDB.get_p(c["personality"])["name"]
		info.add_child(_dark(sub, 17, Color("555555")))
		h.add_child(info)
		if lead["called"]:
			h.add_child(_dark("Llamado", 20, Color("777777")))
		else:
			var btn := UIKit.button("Llamar", func() -> void:
				request_call.emit(lead)
				queue_free(), UIKit.C_GOOD, 60, 22)
			btn.custom_minimum_size = Vector2(140, 60)
			h.add_child(btn)
		b.add_child(row)


func _app_crm() -> void:
	var b := _app_header("Clientes (CRM)")
	var list: Array = Save.data["crm"].duplicate()
	list.reverse()
	if list.is_empty():
		b.add_child(_dark("Aún no has hablado con nadie."))
	for e in list:
		var row := UIKit.panel(Color("e8e4da"), 12, 10)
		var v := UIKit.vbox(2)
		row.add_child(v)
		v.add_child(_dark("Día %d · %s — %s" % [int(e["day"]), e["name"], Economy.OUTCOMES.get(e["outcome"], e["outcome"])], 21))
		v.add_child(_dark("Oferta: %s" % e.get("offer", ""), 17, Color("555555")))
		if str(e.get("note", "")) != "":
			v.add_child(_dark("Nota: " + str(e["note"]), 17, Color("6b4f1d")))
		b.add_child(row)


func _app_calendar() -> void:
	var b := _app_header("Calendario de campaña")
	var camp: Dictionary = Save.data["campaign"]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for d in range(1, CampaignDB.DAYS.size() + 1):
		var info := CampaignDB.day_info(d)
		var unlocked := d <= int(camp["max_day_unlocked"])
		var grade := str(camp["day_grades"].get(str(d), ""))
		var col := Color("27ae60") if camp["completed_days"].has(d) else (Color("f5b041") if unlocked else Color("aaaaaa"))
		var p := UIKit.panel(col, 12, 10)
		p.custom_minimum_size = Vector2(230, 110)
		var v := UIKit.vbox(2)
		p.add_child(v)
		v.add_child(_dark("Día %d %s" % [d, ("· Nota " + grade) if grade != "" else ""], 20))
		v.add_child(_dark(info["title"], 16))
		v.add_child(_dark("Cuota %s" % UIKit.money(int(info["quota"])), 16))
		grid.add_child(p)
	b.add_child(grid)
	if int(camp["max_day_unlocked"]) > CampaignDB.DAYS.size():
		b.add_child(_dark("Campaña completada: modo infinito activado.", 22, Color("1e8449")))


func _app_stats() -> void:
	var b := _app_header("Estadísticas")
	var s: Dictionary = Save.data["stats"]
	var calls := maxi(1, int(s["calls_made"]))
	var rows := [
		["Jornadas completadas", s["days_completed"]], ["Llamadas realizadas", s["calls_made"]],
		["Transacciones ficticias", s["transactions"]], ["Tasa de éxito", "%d %%" % int(100.0 * int(s["transactions"]) / calls)],
		["Dinero ficticio acumulado", UIKit.money(int(s["money_total"]))], ["Récord en un día", UIKit.money(int(s["record_day_income"]))],
		["Clientes distintos atendidos", s["clients_served"].size()], ["Objetivos completados", s["objectives_completed"]],
		["Veces que te colgaron", s["hangups"]], ["Frases por micrófono", s["voice_turns"]],
		["Llamada más larga", "%d s" % int(s["longest_call_s"])], ["Mejor nota", s["best_grade"] if s["best_grade"] != "" else "-"],
		["Logros", "%d / %d" % [Save.data["achievements"].size(), AchievementDB.ACHIEVEMENTS.size()]],
	]
	for r in rows:
		var h := UIKit.hbox(10)
		var l := _dark(str(r[0]), 21)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(_dark(str(r[1]), 21, Color("1f618d")))
		b.add_child(h)
	b.add_child(_dark("Logros", 24, Color("6c3483")))
	for id in AchievementDB.ACHIEVEMENTS.keys():
		var got: bool = Save.data["achievements"].has(id)
		var a: Dictionary = AchievementDB.ACHIEVEMENTS[id]
		b.add_child(_dark(("[X] " if got else "[  ] ") + a["name"] + " — " + a["desc"], 18, Color("1e8449") if got else Color("777777")))
	b.add_child(_dark("IA: %s. Respuestas generadas en esta sesión: %d (media %.1f s). Todo se calcula en el móvil, sin conexión." % [Brain.status_text(), Brain.turns_total, Brain.avg_turn_seconds()], 17, Color("555555")))


func _app_goals() -> void:
	var b := _app_header("Objetivos de hoy")
	if not Game.in_shift:
		b.add_child(_dark("La jornada no ha empezado."))
		return
	var q := Game.quota()
	var inc := int(Game.ledger["income"])
	b.add_child(_dark("Día %d · %s" % [Game.day, CampaignDB.day_info(Game.day)["title"]], 26, Color("a04000")))
	b.add_child(_dark("Cuota: %s / %s" % [UIKit.money(inc), UIKit.money(q)], 24))
	b.add_child(UIKit.bar(mini(inc, q), q, UIKit.C_GOOD, 24))
	var calls_left := maxi(1, Game.leads.filter(func(l): return not l["called"]).size())
	b.add_child(_dark("Te falta %s. Unas %s por llamada con los clientes que quedan." % [UIKit.money(maxi(0, q - inc)), UIKit.money(int(maxi(0, q - inc) / float(calls_left)))], 20, Color("555555")))
	for o in Game.objectives:
		b.add_child(_dark(("[X] " if o["done"] else "[  ] ") + "%s  (+%s)" % [o["text"], UIKit.money(int(o["reward"]))], 22, Color("1e8449") if o["done"] else Color("1b1b22")))
	b.add_child(_dark("Avisos del jefe: %d/3" % int(Save.data["campaign"]["strikes"]), 20, Color("a93226")))


func _app_tx() -> void:
	var b := _app_header("Transacciones y saldo")
	b.add_child(_dark("Todo es dinero de juego. Las tarjetas son ficticias (prefijo 0000, inservibles).", 17, Color("a93226")))
	# Resumen
	var sp := UIKit.panel(Color("e8f6ef"), 12, 12)
	var sv := UIKit.vbox(4)
	sp.add_child(sv)
	sv.add_child(_dark("Saldo: %s" % UIKit.money(int(Save.data["money"])), 30, Color("145a32")))
	if Game.in_shift:
		var q := Game.quota()
		sv.add_child(_dark("Hoy (día %d): ventas %s de %s de cuota · tu comisión %s · neto del día %s" % [Game.day, UIKit.money(int(Game.ledger["income"])), UIKit.money(q), UIKit.money(int(Game.ledger.get("commissions", 0))), UIKit.money(int(Game.ledger.get("net", 0)))], 19))
		sv.add_child(UIKit.bar(mini(int(Game.ledger["income"]), q), q, UIKit.C_GOOD, 16))
		sv.add_child(_dark("Llamadas: %d · ventas: %d · colgadas: %d · mejor venta: %s" % [Game.ledger["calls"], Game.ledger["successes"], Game.ledger["hangups"], UIKit.money(int(Game.ledger["best_sale"]))], 18, Color("555555")))
	sv.add_child(_dark("Comisión por venta: %d %% del importe (más con mejoras). Las ventas suman a la cuota; tu saldo cobra la comisión al momento. Al final del día se pagan los gastos." % int(Economy.COMMISSION_RATE * 100), 16, Color("555555")))
	b.add_child(sp)
	# Pestañas: ventas / movimientos / llamadas de hoy
	var tabs := UIKit.hbox(8)
	b.add_child(tabs)
	var area := UIKit.vbox(6)
	b.add_child(area)
	var show_sales := func() -> void:
		for c in area.get_children():
			c.queue_free()
		var list: Array = Save.data["transactions"].duplicate()
		list.reverse()
		if list.is_empty():
			area.add_child(_dark("Sin ventas todavía. Cierra una llamada con «Pedir datos de pago»."))
		for t in list:
			var row := UIKit.panel(Color("ece8de"), 10, 8)
			var v := UIKit.vbox(2)
			row.add_child(v)
			v.add_child(_dark("%s · Día %d · %s" % [t.get("id", "TX"), int(t["day"]), t["client"]], 18, Color("555555")))
			v.add_child(_dark("%s" % t.get("proposal", t.get("offer", "")), 21))
			v.add_child(_dark("%s × %d = %s  ·  comisión %s  ·  %s  ·  %s" % [UIKit.money(int(t.get("unit_price", t["amount"]))), int(t.get("quantity", 1)), UIKit.money(int(t["amount"])), UIKit.money(int(t.get("commission", 0))), t.get("status", "completada"), t.get("card", "")], 18, Color("1f618d")))
			area.add_child(row)
	var show_moves := func() -> void:
		for c in area.get_children():
			c.queue_free()
		var list: Array = Save.data.get("movements", []).duplicate()
		list.reverse()
		if list.is_empty():
			area.add_child(_dark("Sin movimientos todavía."))
		var names := {"comision": "Comisión", "incentivo": "Incentivo", "bono": "Bono", "recompensa": "Recompensa", "multa": "Multa", "gasto": "Gasto", "compra": "Compra"}
		for m in list.slice(0, 80):
			var amt := int(m["amount"])
			area.add_child(_dark("Día %d · %s: %s  %s%s  → saldo %s" % [int(m["day"]), names.get(m["kind"], m["kind"]), m["label"], "+" if amt > 0 else "", UIKit.money(amt), UIKit.money(int(m["balance"]))], 18, Color("1e8449") if amt > 0 else Color("a93226")))
	var show_calls := func() -> void:
		for c in area.get_children():
			c.queue_free()
		if not Game.in_shift or Game.ledger["results"].is_empty():
			area.add_child(_dark("Aún no has hecho llamadas hoy."))
			return
		var rs: Array = Game.ledger["results"].duplicate()
		rs.reverse()
		for r in rs:
			area.add_child(_dark("%s · %s · %s%s" % [r["client_name"], r.get("offer_name", ""), r["outcome_text"], ("  ·  %s" % UIKit.money(int(r.get("final_amount", 0)))) if int(r.get("final_amount", 0)) > 0 else ""], 18, Color("1e8449") if r["outcome"] == "success" else Color("555555")))
	tabs.add_child(UIKit.button("Ventas", show_sales, UIKit.C_BLUE, 48, 18))
	tabs.add_child(UIKit.button("Movimientos del saldo", show_moves, UIKit.C_BLUE, 48, 18))
	tabs.add_child(UIKit.button("Llamadas de hoy", show_calls, UIKit.C_BLUE, 48, 18))
	show_sales.call()


func _app_shop() -> void:
	var b := _app_header("Tienda de mejoras")
	b.add_child(_dark("Saldo disponible: %s (tus comisiones se suman al momento; los gastos se pagan al final del día)" % UIKit.money(int(Save.data["money"])), 22, Color("1f618d")))
	var day := int(Save.data["campaign"]["max_day_unlocked"])
	for id in UpgradeDB.UPGRADES.keys():
		var u: Dictionary = UpgradeDB.UPGRADES[id]
		var row := UIKit.panel(Color("e8e4da"), 12, 10)
		var h := UIKit.hbox(10)
		row.add_child(h)
		var v := UIKit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(_dark("%s — %s" % [u["name"], UIKit.money(int(u["cost"]))], 21))
		v.add_child(_dark(u["desc"] + ("  (Requiere: %s)" % UpgradeDB.UPGRADES[u["requires"]]["name"] if u.has("requires") else ""), 17, Color("555555")))
		h.add_child(v)
		var chk := UpgradeDB.can_buy(id, Save.data["upgrades_owned"], int(Save.data["money"]), day)
		if Save.data["upgrades_owned"].has(id):
			h.add_child(_dark("Comprado", 20, Color("1e8449")))
		elif int(u["day"]) > day:
			h.add_child(_dark("Día %d" % int(u["day"]), 20, Color("777777")))
		else:
			var btn := UIKit.button("Comprar", func() -> void:
				var r := Game.buy_upgrade(id)
				if r["ok"]:
					Audio.play("cash")
					Game.notify.emit("Comprado: " + u["name"], "good")
				else:
					Audio.play("error")
					Game.notify.emit(r["why"], "bad")
				_app_shop(), UIKit.C_GOOD if chk["ok"] else Color("95a5a6"), 58, 20)
			btn.custom_minimum_size = Vector2(140, 58)
			h.add_child(btn)
		b.add_child(row)


func _app_mail() -> void:
	var b := _app_header("Correo")
	var list: Array = Save.data["emails"].duplicate()
	list.reverse()
	if list.is_empty():
		b.add_child(_dark("Bandeja vacía."))
	for e in list:
		var row := UIKit.panel(Color("fdebd0") if not e["read"] else Color("e8e4da"), 12, 10)
		var v := UIKit.vbox(4)
		row.add_child(v)
		v.add_child(_dark(("[NUEVO] " if not e["read"] else "") + "%s — %s" % [e["from"], e["subject"]], 21))
		v.add_child(_dark(e["body"], 18, Color("333333")))
		e["read"] = true
		b.add_child(row)
	Save.save_game()


func _app_evals() -> void:
	var b := _app_header("Evaluaciones del jefe")
	var list: Array = Save.data["evaluations"].duplicate()
	list.reverse()
	if list.is_empty():
		b.add_child(_dark("Todavía no te han evaluado. Disfrútalo."))
	for e in list:
		var row := UIKit.panel(Color("e8e4da"), 12, 10)
		var v := UIKit.vbox(4)
		row.add_child(v)
		v.add_child(_dark("Día %d · Nota %s · %s de %s" % [int(e["day"]), e["grade"], UIKit.money(int(e["income"])), UIKit.money(int(e["quota"]))], 21))
		v.add_child(_dark("«%s»" % e["comment"], 18, Color("6c3483")))
		b.add_child(row)


func _app_tools() -> void:
	var b := _app_header("Herramientas cómicas")
	var excuse := _dark(EXCUSES[0], 22, Color("a04000"))
	b.add_child(_dark("Generador de excusas profesionales", 24))
	b.add_child(excuse)
	b.add_child(UIKit.button("Generar excusa", func() -> void:
		excuse.text = EXCUSES[rng.randi() % EXCUSES.size()]
		Audio.play("boing", -6.0), Color("d35400"), 60, 22))
	b.add_child(_dark("Botonera de efectos (para animar la oficina)", 24))
	var h := UIKit.hbox(8)
	for s in [["Aplausos", "applause"], ["Risas", "laugh"], ["Trombón triste", "wahwah"], ["Caja registradora", "cash"]]:
		h.add_child(UIKit.button(s[0], func() -> void: Audio.play(s[1]), Color("5d6d7e"), 58, 18))
	b.add_child(h)
	b.add_child(_dark("Calculadora de nervios", 24))
	var s_left := Game.shift_left if Game.in_shift else 0.0
	var ev_left := maxi(0, Game.events_budget - Game.events_done.size()) if Game.in_shift else 0
	var need := maxi(0, Game.quota() - int(Game.ledger.get("income", 0))) if Game.in_shift else 0
	b.add_child(_dark("Quedan %d min %d s de jornada, te faltan %s para la cuota y aún pueden pasar %d imprevistos hoy." % [int(s_left) / 60, int(s_left) % 60, UIKit.money(need), ev_left], 20))


func _show_crash() -> void:
	if crash_layer and is_instance_valid(crash_layer):
		return
	crash_progress = 0.0
	crash_layer = Control.new()
	crash_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crash_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(crash_layer)
	var bg := ColorRect.new()
	bg.color = Color("1a3fa8")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crash_layer.add_child(bg)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crash_layer.add_child(cc)
	var v := UIKit.vbox(16)
	cc.add_child(v)
	v.add_child(UIKit.label(":(", 90, Color.WHITE))
	v.add_child(UIKit.label("TimoOS ha encontrado un problema y necesita llorar un rato.\nToca la pantalla para animarlo a reiniciar.", 28, Color.WHITE))
	var bar := UIKit.bar(0, 100, Color.WHITE, 26)
	bar.custom_minimum_size = Vector2(600, 26)
	v.add_child(bar)
	crash_layer.set_meta("bar", bar)
	crash_layer.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			crash_progress += 7.0
			Audio.play("type", -6.0))
	Audio.play("error")


func _process(delta: float) -> void:
	if crash_layer and is_instance_valid(crash_layer):
		crash_progress += delta * 3.5
		(crash_layer.get_meta("bar") as ProgressBar).value = crash_progress
		if crash_progress >= 100.0 or not Game.is_event("pc_crash"):
			crash_layer.queue_free()
			crash_layer = null
			if Game.is_event("pc_crash"):
				Game.end_event()
			Audio.play("ding")
