class_name CustomizeScreen
extends Control
## Personalización del personaje (pelo, camisa, sombrero, gafas, corbata) con vista
## previa 3D, y compra de ropa con dinero ficticio.

signal closed

var preview: SubViewport
var model: CharacterModel
var list_box: VBoxContainer
var money_label: Label
var slot := "hair"


static func player_look() -> Dictionary:
	var eq: Dictionary = Save.data["equipped"]
	var hair := str(eq.get("hair", "hair_short")).replace("hair_", "")
	var shirt_id := str(eq.get("shirt", "shirt_blue"))
	var shirt_col := str(UpgradeDB.COSMETICS.get(shirt_id, {"color": "3a6ea5"}).get("color", "3a6ea5"))
	var acc := []
	match str(eq.get("hat", "")):
		"hat_cap":
			acc.append("cap")
		"hat_top":
			acc.append("top_hat")
		"hat_cowboy":
			acc.append("cowboy")
		"hat_beanie":
			acc.append("beanie")
	match str(eq.get("glasses", "")):
		"glasses_round":
			acc.append("glasses")
		"glasses_sun":
			acc.append("sunglasses")
	match str(eq.get("tie", "")):
		"tie_red":
			acc.append("tie")
		"tie_bow":
			acc.append("bowtie")
		"tie_gold":
			acc.append("tie_gold")
	if Save.data["upgrades_owned"].has("auriculares") and not acc.has("cap") and not acc.has("top_hat") and not acc.has("cowboy"):
		acc.append("headphones")
	return {"skin": "e8b48a", "body": "avg", "hair": hair, "hair_color": "3b2416", "shirt": shirt_col, "pants": "2a2f3a", "acc": acc}


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	preview = SubViewport.new()
	preview.own_world_3d = true
	preview.size = Vector2i(460, 560)
	add_child(preview)
	var w := Node3D.new()
	preview.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2b3550")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-30, 25, 0)
	w.add_child(l)
	model = CharacterModel.new()
	w.add_child(model)
	model.build(player_look(), 7)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.15, 3.3)
	cam.fov = 40
	w.add_child(cam)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var h := UIKit.hbox(20)
	margin.add_child(h)
	var tr := TextureRect.new()
	tr.texture = preview.get_texture()
	tr.custom_minimum_size = Vector2(400, 0)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(tr)
	var v := UIKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var top := UIKit.hbox(10)
	var t := UIKit.label(Loc.t("customize"), 32, UIKit.C_ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	money_label = UIKit.label("", 22)
	top.add_child(money_label)
	top.add_child(UIKit.button(Loc.t("close"), func() -> void:
		closed.emit()
		queue_free(), UIKit.C_PANEL2, 60, 22))
	v.add_child(top)
	var tabs := UIKit.hbox(8)
	for s in [["hair", "Pelo"], ["shirt", "Camisa"], ["hat", "Sombrero"], ["glasses", "Gafas"], ["tie", "Corbata"]]:
		var b := UIKit.button(s[1], func() -> void:
			slot = s[0]
			_refresh(), UIKit.C_PANEL2, 56, 20)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
	v.add_child(tabs)
	list_box = UIKit.vbox(8)
	v.add_child(UIKit.scroll(list_box))
	_refresh()


func _refresh() -> void:
	money_label.text = "Saldo: " + UIKit.money(int(Save.data["money"]))
	for c in list_box.get_children():
		c.queue_free()
	var eq: Dictionary = Save.data["equipped"]
	for id in UpgradeDB.COSMETICS.keys():
		var cdef: Dictionary = UpgradeDB.COSMETICS[id]
		if cdef["slot"] != slot:
			continue
		var owned: bool = Save.data["cosmetics_owned"].has(id)
		var equipped: bool = eq.get(slot, "") == id
		var row := UIKit.panel(UIKit.C_PANEL2, 12, 10)
		var h := UIKit.hbox(10)
		row.add_child(h)
		var l := UIKit.label("%s  %s" % [cdef["name"], "" if owned else "— " + UIKit.money(int(cdef["cost"]))], 22)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var b: Button
		if owned:
			b = UIKit.button(Loc.t("equipped") if equipped else Loc.t("equip"), func() -> void:
				Game.equip_cosmetic(id)
				_apply(), UIKit.C_GOOD if equipped else UIKit.C_ACCENT, 56, 20)
		else:
			b = UIKit.button(Loc.t("buy"), func() -> void:
				var r := Game.buy_cosmetic(id)
				if r["ok"]:
					Audio.play("cash")
					Game.equip_cosmetic(id)
					_apply()
				else:
					Audio.play("error")
					money_label.text = r["why"], UIKit.C_BLUE, 56, 20)
		b.custom_minimum_size = Vector2(160, 56)
		h.add_child(b)
		list_box.add_child(row)


func _apply() -> void:
	model.build(player_look(), 7)
	model.play_gesture("wave")
	_refresh()


func _process(delta: float) -> void:
	if model:
		model.rotation.y += delta * 0.6
