extends Node
## Estado de la jornada en curso y aplicación AUTORITATIVA de los resultados
## (dinero ficticio, estadísticas, objetivos, logros, correo, evaluaciones).

signal money_changed(day_income: int)
signal balance_changed(balance: int)
signal clock_changed(minutes_left: float)
signal notify(text: String, kind: String)
signal event_started(id: String)
signal event_ended(id: String)
signal day_ended(report: Dictionary)
signal leads_changed
signal achievement_unlocked(id: String)

var rng := RandomNumberGenerator.new()
var day := 1
var in_shift := false
var shift_total := 540.0
var shift_left := 540.0
var ledger := {}
var objectives: Array = []
var leads: Array = []
var active_event := ""
var event_time_left := 0.0
var events_done: Array = []
var events_budget := 0
var next_event_in := 60.0
var buffs := {"next_call_mult": 1.0, "pizza": 0.0, "hard_client": false, "weird_question": false, "vip_mult": 1.0}
var quota_half_said := false
var quota_done_said := false
var late_said := false
var on_call := false
var soundboard_used := false


func _ready() -> void:
	rng.randomize()


# ------------------------------------------------------------------ Jornada

func start_day(d: int) -> void:
	day = clampi(d, 1, int(Save.data["campaign"]["max_day_unlocked"]))
	Save.data["campaign"]["current_day"] = day
	shift_total = float(Settings.get_value("shift_minutes")) * 60.0
	shift_left = shift_total
	in_shift = true
	on_call = false
	ledger = {"income": 0, "calls": 0, "successes": 0, "hangups": 0, "results": [], "contradictions": 0,
		"best_sale": 0, "streak": 0, "max_streak": 0, "incidents": 0, "fines": 0, "bonuses": 0,
		"objections_resolved": 0, "voice_turns": 0, "missed": 0, "quota": CampaignDB.quota(day),
		"commissions": 0, "net": 0, "sales_amount": 0}
	objectives = AchievementDB.make_objectives(day, rng)
	events_done = []
	events_budget = int(CampaignDB.day_info(day)["events"])
	next_event_in = rng.randf_range(35.0, 70.0)
	active_event = ""
	buffs = {"next_call_mult": 1.0, "pizza": 0.0, "hard_client": false, "weird_question": false, "vip_mult": 1.0}
	quota_half_said = false
	quota_done_said = false
	late_said = false
	_generate_leads()
	_add_email("jefe_dia_%d" % day, BossLines.BOSS_NAME, "Día %d: %s" % [day, CampaignDB.day_info(day)["title"]], CampaignDB.day_info(day)["boss"] + "\n\nCuota de hoy: %d." % ledger["quota"])
	Save.save_game()
	money_changed.emit(0)


func mods() -> Dictionary:
	var m := UpgradeDB.aggregate_mods(Save.data["upgrades_owned"])
	m["next_call_mult"] = buffs["next_call_mult"] * buffs["vip_mult"]
	return m


func quota() -> int:
	return int(ledger.get("quota", CampaignDB.quota(day)))


func clock_text() -> String:
	var frac := 1.0 - shift_left / maxf(1.0, shift_total)
	var minutes := int(frac * (CampaignDB.SHIFT_END_HOUR - CampaignDB.SHIFT_START_HOUR) * 60.0)
	return "%02d:%02d" % [CampaignDB.SHIFT_START_HOUR + minutes / 60, minutes % 60]


func _process(delta: float) -> void:
	if not in_shift or get_tree().paused:
		return
	shift_left = maxf(0.0, shift_left - delta)
	clock_changed.emit(shift_left)
	if active_event != "":
		event_time_left -= delta
		if event_time_left <= 0.0 and float(EventDB.EVENTS[active_event]["duration"]) > 0.0:
			end_event()
	else:
		next_event_in -= delta
		if next_event_in <= 0.0 and events_done.size() < events_budget and shift_left > 40.0:
			var id := EventDB.pick(day, rng, events_done)
			if id != "":
				start_event(id)
			next_event_in = rng.randf_range(50.0, 95.0)
	if not late_said and shift_left < shift_total * 0.25 and ledger["income"] < quota() * 0.5 and not on_call:
		late_said = true
		notify.emit(BossLines.remark("late_low", rng), "boss")


