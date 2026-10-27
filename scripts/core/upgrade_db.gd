class_name UpgradeDB
extends RefCounted
## Mejoras, decoración y ropa. Los efectos se traducen a "mods" que consumen las reglas
## (ConversationRules/Economy/CallManager). Todo se compra con dinero ficticio del juego.

const UPGRADES := {
	"auriculares": {"name": "Auriculares con cancelación de excusas", "cost": 120, "day": 1, "cat": "herramientas",
		"desc": "+25 % de tiempo por llamada.", "mods": {"call_time_mult": 1.25}},
	"crm": {"name": "CRM Básico «Chismógrafo»", "cost": 160, "day": 1, "cat": "ordenador",
		"desc": "Muestra la personalidad del cliente antes de llamar.", "mods": {"show_personality": 1}},
	"crm_pro": {"name": "CRM Pro con fichas de cotilleo", "cost": 380, "day": 3, "cat": "ordenador", "requires": "crm",
		"desc": "Muestra qué le gusta y qué odia a cada cliente.", "mods": {"show_likes": 1}},
	"monitor_doble": {"name": "Monitor doble", "cost": 220, "day": 2, "cat": "ordenador",
		"desc": "Ves los valores exactos de confianza, paciencia y sospecha.", "mods": {"show_exact": 1}},
	"guion": {"name": "Guion de ventas plastificado", "cost": 150, "day": 1, "cat": "herramientas",
		"desc": "+20 % a la comprensión que generas.", "mods": {"understanding_mult": 1.2}},
	"frases": {"name": "Teclado de frases rápidas", "cost": 90, "day": 1, "cat": "herramientas",
		"desc": "Botones con frases útiles en el modo texto.", "mods": {"quick_phrases": 1}},
	"cafetera": {"name": "Cafetera personal", "cost": 200, "day": 2, "cat": "comodidad",
		"desc": "Los clientes empiezan con +10 de paciencia (tu buen humor se contagia). Sin gasto de café.", "mods": {"patience_start": 10.0}},
	"telefono_vip": {"name": "Teléfono dorado VIP", "cost": 450, "day": 3, "cat": "herramientas",
		"desc": "+15 % a los importes conseguidos.", "mods": {"amount_mult": 1.15}},
	"silla_gamer": {"name": "Silla gamer con luces", "cost": 180, "day": 2, "cat": "comodidad",
		"desc": "+20 % velocidad al caminar y alquiler de silla más barato.", "mods": {"move_speed_mult": 1.2}},
	"risas": {"name": "Botonera de risas enlatadas", "cost": 140, "day": 2, "cat": "herramientas",
		"desc": "Herramienta cómica: suelta risas en la llamada (+humor, una vez por llamada).", "mods": {"soundboard": 1}},
	"curso_empatia": {"name": "Curso exprés de empatía", "cost": 300, "day": 4, "cat": "herramientas",
		"desc": "+15 % a la confianza que ganas.", "mods": {"trust_mult": 1.15}},
	"manual_cierre": {"name": "Manual «Cierra como un tiburón»", "cost": 520, "day": 5, "cat": "herramientas",
		"desc": "+6 % de probabilidad de cierre.", "mods": {"close_bonus": 0.06}},
	"ventilador": {"name": "Ventilador antiestrés", "cost": 260, "day": 4, "cat": "comodidad",
		"desc": "Los clientes pierden paciencia un 15 % más despacio.", "mods": {"patience_drain_mult": 0.85}},
	"planta": {"name": "Planta de plástico motivadora", "cost": 60, "day": 1, "cat": "decoracion", "deco": true,
		"desc": "Decoración. +1 % de cierre (la planta cree en ti).", "mods": {"close_bonus": 0.01}},
	"lampara_lava": {"name": "Lámpara de lava", "cost": 110, "day": 2, "cat": "decoracion", "deco": true,
		"desc": "Decoración relajante. +2 de paciencia inicial.", "mods": {"patience_start": 2.0}},
	"pecera": {"name": "Pecera con pez filósofo", "cost": 170, "day": 3, "cat": "decoracion", "deco": true,
		"desc": "Decoración. +1 % de cierre.", "mods": {"close_bonus": 0.01}},
	"trofeo": {"name": "Trofeo comprado a ti mismo", "cost": 250, "day": 5, "cat": "decoracion", "deco": true,
		"desc": "Decoración. +3 de confianza inicial (se nota tu seguridad).", "mods": {"trust_start": 3.0}},
	"poster": {"name": "Póster «Vende humo, cobra nubes»", "cost": 80, "day": 1, "cat": "decoracion", "deco": true,
		"desc": "Decoración. Puramente estética.", "mods": {}},
}

