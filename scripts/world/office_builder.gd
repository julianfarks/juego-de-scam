class_name OfficeBuilder
extends RefCounted
## Construye la oficina de TeleTimo por código: zona de trabajo, despacho acristalado
## del jefe, sala de descanso, tablón de objetivos, ventanas con ciudad, decoración y
## colisiones. Geometría low-poly con materiales compartidos (barato en móvil).

const W := 12.0   # medio ancho (x)
const D := 8.0    # medio fondo (z)
const H := 3.0

var root: Node3D
var refs := {
	"interactables": [], "coworker_seats": [], "player_spawn": Vector3(-6, 0, 5), "monitors": [],
	"waypoints": {}, "deco_slots": [],
}


static func m(hex: String, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	return CharacterModel.mat(hex, rough, metal)


static func emissive(hex: String, energy := 1.5) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(hex)
	mt.emission_enabled = true
	mt.emission = Color(hex)
	mt.emission_energy_multiplier = energy
	return mt


func box_at(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, collide := false, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = CharacterModel.box(size)
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	if collide:
		add_collider(parent, size, pos, rot_y)
	return mi


func add_collider(parent: Node3D, size: Vector3, pos: Vector3, rot_y := 0.0) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	body.position = pos
	body.rotation.y = rot_y
	parent.add_child(body)


func mesh_at(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func label3d(parent: Node3D, text: String, pos: Vector3, size := 48, color := Color.WHITE, rot_y := 0.0, outline := 8) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.005
	l.modulate = color
	l.outline_size = outline
	l.position = pos
	l.rotation.y = rot_y
	l.double_sided = false
	parent.add_child(l)
	return l


func add_interactable(node: Node3D, kind: String, label: String, radius := 1.6, data: Dictionary = {}) -> void:
	refs["interactables"].append({"node": node, "kind": kind, "label": label, "radius": radius, "data": data})


func build(parent: Node3D, quality: int) -> Dictionary:
	root = Node3D.new()
	root.name = "Office"
	parent.add_child(root)
	_environment(quality)
	_shell()
	_windows_and_city()
	_work_area()
	_boss_office()
	_break_room()
	_board_and_wall_details()
	_plants_and_props(quality)
	refs["waypoints"] = {
		"boss_desk": Vector3(9.5, 0, -5.5), "boss_door": Vector3(6.5, 0, -1.2), "aisle_w": Vector3(-6, 0, 0.3),
		"aisle_e": Vector3(4.5, 0, 0.3), "coffee": Vector3(8.6, 0, 5.2), "board": Vector3(-3, 0, -6.6),
		"player_desk": Vector3(-8.0, 0, 4.0), "cooler": Vector3(11.0, 0, 3.4),
	}
	return refs


func _environment(quality: int) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9ec9e8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff1dd")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	if quality >= 2:
		env.glow_enabled = true
		env.glow_intensity = 0.4
		env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -60, 0)
	sun.light_energy = 1.05
	sun.light_color = Color("fff4e0")
	sun.shadow_enabled = quality >= 1
	sun.directional_shadow_max_distance = 26.0 if quality >= 2 else 18.0
	sun.shadow_blur = 1.5
	root.add_child(sun)
	if quality >= 2:
		for p in [Vector3(-4, 2.6, 0), Vector3(8.5, 2.6, -5)]:
			var o := OmniLight3D.new()
			o.position = p
			o.omni_range = 7.0
			o.light_energy = 0.6
			o.light_color = Color("ffe9c4")
			root.add_child(o)


func _shell() -> void:
	# Suelo de moqueta con pasillo
	box_at(root, Vector3(W * 2, 0.2, D * 2), Vector3(0, -0.1, 0), m("5d6b82"), true)
	box_at(root, Vector3(W * 2 - 0.4, 0.02, 1.6), Vector3(0, 0.005, 0.3), m("7a869c"))
	box_at(root, Vector3(6, 0.02, 6), Vector3(9, 0.006, 5), m("c9a27a"))   # parqué zona descanso
	var wall := m("efe6d4")
	var trim := m("c9b99c")
	# Paredes con zócalo (norte, sur, este; oeste tiene ventanas)
	box_at(root, Vector3(W * 2, H, 0.3), Vector3(0, H / 2, -D), wall, true)
	box_at(root, Vector3(W * 2, H, 0.3), Vector3(0, H / 2, D), wall, true)
	box_at(root, Vector3(0.3, H, D * 2), Vector3(W, H / 2, 0), wall, true)
	box_at(root, Vector3(W * 2, 0.15, 0.32), Vector3(0, 0.075, -D + 0.01), trim)
	box_at(root, Vector3(W * 2, 0.15, 0.32), Vector3(0, 0.075, D - 0.01), trim)
	# Puerta de entrada (sur)
	box_at(root, Vector3(1.4, 2.3, 0.1), Vector3(-1.5, 1.15, D - 0.2), m("8b5e3c"))
	mesh_at(root, CharacterModel.sphere(0.05), Vector3(-1.0, 1.1, D - 0.28), m("e0b030", 0.3, 0.8))
	label3d(root, "SALIDA (prohibido rendirse)", Vector3(-1.5, 2.55, D - 0.17), 36, Color("ffdddd"), PI)
	# Lámparas de techo (emisivas, sin coste de luz)
	var lamp := emissive("fff6e0", 2.0)
	for x in [-8.0, -4.0, 0.0, 4.0]:
		for z in [-3.0, 3.0]:
			box_at(root, Vector3(1.6, 0.06, 0.5), Vector3(x, H - 0.1, z), lamp)
			box_at(root, Vector3(0.02, 0.4, 0.02), Vector3(x, H + 0.1, z), m("888888"))


func _windows_and_city() -> void:
	var frame := m("dfe3e8", 0.4, 0.3)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.88, 1.0, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	# Pared oeste: base, dintel y columnas entre ventanales
	box_at(root, Vector3(0.3, 0.8, D * 2), Vector3(-W, 0.4, 0), m("efe6d4"), true)
	box_at(root, Vector3(0.3, 0.5, D * 2), Vector3(-W, H - 0.25, 0), m("efe6d4"))
	for z in range(-8, 9, 4):
		box_at(root, Vector3(0.32, H, 0.25), Vector3(-W, H / 2, z), frame, true)
	box_at(root, Vector3(0.05, 1.7, D * 2), Vector3(-W, 1.65, 0), glass, true)
	# Ciudad de fondo (cartón piedra con ventanas iluminadas)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var bmat := [m("7f8fa6"), m("95a5b8"), m("6c7a8f"), m("a7b4c4")]
	var wmat := emissive("ffe8a3", 0.8)
	for i in 16:
		var hgt := rng.randf_range(4.0, 14.0)
		var z := -10.0 + i * 1.6 + rng.randf_range(-0.3, 0.3)
		var x := -W - rng.randf_range(6.0, 16.0)
		var wdt := rng.randf_range(1.6, 3.2)
		box_at(root, Vector3(wdt, hgt, wdt), Vector3(x, hgt / 2 - 2.0, z), bmat[i % 4])
		for k in 4:
			box_at(root, Vector3(0.05, 0.35, 0.5), Vector3(x + wdt / 2 + 0.03, rng.randf_range(0.5, hgt - 2.5), z + rng.randf_range(-wdt / 3, wdt / 3)), wmat)
	box_at(root, Vector3(40, 0.2, 40), Vector3(-W - 14, -2.2, 0), m("8aa07a"))


func _desk(pos: Vector3, rot_y: float, is_player := false) -> Dictionary:
	var desk := Node3D.new()
	desk.position = pos
	desk.rotation.y = rot_y
	root.add_child(desk)
	var wood := m("b5835a")
	var metal := m("6e7480", 0.4, 0.5)
	box_at(desk, Vector3(1.6, 0.06, 0.8), Vector3(0, 0.75, 0), wood)
	for x in [-0.75, 0.75]:
		box_at(desk, Vector3(0.05, 0.75, 0.75), Vector3(x, 0.375, 0), metal)
	box_at(desk, Vector3(1.5, 0.5, 0.03), Vector3(0, 0.45, -0.38), m("8a6040"))
	add_collider(root, Vector3(1.7, 1.0, 0.9), pos + Vector3(0, 0.5, 0).rotated(Vector3.UP, rot_y))
	# Separador de cubículo
	box_at(desk, Vector3(1.7, 0.5, 0.05), Vector3(0, 1.0, -0.43), m("7b8fa8"))
	# Monitor
	var mon := Node3D.new()
	mon.position = Vector3(0, 0.78, -0.2)
	desk.add_child(mon)
	box_at(mon, Vector3(0.62, 0.4, 0.04), Vector3(0, 0.32, 0), m("22252b", 0.4))
	var screen_mat := emissive("3a7bd5" if not is_player else "2ec4b6", 1.2)
	var screen := box_at(mon, Vector3(0.56, 0.34, 0.01), Vector3(0, 0.32, 0.022), screen_mat)
	box_at(mon, Vector3(0.06, 0.12, 0.06), Vector3(0, 0.06, 0), m("22252b"))
	box_at(mon, Vector3(0.25, 0.02, 0.18), Vector3(0, 0.0, 0), m("22252b"))
	refs["monitors"].append(screen)
	# Teclado y ratón
	box_at(desk, Vector3(0.45, 0.025, 0.15), Vector3(0, 0.79, 0.12), m("2b2d33"))
	box_at(desk, Vector3(0.06, 0.025, 0.1), Vector3(0.35, 0.79, 0.12), m("2b2d33"))
	# Teléfono de sobremesa
	var phone := Node3D.new()
	phone.position = Vector3(-0.55, 0.79, 0.0)
	desk.add_child(phone)
	box_at(phone, Vector3(0.22, 0.06, 0.18), Vector3(0, 0.03, 0), m("e9e9ee" if not is_player else "f2c12e", 0.3))
	box_at(phone, Vector3(0.24, 0.05, 0.07), Vector3(0, 0.085, -0.04), m("33363d", 0.3))
	# Silla
	var chair := Node3D.new()
	chair.position = Vector3(0, 0, 0.75)
	desk.add_child(chair)
	var chair_m := m("2d3e50") if not is_player else m("c0392b")
	box_at(chair, Vector3(0.5, 0.08, 0.5), Vector3(0, 0.48, 0), chair_m)
	box_at(chair, Vector3(0.5, 0.6, 0.08), Vector3(0, 0.82, 0.24), chair_m)
	box_at(chair, Vector3(0.05, 0.45, 0.05), Vector3(0, 0.22, 0), metal)
	mesh_at(chair, CharacterModel.cylinder(0.3, 0.3, 0.04, 5), Vector3(0, 0.03, 0), metal)
	# Cosas sobre la mesa
	mesh_at(desk, CharacterModel.cylinder(0.04, 0.035, 0.1), Vector3(0.55, 0.83, -0.05), m(["e63946", "f4a261", "2a9d8f", "ffffff"][randi() % 4]))
	box_at(desk, Vector3(0.21, 0.01, 0.3), Vector3(0.3, 0.785, -0.15), m("fafafa"), false, 0.2)
	return {"node": desk, "phone": phone, "monitor": mon, "screen": screen, "chair": chair}


func _work_area() -> void:
	var cols := [-8.0, -4.0, 0.0, 4.0]
	var rows := [-3.6, 3.6]
	for r in rows:
		for c in cols:
			var pos := Vector3(c, 0, r)
			var is_player: bool = (c == -8.0 and r == 3.6)
			var desk := _desk(pos, 0.0, is_player)
			if is_player:
				refs["player_desk"] = desk
				refs["player_spawn"] = pos + Vector3(0.6, 0, 1.6)
				add_interactable(desk["phone"], "phone", "Teléfono", 1.7)
				add_interactable(desk["monitor"], "computer", "Ordenador", 1.7)
				var nameplate := label3d(desk["node"], "TÚ (novato)", Vector3(0, 1.32, -0.4), 40, Color("ffe066"))
				nameplate.billboard = BaseMaterial3D.BILLBOARD_DISABLED
				refs["player_screen_label"] = label3d(desk["monitor"], "TimoOS", Vector3(0, 0.33, 0.03), 28, Color.WHITE, 0.0, 4)
				refs["deco_slots"] = [desk["node"].to_global(Vector3(0.7, 0.78, -0.3)), desk["node"].to_global(Vector3(-0.2, 0.78, -0.3)), desk["node"].to_global(Vector3(-0.75, 1.25, -0.43)), desk["node"].to_global(Vector3(0.45, 0.78, 0.25))]
				refs["deco_parent"] = root
			else:
				refs["coworker_seats"].append({"pos": pos + Vector3(0, 0, 0.75), "rot": PI, "desk": desk})


func _boss_office() -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.9, 1.0, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	var frame := m("4a4f5a", 0.4, 0.4)
	# Paredes de cristal: x=6.5 (con puerta) y z=-2
	box_at(root, Vector3(0.06, H, 4.0), Vector3(6.5, H / 2, -6.0), glass, true)
	box_at(root, Vector3(4.0, H, 0.06), Vector3(10.0, H / 2, -2.0), glass, true)
	box_at(root, Vector3(1.0, H, 0.06), Vector3(7.0, H / 2, -2.0), glass, true)
	for p in [Vector3(6.5, H / 2, -8), Vector3(6.5, H / 2, -4), Vector3(6.5, H / 2, -2), Vector3(8, H / 2, -2), Vector3(12, H / 2, -2)]:
		box_at(root, Vector3(0.1, H, 0.1), p, frame)
	box_at(root, Vector3(5.5, 0.08, 6.0), Vector3(9.25, H, -5.0), frame)
	label3d(root, "DIRECCIÓN", Vector3(9.8, 2.6, -1.95), 64, Color("ffd166"))
	box_at(root, Vector3(5.5, 0.02, 6.0), Vector3(9.25, 0.007, -5.0), m("6b2737"))
	# Mesa del jefe, sillón, teléfono dorado y cuadro
	var desk := Node3D.new()
	desk.position = Vector3(9.5, 0, -6.4)
	root.add_child(desk)
	box_at(desk, Vector3(2.4, 0.1, 1.0), Vector3(0, 0.78, 0), m("5c3a21", 0.4))
	box_at(desk, Vector3(2.3, 0.75, 0.9), Vector3(0, 0.37, 0), m("4a2e1a", 0.5))
	add_collider(root, Vector3(2.5, 1.0, 1.1), Vector3(9.5, 0.5, -6.4))
	box_at(desk, Vector3(0.24, 0.07, 0.2), Vector3(-0.8, 0.86, 0.1), m("e0b030", 0.25, 0.9))
	box_at(desk, Vector3(0.7, 1.2, 0.3), Vector3(0, 1.0, -0.9), m("7a1f2b"))
	label3d(desk, "$", Vector3(0.6, 0.95, 0.2), 120, Color("2ecc71"))
	box_at(root, Vector3(1.4, 1.0, 0.05), Vector3(9.5, 2.0, -7.83), m("e0b030", 0.3, 0.7))
	box_at(root, Vector3(1.25, 0.85, 0.02), Vector3(9.5, 2.0, -7.8), m("35424f"))
	label3d(root, "EMPLEADO DEL MES:\nYO MISMO", Vector3(9.5, 2.0, -7.78), 30, Color("ffd166"))
	mesh_at(root, CharacterModel.cylinder(0.25, 0.2, 0.4), Vector3(11.3, 0.2, -7.3), m("8b5e3c"))
	mesh_at(root, CharacterModel.sphere(0.45), Vector3(11.3, 0.8, -7.3), m("2e7d32"), Vector3(1, 1.3, 1))
	add_interactable(desk, "boss_desk", "Despacho del jefe", 2.2)


func _break_room() -> void:
	var base := Vector3(9, 0, 5)
	# Sofá
	var sofa_m := m("e76f51")
	box_at(root, Vector3(2.4, 0.45, 0.9), Vector3(9.5, 0.23, 7.2), sofa_m, true)
	box_at(root, Vector3(2.4, 0.6, 0.25), Vector3(9.5, 0.7, 7.55), sofa_m)
	box_at(root, Vector3(0.25, 0.65, 0.9), Vector3(8.3, 0.45, 7.2), sofa_m)
	box_at(root, Vector3(0.25, 0.65, 0.9), Vector3(10.7, 0.45, 7.2), sofa_m)
	box_at(root, Vector3(1.2, 0.4, 0.6), Vector3(9.5, 0.2, 5.9), m("8b5e3c"), true)
	# Cafetera
	var coffee := Node3D.new()
	coffee.position = Vector3(8.6, 0, 4.2)
	root.add_child(coffee)
	box_at(coffee, Vector3(1.4, 0.9, 0.6), Vector3(0, 0.45, 0), m("d8d2c4"))
	box_at(coffee, Vector3(0.5, 0.6, 0.45), Vector3(0, 1.2, 0), m("2b2d33", 0.3, 0.5))
	box_at(coffee, Vector3(0.3, 0.1, 0.02), Vector3(0, 1.3, 0.23), emissive("ff6b35", 1.5))
	mesh_at(coffee, CharacterModel.cylinder(0.04, 0.035, 0.09), Vector3(0, 0.95, 0.1), m("ffffff"))
	add_collider(root, Vector3(1.4, 1.5, 0.6), coffee.position + Vector3(0, 0.75, 0))
	add_interactable(coffee, "coffee", "Cafetera", 1.6)
	# Dispensador de agua
	var cooler := Node3D.new()
	cooler.position = Vector3(11.4, 0, 3.0)
	root.add_child(cooler)
	box_at(cooler, Vector3(0.4, 1.0, 0.4), Vector3(0, 0.5, 0), m("e9ecef"))
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.5, 0.75, 1.0, 0.6)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_at(cooler, CharacterModel.cylinder(0.16, 0.16, 0.45), Vector3(0, 1.22, 0), water)
	add_collider(root, Vector3(0.5, 1.5, 0.5), cooler.position + Vector3(0, 0.75, 0))
	add_interactable(cooler, "cooler", "Dispensador de agua", 1.4)
	# Nevera
	box_at(root, Vector3(0.8, 1.9, 0.7), Vector3(11.4, 0.95, 5.0), m("f8f9fa", 0.3), true)
	box_at(root, Vector3(0.04, 0.4, 0.04), Vector3(11.0, 1.2, 4.62), m("888888"))
	# Mesa de la pizza (para el evento)
	var pizza := Node3D.new()
	pizza.position = Vector3(7.2, 0, 6.6)
	root.add_child(pizza)
	box_at(pizza, Vector3(0.9, 0.05, 0.9), Vector3(0, 0.72, 0), m("b5835a"))
	box_at(pizza, Vector3(0.06, 0.72, 0.06), Vector3(0, 0.36, 0), m("6e7480"))
	var box_p := box_at(pizza, Vector3(0.5, 0.06, 0.5), Vector3(0, 0.78, 0), m("c9a27a"))
	var pz := mesh_at(pizza, CharacterModel.cylinder(0.22, 0.22, 0.03, 10), Vector3(0, 0.83, 0), m("f4a261"))
	box_p.visible = false
	pz.visible = false
	refs["pizza_meshes"] = [box_p, pz]
	refs["pizza_node"] = pizza
	label3d(root, "ZONA DE DESCANSO\n(máx. 3 minutos)", Vector3(9.0, 2.5, 7.83), 40, Color("2b2d42"), PI, 0)


func _board_and_wall_details() -> void:
	# Tablón de objetivos (se actualiza en tiempo real)
	var board := Node3D.new()
	board.position = Vector3(-3, 0, -7.8)
	root.add_child(board)
	box_at(board, Vector3(3.6, 1.8, 0.08), Vector3(0, 1.7, 0), m("2f3e46"))
	box_at(board, Vector3(3.8, 0.1, 0.12), Vector3(0, 0.78, 0.02), m("8b5e3c"))
	refs["board_label"] = label3d(board, "OBJETIVOS", Vector3(0, 1.75, 0.06), 44, Color("f1faee"), 0.0, 0)
	add_interactable(board, "board", "Tablón de objetivos", 2.2)
	# Reloj de pared
	mesh_at(root, CharacterModel.cylinder(0.35, 0.35, 0.05, 20), Vector3(2.5, 2.3, -7.82), m("ffffff"), Vector3.ONE, Vector3(PI / 2, 0, 0))
	refs["clock_label"] = label3d(root, "09:00", Vector3(2.5, 2.3, -7.78), 50, Color("1b1b22"), 0.0, 0)
	# Pósteres motivacionales (originales)
	var posters := [["¡VENDE HUMO,\nCOBRA NUBES!", "e63946", Vector3(-8, 1.8, -7.83)], ["EL CLIENTE\nSIEMPRE PAGA\n(casi)", "2a9d8f", Vector3(6.0, 1.8, 7.83)], ["CUOTA > SUEÑO", "f4a261", Vector3(-7.0, 1.8, 7.83)], ["SONRÍE:\nTE OYEN\nSONREÍR", "8338ec", Vector3(-11.83, 0, 0)]]
	for p in posters:
		var pos: Vector3 = p[2]
		if pos.x < -11:
			continue
		var rot := 0.0 if pos.z < 0 else PI
		box_at(root, Vector3(1.2, 1.4, 0.03), pos, m(p[1]), false, rot)
		label3d(root, p[0], pos + Vector3(0, 0, 0.03 if pos.z < 0 else -0.03), 34, Color.WHITE, rot, 0)
	# Archivadores y fotocopiadora
	for i in 3:
		box_at(root, Vector3(0.5, 1.3, 0.6), Vector3(-11.4 + i * 0.55, 0.65, -7.4), m("8d99ae", 0.4, 0.4), true)
	var printer := Node3D.new()
	printer.position = Vector3(2.0, 0, 6.9)
	root.add_child(printer)
	box_at(printer, Vector3(0.9, 0.9, 0.7), Vector3(0, 0.45, 0), m("dee2e6"))
	box_at(printer, Vector3(0.7, 0.05, 0.4), Vector3(0, 0.93, 0.05), m("adb5bd"))
	box_at(printer, Vector3(0.2, 0.06, 0.02), Vector3(0.25, 0.8, 0.36), emissive("06d6a0", 1.0))
	add_collider(root, Vector3(0.9, 1.0, 0.7), printer.position + Vector3(0, 0.5, 0))
	add_interactable(printer, "printer", "Fotocopiadora", 1.4)


func _plants_and_props(quality: int) -> void:
	var pot := m("b5651d")
	var leaf := m("2e7d32")
	var leaf2 := m("43a047")
	var spots := [Vector3(-11.3, 0, 7.3), Vector3(-11.3, 0, -3.5), Vector3(5.8, 0, -7.3), Vector3(5.8, 0, 7.3), Vector3(-2.0, 0, 7.3), Vector3(11.3, 0, 7.3)]
	if quality == 0:
		spots = spots.slice(0, 3)
	for i in spots.size():
		var p: Vector3 = spots[i]
		mesh_at(root, CharacterModel.cylinder(0.22, 0.17, 0.4), p + Vector3(0, 0.2, 0), pot)
		for k in 3:
			mesh_at(root, CharacterModel.sphere(0.28), p + Vector3(sin(k * 2.1) * 0.12, 0.65 + k * 0.22, cos(k * 2.1) * 0.12), leaf if k % 2 == 0 else leaf2)
		add_collider(root, Vector3(0.5, 1.2, 0.5), p + Vector3(0, 0.6, 0))
	add_interactable(root.get_child(root.get_child_count() - 1) as Node3D, "plant", "Planta motivadora", 1.2)
	# Papeleras
	for p in [Vector3(-6.9, 0, 4.2), Vector3(1.1, 0, -2.9), Vector3(5.2, 0, 4.2)]:
		mesh_at(root, CharacterModel.cylinder(0.15, 0.12, 0.35), p + Vector3(0, 0.17, 0), m("6c757d", 0.5, 0.4))