func start_event(id: String) -> void:
	active_event = id
	event_time_left = float(EventDB.EVENTS[id]["duration"])
	events_done.append(id)
	ledger["incidents"] += 1 if id in ["pc_crash", "phone_outage", "interruption"] else 0
	match id:
		"special_opportunity":
			buffs["next_call_mult"] = 2.0
		"hard_client":
			buffs["hard_client"] = true
		"weird_clarification":
			buffs["weird_question"] = true
	notify.emit("%s — %s" % [EventDB.EVENTS[id]["name"], EventDB.EVENTS[id]["desc"]], "event")
	event_started.emit(id)
	if float(EventDB.EVENTS[id]["duration"]) <= 0.0:
		active_event = ""
		event_ended.emit(id)


func end_event() -> void:
	if active_event == "":
		return
	var id := active_event
	active_event = ""
	event_ended.emit(id)


func is_event(id: String) -> bool:
	return active_event == id


# ------------------------------------------------------------------ Leads

func _generate_leads() -> void:
	leads.clear()
	var pool := ClientDB.available_for_day(day)
	pool.shuffle()
	var count := mini(pool.size(), 6 + int(CampaignDB.day_info(day)["lead_bonus"]))
	for i in count:
		leads.append(_make_lead(pool[i]))
	# Clientes que pidieron que les volvieran a llamar
	for cb in Save.data["callbacks"]:
		var lead := _make_lead(cb["client_id"])
		lead["callback"] = true
		lead["offer"] = cb.get("offer_id", lead["offer"])
		lead["trust_bonus"] = float(cb.get("trust_bonus", 10))
		leads.push_front(lead)
	Save.data["callbacks"] = []
	leads_changed.emit()


func _make_lead(client_id: String) -> Dictionary:
	var c := ClientDB.get_c(client_id)
	var offers := OfferDB.unlocked_for_day(day)
	var best: String = offers[0]
	var best_aff := -1.0
	for o in offers:
		var a := ClientDB.offer_affinity(client_id, o) + rng.randf() * 0.3
		if a > best_aff:
			best_aff = a
			best = o
	return {"client_id": client_id, "name": c["name"], "stars": int(c["difficulty"]), "offer": best, "called": false, "callback": false, "trust_bonus": 0.0}


func next_incoming_lead() -> Dictionary:
	var open := leads.filter(func(l): return not l["called"])
	if buffs["hard_client"]:
		var hard := open.filter(func(l): return int(l["stars"]) >= 3)
		if hard.is_empty():
			var extra_pool := ClientDB.available_for_day(maxi(day, 3)).filter(func(id): return int(ClientDB.get_c(id)["difficulty"]) >= 3)
			if not extra_pool.is_empty():
				var l := _make_lead(extra_pool[rng.randi() % extra_pool.size()])
				leads.append(l)
				hard = [l]
		if not hard.is_empty():
			return hard[0]
	if open.is_empty():
		var pool := ClientDB.available_for_day(day)
		var l2 := _make_lead(pool[rng.randi() % pool.size()])
		leads.append(l2)
		leads_changed.emit()
		return l2
	return open[rng.randi() % open.size()]


func call_flags_for(lead: Dictionary) -> Dictionary:
	var m := mods()
	var flags := {
		"extra_trust": float(m.get("trust_start", 0.0)) + float(lead.get("trust_bonus", 0.0)),
		"extra_patience": float(m.get("patience_start", 0.0)) + buffs["pizza"],
		"weird_question": buffs["weird_question"],
		"time_mult": float(m.get("call_time_mult", 1.0)),
		"amount_extra": 1.0,
	}
	if buffs["hard_client"] and int(lead["stars"]) >= 3:
		flags["amount_extra"] = 1.4
	return flags


# ------------------------------------------------------------------ Resultados

## Movimiento del saldo ficticio del jugador (todo pasa por aquí y queda registrado).
## kind: comision | incentivo | bono | recompensa | multa | gasto | compra
func post(kind: String, amount: int, label: String) -> void:
	if amount == 0:
		return
	Save.data["money"] = int(Save.data["money"]) + amount
	Save.push_capped("movements", {"day": day, "kind": kind, "amount": amount, "label": label, "balance": int(Save.data["money"]), "unix": int(Time.get_unix_time_from_system())})
	if kind != "compra" and not ledger.is_empty():
		ledger["net"] = int(ledger.get("net", 0)) + amount
	balance_changed.emit(int(Save.data["money"]))