const COSMETICS := {
	"hair_short": {"name": "Pelo corto", "slot": "hair", "cost": 0},
	"hair_messy": {"name": "Pelo despeinado", "slot": "hair", "cost": 40},
	"hair_long": {"name": "Melena", "slot": "hair", "cost": 60},
	"hair_mohawk": {"name": "Cresta", "slot": "hair", "cost": 90},
	"hair_afro": {"name": "Afro", "slot": "hair", "cost": 90},
	"hair_bald": {"name": "Calvo reluciente", "slot": "hair", "cost": 30},
	"shirt_blue": {"name": "Camisa azul de oficina", "slot": "shirt", "cost": 0, "color": "3a6ea5"},
	"shirt_red": {"name": "Camisa roja de tiburón", "slot": "shirt", "cost": 50, "color": "c0392b"},
	"shirt_hawaii": {"name": "Camisa hawaiana", "slot": "shirt", "cost": 120, "color": "f39c12"},
	"shirt_black": {"name": "Traje negro elegante", "slot": "shirt", "cost": 200, "color": "1e1e24"},
	"shirt_green": {"name": "Polo verde dólar", "slot": "shirt", "cost": 80, "color": "27ae60"},
	"hat_cap": {"name": "Gorra de vendedor", "slot": "hat", "cost": 60},
	"hat_top": {"name": "Chistera", "slot": "hat", "cost": 220},
	"hat_cowboy": {"name": "Sombrero vaquero", "slot": "hat", "cost": 160},
	"hat_beanie": {"name": "Gorro de lana", "slot": "hat", "cost": 50},
	"glasses_round": {"name": "Gafas redondas", "slot": "glasses", "cost": 70},
	"glasses_sun": {"name": "Gafas de sol de jefe", "slot": "glasses", "cost": 130},
	"tie_red": {"name": "Corbata roja", "slot": "tie", "cost": 60},
	"tie_bow": {"name": "Pajarita", "slot": "tie", "cost": 90},
	"tie_gold": {"name": "Corbata dorada", "slot": "tie", "cost": 300},
}


static func available(day: int) -> Array:
	var out := []
	for id in UPGRADES.keys():
		if int(UPGRADES[id]["day"]) <= day:
			out.append(id)
	return out


static func can_buy(id: String, owned: Array, money: int, day: int) -> Dictionary:
	if not UPGRADES.has(id):
		return {"ok": false, "why": "No existe"}
	var u: Dictionary = UPGRADES[id]
	if owned.has(id):
		return {"ok": false, "why": "Ya lo tienes"}
	if int(u["day"]) > day:
		return {"ok": false, "why": "Se desbloquea el día %d" % u["day"]}
	if u.has("requires") and not owned.has(u["requires"]):
		return {"ok": false, "why": "Requiere: " + UPGRADES[u["requires"]]["name"]}
	if money < int(u["cost"]):
		return {"ok": false, "why": "Dinero insuficiente"}
	return {"ok": true, "why": ""}


## Combina los efectos de todas las mejoras compradas.
static func aggregate_mods(owned: Array) -> Dictionary:
	var m := {"call_time_mult": 1.0, "understanding_mult": 1.0, "trust_mult": 1.0, "amount_mult": 1.0,
		"close_bonus": 0.0, "patience_start": 0.0, "trust_start": 0.0, "patience_drain_mult": 1.0, "move_speed_mult": 1.0}
	for id in owned:
		if not UPGRADES.has(id):
			continue
		var um: Dictionary = UPGRADES[id]["mods"]
		for k in um.keys():
			if k.ends_with("_mult"):
				m[k] = float(m.get(k, 1.0)) * float(um[k])
			elif k in ["close_bonus", "patience_start", "trust_start"]:
				m[k] = float(m.get(k, 0.0)) + float(um[k])
			else:
				m[k] = um[k]
	m["close_bonus"] = minf(float(m["close_bonus"]), 0.12)
	return m