## Aplica el resultado de una llamada. El importe y la comisión vienen de las reglas
## (Economy); aquí se vuelven a acotar, se registra la transacción ficticia y se
## actualiza el saldo al momento.
func apply_call_result(r: Dictionary) -> void:
	var lead_id: String = r["client_id"]
	for l in leads:
		if l["client_id"] == lead_id:
			l["called"] = true
	leads_changed.emit()
	ledger["calls"] += 1
	Save.stat_add("calls_made")
	var served: Dictionary = Save.data["stats"]["clients_served"]
	served[lead_id] = int(served.get(lead_id, 0)) + 1
	var outcome: String = r["outcome"]
	var amount := 0
	var commission := 0
	var label := String(r.get("offer_name", "Propuesta"))
	if outcome == "success":
		var cap := int(ClientDB.budget(lead_id, day) * Economy.AMOUNT_CAP_X_BUDGET)  # límite absoluto
		amount = clampi(int(r["amount"]), 0, cap)
		commission = clampi(int(r.get("commission", Economy.commission(amount, mods()))), 0, int(amount * Economy.COMMISSION_RATE * 3.0))
		ledger["successes"] += 1
		ledger["streak"] += 1
		ledger["max_streak"] = maxi(ledger["max_streak"], ledger["streak"])
		ledger["best_sale"] = maxi(ledger["best_sale"], amount)
		ledger["sales_amount"] = int(ledger.get("sales_amount", 0)) + amount
		ledger["commissions"] = int(ledger.get("commissions", 0)) + commission
		Save.stat_add("transactions")
		Save.stat_add("successes")
		buffs["next_call_mult"] = 1.0
		Save.push_capped("transactions", {
			"id": "TX-%d-%04d" % [day, randi() % 10000], "day": day, "client": r["client_name"], "client_id": lead_id,
			"proposal": label, "unit_price": int(r.get("unit_price", amount)), "quantity": int(r.get("quantity", 1)),
			"amount": amount, "commission": commission, "status": "completada", "outcome": r.get("outcome_text", ""),
			"card": r.get("card", {}).get("masked", ""), "turns": int(r.get("turns", 0)), "mode": r.get("mode", ""),
		})
		post("comision", commission, "Comisión: %s (%s)" % [label, r["client_name"]])
		if amount >= 400:
			unlock("big_fish")
		var p: String = ClientDB.get_c(lead_id)["personality"]
		if p == "detector":
			unlock("detector_sale")
		if p == "sospechoso":
			unlock("paranoid_sale")
	else:
		ledger["streak"] = 0
		var consolation := Economy.consolation(outcome)
		if consolation > 0:
			post("incentivo", consolation, "Incentivo: %s quedó %s" % [r["client_name"], "interesado" if outcome == "interested" else "pendiente de rellamada"])
		if outcome in ["hangup", "contradiction"]:
			ledger["hangups"] += 1
			Save.stat_add("hangups")
		else:
			Save.stat_add("failures")
		if outcome == "callback":
			Save.push_capped("callbacks", {"client_id": lead_id, "offer_id": r.get("offer_id", ""), "trust_bonus": 12, "day": day})
	ledger["income"] += amount
	ledger["contradictions"] += int(r.get("contradictions", 0))
	ledger["objections_resolved"] += int(r.get("objections_resolved", 0))
	ledger["voice_turns"] += int(r.get("voice_turns", 0))
	r["final_amount"] = amount
	r["final_commission"] = commission
	ledger["results"].append(r)
	buffs["pizza"] = 0.0
	buffs["weird_question"] = false
	buffs["vip_mult"] = 1.0
	if outcome == "success" and buffs["hard_client"]:
		buffs["hard_client"] = false
	if int(r.get("duration", 0)) > int(Save.data["stats"]["longest_call_s"]):
		Save.data["stats"]["longest_call_s"] = int(r["duration"])
	if int(r.get("duration", 0)) >= 120:
		unlock("long_talk")
	Save.push_capped("crm", {"client_id": lead_id, "name": r["client_name"], "outcome": outcome, "day": day, "offer": label, "note": r.get("comment", "")})
	_update_objectives(r)
	_check_achievements()
	money_changed.emit(ledger["income"])
	if not quota_half_said and ledger["income"] >= quota() * 0.5 and ledger["income"] < quota():
		quota_half_said = true
		notify.emit(BossLines.remark("quota_half", rng), "boss")
	elif ledger["income"] >= quota() and not quota_done_said:
		quota_done_said = true
		notify.emit(BossLines.remark("quota_done", rng), "boss")
	Save.save_game()


func add_fine(amount: int, why: String) -> void:
	ledger["fines"] += amount
	post("multa", -amount, why)
	notify.emit("%s (-%d)" % [why, amount], "bad")


func add_bonus(amount: int, why: String) -> void:
	ledger["bonuses"] += amount
	post("bono", amount, why)
	notify.emit("%s (+%d)" % [why, amount], "good")


func register_missed_call() -> void:
	ledger["missed"] += 1
	notify.emit(BossLines.remark("missed", rng), "boss")


func _update_objectives(r: Dictionary) -> void:
	for o in objectives:
		if o["done"]:
			continue
		match o["type"]:
			"sales":
				o["progress"] = ledger["successes"]
			"calls":
				o["progress"] = ledger["calls"]
			"voice_turns":
				o["progress"] = ledger["voice_turns"]
			"resolve_objections":
				o["progress"] = ledger["objections_resolved"]
			"big_sale":
				o["progress"] = ledger["best_sale"]
			"no_hangups":
				o["progress"] = 0 if ledger["hangups"] > 0 else 1
		if o["type"] != "no_hangups" and int(o["progress"]) >= int(o["target"]):
			o["done"] = true
			Save.stat_add("objectives_completed")
			notify.emit("Objetivo cumplido: %s (+%d)" % [o["text"], o["reward"]], "good")
			Audio.play("levelup")


func unlock(id: String) -> void:
	var list: Array = Save.data["achievements"]
	if list.has(id) or not AchievementDB.ACHIEVEMENTS.has(id):
		return
	list.append(id)
	achievement_unlocked.emit(id)
	notify.emit("Logro desbloqueado: " + AchievementDB.ACHIEVEMENTS[id]["name"], "achievement")
	Audio.play("applause", -6.0)


func _check_achievements() -> void:
	var s: Dictionary = Save.data["stats"]
	if int(s["transactions"]) >= 1:
		unlock("first_sale")
	if int(s["transactions"]) >= 10:
		unlock("ten_sales")
	if int(s["transactions"]) >= 50:
		unlock("fifty_sales")
	if int(s["voice_turns"]) >= 20:
		unlock("voice_seller")
	if Save.data["stats"]["clients_served"].size() >= 15:
		unlock("meet_all")
	if int(s["money_total"]) + int(ledger.get("income", 0)) >= 5000:
		unlock("rich")
	if int(ledger.get("max_streak", 0)) >= 3:
		unlock("streak")


## Datos de la jornada para que el jefe (IA o local) comente antes de cerrar.
func day_stats_preview() -> Dictionary:
	var income: int = ledger["income"]
	var q := quota()
	return {"income": income, "quota": q, "grade": BossLines.grade_for(income, q, ledger["hangups"], ledger["calls"]),
		"calls": ledger["calls"], "successes": ledger["successes"], "hangups": ledger["hangups"],
		"contradictions": ledger["contradictions"], "best_sale": ledger["best_sale"], "incidents": ledger["incidents"],
		"missed": ledger["missed"], "day": day, "passed": income >= q}


## Cierra la jornada y aplica todo al guardado. Devuelve el informe completo.
func end_day(boss_comment := "") -> Dictionary:
	in_shift = false
	var income: int = ledger["income"]
	var q := quota()
	var exp_list := CampaignDB.expenses(day, Save.data["upgrades_owned"])
	var expenses := 0
	for e in exp_list:
		expenses += int(e["amount"])
	# Objetivo "nadie me cuelga" se evalúa al final
	for o in objectives:
		if o["type"] == "no_hangups" and not o["done"] and ledger["hangups"] == 0 and ledger["calls"] >= 2:
			o["done"] = true
			Save.stat_add("objectives_completed")
	var rewards := 0
	for o in objectives:
		if o["done"]:
			rewards += int(o["reward"])
	var passed := income >= q
	var grade := BossLines.grade_for(income, q, ledger["hangups"], ledger["calls"])
	var day_bonus := int(q * 0.25) if passed else 0
	# Al cerrar la jornada se cobran recompensas y bono de cuota y se pagan los gastos
	# (las comisiones, bonos y multas ya se aplicaron al saldo en su momento).
	for o in objectives:
		if o["done"]:
			post("recompensa", int(o["reward"]), "Objetivo: %s" % o.get("text", o.get("type", "")))
	if day_bonus > 0:
		post("bono", day_bonus, "Bono por cumplir la cuota del día %d" % day)
	for e in exp_list:
		post("gasto", -int(e["amount"]), String(e["label"]))
	var net := int(ledger.get("net", 0))
	var stats_for_boss := {"income": income, "quota": q, "grade": grade, "calls": ledger["calls"], "successes": ledger["successes"],
		"hangups": ledger["hangups"], "contradictions": ledger["contradictions"], "best_sale": ledger["best_sale"],
		"incidents": ledger["incidents"], "missed": ledger["missed"], "day": day, "passed": passed}
	var comment := boss_comment if boss_comment != "" else BossLines.evaluation(stats_for_boss, rng)
	var camp: Dictionary = Save.data["campaign"]
	var fired := false
	if passed:
		camp["strikes"] = 0
		if not camp["completed_days"].has(day):
			camp["completed_days"].append(day)
		camp["max_day_unlocked"] = maxi(int(camp["max_day_unlocked"]), day + 1)
		camp["current_day"] = day + 1
		Save.stat_add("days_completed")
		unlock("first_day")
		if income >= q * 2:
			unlock("double_quota")
		if ledger["hangups"] == 0 and ledger["calls"] >= 3:
			unlock("perfect_day")
		if CampaignDB.is_campaign_end(day):
			unlock("campaign_done")
	else:
		camp["strikes"] = int(camp["strikes"]) + 1
		if int(camp["strikes"]) >= 3:
			fired = true
			camp["strikes"] = 0
	if grade == "S":
		unlock("grade_s")
	var prev_grade := str(camp["day_grades"].get(str(day), ""))
	if prev_grade == "" or "SABCDF".find(grade) < "SABCDF".find(prev_grade):
		camp["day_grades"][str(day)] = grade
	Save.data["career_earnings"] = int(Save.data["career_earnings"]) + maxi(0, income)
	Save.stat_add("money_total", maxi(0, income))
	if income > int(Save.data["stats"]["record_day_income"]):
		Save.data["stats"]["record_day_income"] = income
	var best := str(Save.data["stats"]["best_grade"])
	if best == "" or "SABCDF".find(grade) < "SABCDF".find(best):
		Save.data["stats"]["best_grade"] = grade
	Save.push_capped("evaluations", {"day": day, "grade": grade, "comment": comment, "income": income, "quota": q})
	_add_email("eval_%d_%d" % [day, Time.get_ticks_msec()], BossLines.BOSS_NAME, "Evaluación del día %d: %s" % [day, grade], comment)
	_check_achievements()
	Save.save_game()
	var report := {"day": day, "income": income, "quota": q, "passed": passed, "grade": grade, "comment": comment,
		"expenses": exp_list, "expenses_total": expenses, "rewards": rewards, "objectives": objectives.duplicate(true),
		"day_bonus": day_bonus, "fines": ledger["fines"], "bonuses": ledger["bonuses"], "net": net, "fired": fired,
		"commissions": int(ledger.get("commissions", 0)),
		"calls": ledger["calls"], "successes": ledger["successes"], "hangups": ledger["hangups"],
		"strikes": camp["strikes"], "money": Save.data["money"], "stats_for_boss": stats_for_boss}
	day_ended.emit(report)
	return report


func _add_email(id: String, from: String, subject: String, body: String) -> void:
	for e in Save.data["emails"]:
		if e["id"] == id:
			return
	Save.push_capped("emails", {"id": id, "from": from, "subject": subject, "body": body, "read": false, "day": day})


func unread_emails() -> int:
	return Save.data["emails"].filter(func(e): return not e["read"]).size()


func buy_upgrade(id: String) -> Dictionary:
	var chk := UpgradeDB.can_buy(id, Save.data["upgrades_owned"], int(Save.data["money"]), int(Save.data["campaign"]["max_day_unlocked"]))
	if not chk["ok"]:
		return chk
	post("compra", -int(UpgradeDB.UPGRADES[id]["cost"]), "Mejora: %s" % UpgradeDB.UPGRADES[id]["name"])
	Save.data["upgrades_owned"].append(id)
	Save.save_game()
	return {"ok": true, "why": ""}


func buy_cosmetic(id: String) -> Dictionary:
	if not UpgradeDB.COSMETICS.has(id):
		return {"ok": false, "why": "No existe"}
	var owned: Array = Save.data["cosmetics_owned"]
	if owned.has(id):
		return {"ok": false, "why": "Ya lo tienes"}
	var cost := int(UpgradeDB.COSMETICS[id]["cost"])
	if int(Save.data["money"]) < cost:
		return {"ok": false, "why": "Dinero insuficiente"}
	post("compra", -cost, "Ropa: %s" % UpgradeDB.COSMETICS[id].get("name", id))
	owned.append(id)
	Save.save_game()
	return {"ok": true, "why": ""}


func equip_cosmetic(id: String) -> void:
	if not UpgradeDB.COSMETICS.has(id):
		return
	var slot: String = UpgradeDB.COSMETICS[id]["slot"]
	var eq: Dictionary = Save.data["equipped"]
	eq[slot] = "" if eq.get(slot, "") == id and slot in ["hat", "glasses", "tie"] else id
	Save.save_game()
