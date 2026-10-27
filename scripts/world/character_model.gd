class_name CharacterModel
extends Node3D
## Personaje cartoon low-poly construido por código: silueta según el tipo de
## cuerpo, peinados, ropa y accesorios distintos, cara expresiva (cejas, párpados,
## boca con comisuras, mejillas) y animación procedural: respirar, parpadear,
## caminar, sentarse a teclear, hablar por teléfono, emociones y gestos.

const SKIN_DEFAULT := "f1c7a3"

var look: Dictionary = {}
var state := "idle"            # idle | walk | sit | phone | sit_phone
var emotion := "neutral"
var talk_amount := 0.0         # 0..1, lo controla quien habla
var walk_speed := 0.0
var look_yaw := 0.0
var _gesture := ""
var _gesture_t := 0.0
var _t := 0.0
var _blink_t := 2.0
var _blink := 0.0
var _seed := 0.0
var _emotion_blend := {}

var hips: Node3D
var torso: Node3D
var head_pivot: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var fore_l: Node3D
var fore_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var brow_l: MeshInstance3D
var brow_r: MeshInstance3D
var lid_l: MeshInstance3D
var lid_r: MeshInstance3D
var eye_l: Node3D
var eye_r: Node3D
var mouth: MeshInstance3D
var corner_l: MeshInstance3D
var corner_r: MeshInstance3D
var cheek_l: MeshInstance3D
var cheek_r: MeshInstance3D
var phone_mesh: Node3D
var skin_mat: StandardMaterial3D
var body_scale := Vector3.ONE
var height_scale := 1.0

static var _mat_cache: Dictionary = {}


static func mat(hex: String, rough := 0.85, metallic := 0.0, emission := false) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f_%s" % [hex, rough, metallic, emission]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = rough
	m.metallic = metallic
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	if emission:
		m.emission_enabled = true
		m.emission = Color(hex)
		m.emission_energy_multiplier = 1.2
	_mat_cache[key] = m
	return m


func _mesh(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func sphere(r := 0.5, seg := 12) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = seg / 2
	return s


static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 4
	return c


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cylinder(top: float, bottom: float, h: float, seg := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	return c


func build(p_look: Dictionary, seed_v := 0) -> void:
	for ch in get_children():
		ch.queue_free()
	look = p_look
	_seed = float(seed_v % 1000) * 0.37
	var skin := str(look.get("skin", SKIN_DEFAULT))
	skin_mat = mat(skin).duplicate()
	var shirt := mat(str(look.get("shirt", "3a6ea5")))
	var pants := mat(str(look.get("pants", "2a2f3a")))
	var hair_m := mat(str(look.get("hair_color", "3a2a1a")), 0.6)
	var shoe := mat("2a1d14", 0.5)
	var dark := mat("1b1b22", 0.4)
	var white := mat("ffffff", 0.3)
	var body := str(look.get("body", "avg"))
	var width := 1.0
	height_scale = 1.0
	match body:
		"thin":
			width = 0.82
		"wide":
			width = 1.32
		"tall":
			height_scale = 1.12
			width = 0.95
		"short":
			height_scale = 0.86
			width = 1.05
	scale = Vector3.ONE * height_scale

	hips = Node3D.new()
	hips.position = Vector3(0, 0.82, 0)
	add_child(hips)
	# Piernas
	leg_l = Node3D.new()
	leg_l.position = Vector3(-0.11 * width, 0, 0)
	hips.add_child(leg_l)
	leg_r = Node3D.new()
	leg_r.position = Vector3(0.11 * width, 0, 0)
	hips.add_child(leg_r)
	for leg in [leg_l, leg_r]:
		_mesh(leg, capsule(0.075 * width, 0.45), pants, Vector3(0, -0.2, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.4, 0)
		leg.add_child(knee)
		_mesh(knee, capsule(0.07 * width, 0.42), pants, Vector3(0, -0.18, 0))
		_mesh(knee, box(Vector3(0.13, 0.08, 0.24)), shoe, Vector3(0, -0.38, 0.04))
		if leg == leg_l:
			knee_l = knee
		else:
			knee_r = knee
	# Torso
	torso = Node3D.new()
	torso.position = Vector3(0, 0.05, 0)
	hips.add_child(torso)
	_mesh(torso, capsule(0.2, 0.62), shirt, Vector3(0, 0.27, 0), Vector3(width, 1.0, 0.75 + 0.1 * (width - 1.0)))
	if body == "wide":
		_mesh(torso, sphere(0.22), shirt, Vector3(0, 0.15, 0.07), Vector3(1.25, 1.0, 1.0))
	_mesh(torso, capsule(0.17, 0.3), pants, Vector3(0, 0.0, 0), Vector3(width, 0.6, 0.78))
	# Cuello y cabeza (cabeza grande: proporciones cartoon)
	_mesh(torso, cylinder(0.06, 0.07, 0.1), skin_mat, Vector3(0, 0.6, 0))
	head_pivot = Node3D.new()
	head_pivot.position = Vector3(0, 0.64, 0)
	torso.add_child(head_pivot)
	head = Node3D.new()
	head.position = Vector3(0, 0.2, 0)
	head_pivot.add_child(head)
	_mesh(head, sphere(0.2, 16), skin_mat, Vector3.ZERO, Vector3(1.0, 1.08, 0.98))
	_mesh(head, sphere(0.045), skin_mat, Vector3(-0.2, 0.0, 0), Vector3(0.6, 1.0, 1.0))
	_mesh(head, sphere(0.045), skin_mat, Vector3(0.2, 0.0, 0), Vector3(0.6, 1.0, 1.0))
	_mesh(head, sphere(0.045), skin_mat, Vector3(0, -0.01, 0.2), Vector3(0.9, 0.8, 1.0))  # nariz
	# Ojos
	eye_l = Node3D.new()
	eye_l.position = Vector3(-0.075, 0.045, 0.165)
	head.add_child(eye_l)
	eye_r = Node3D.new()
	eye_r.position = Vector3(0.075, 0.045, 0.165)
	head.add_child(eye_r)
	for eye in [eye_l, eye_r]:
		_mesh(eye, sphere(0.045), white, Vector3.ZERO, Vector3(1.0, 1.15, 0.6))
		_mesh(eye, sphere(0.024), dark, Vector3(0, 0, 0.022), Vector3(1.0, 1.1, 0.6))
	lid_l = _mesh(eye_l, sphere(0.05), skin_mat, Vector3(0, 0.06, 0.005), Vector3(1.05, 0.3, 0.75))
	lid_r = _mesh(eye_r, sphere(0.05), skin_mat, Vector3(0, 0.06, 0.005), Vector3(1.05, 0.3, 0.75))
	var brow_col := hair_m if str(look.get("hair", "short")) != "bald" else mat("6a5a4a")
	brow_l = _mesh(head, box(Vector3(0.075, 0.018, 0.02)), brow_col, Vector3(-0.075, 0.115, 0.18))
	brow_r = _mesh(head, box(Vector3(0.075, 0.018, 0.02)), brow_col, Vector3(0.075, 0.115, 0.18))
	# Boca con comisuras para sonreír o fruncir
	var mouth_m := mat("5a1f24", 0.6)
	mouth = _mesh(head, box(Vector3(0.07, 0.02, 0.02)), mouth_m, Vector3(0, -0.085, 0.185))
	corner_l = _mesh(head, box(Vector3(0.03, 0.014, 0.018)), mouth_m, Vector3(-0.045, -0.08, 0.18))
	corner_r = _mesh(head, box(Vector3(0.03, 0.014, 0.018)), mouth_m, Vector3(0.045, -0.08, 0.18))
	var blush := StandardMaterial3D.new()
	blush.albedo_color = Color(1.0, 0.45, 0.45, 0.0)
	blush.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blush.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cheek_l = _mesh(head, sphere(0.035), blush, Vector3(-0.115, -0.03, 0.15), Vector3(1.0, 0.6, 0.4))
	cheek_r = _mesh(head, sphere(0.035), blush, Vector3(0.115, -0.03, 0.15), Vector3(1.0, 0.6, 0.4))
	cheek_r.material_override = blush
	# Brazos
	arm_l = Node3D.new()
	arm_l.position = Vector3(-0.24 * width, 0.5, 0)
	torso.add_child(arm_l)
	arm_r = Node3D.new()
	arm_r.position = Vector3(0.24 * width, 0.5, 0)
	torso.add_child(arm_r)
	for arm in [arm_l, arm_r]:
		_mesh(arm, capsule(0.058, 0.32), shirt, Vector3(0, -0.13, 0))
		var fore := Node3D.new()
		fore.position = Vector3(0, -0.28, 0)
		arm.add_child(fore)
		_mesh(fore, capsule(0.05, 0.28), skin_mat if look.get("short_sleeves", false) else shirt, Vector3(0, -0.11, 0))
		_mesh(fore, sphere(0.055), skin_mat, Vector3(0, -0.27, 0.0))
		if arm == arm_l:
			fore_l = fore
		else:
			fore_r = fore
	_build_hair(str(look.get("hair", "short")), hair_m)
	for acc in look.get("acc", []):
		_build_accessory(str(acc))
	# Móvil (visible al hablar por teléfono)
	phone_mesh = Node3D.new()
	fore_r.add_child(phone_mesh)
	phone_mesh.position = Vector3(0, -0.28, 0.05)
	_mesh(phone_mesh, box(Vector3(0.05, 0.11, 0.015)), dark, Vector3.ZERO)
	phone_mesh.visible = false


func _build_hair(style: String, m: StandardMaterial3D) -> void:
	var cap := func(sc: Vector3, off := Vector3(0, 0.05, -0.01)) -> MeshInstance3D:
		return _mesh(head, sphere(0.21, 14), m, off, sc)
	match style:
		"bald":
			_mesh(head, sphere(0.06), m, Vector3(-0.19, 0.0, -0.04), Vector3(0.5, 1.0, 1.4))
			_mesh(head, sphere(0.06), m, Vector3(0.19, 0.0, -0.04), Vector3(0.5, 1.0, 1.4))
		"short":
			cap.call(Vector3(1.04, 0.72, 1.03), Vector3(0, 0.08, -0.015))
		"slick":
			var s: MeshInstance3D = cap.call(Vector3(1.05, 0.66, 1.04), Vector3(0, 0.09, -0.02))
			s.material_override = mat(m.albedo_color.to_html(false), 0.2, 0.2)
		"messy":
			cap.call(Vector3(1.05, 0.75, 1.05), Vector3(0, 0.08, -0.01))
			for i in 7:
				var a := i * TAU / 7.0
				_mesh(head, sphere(0.06), m, Vector3(cos(a) * 0.12, 0.2 + sin(i * 1.7) * 0.02, sin(a) * 0.1 - 0.02))
		"long":
			cap.call(Vector3(1.07, 0.78, 1.06), Vector3(0, 0.07, -0.015))
			_mesh(head, box(Vector3(0.38, 0.42, 0.14)), m, Vector3(0, -0.12, -0.12))
			_mesh(head, box(Vector3(0.08, 0.32, 0.12)), m, Vector3(-0.19, -0.1, 0.0))
			_mesh(head, box(Vector3(0.08, 0.32, 0.12)), m, Vector3(0.19, -0.1, 0.0))
		"bob":
			cap.call(Vector3(1.1, 0.8, 1.08), Vector3(0, 0.06, -0.01))
			_mesh(head, sphere(0.2), m, Vector3(0, -0.05, -0.03), Vector3(1.18, 0.75, 1.05))
		"bun":
			cap.call(Vector3(1.04, 0.74, 1.03), Vector3(0, 0.08, -0.015))
			_mesh(head, sphere(0.09), m, Vector3(0, 0.2, -0.12))
		"ponytail":
			cap.call(Vector3(1.04, 0.74, 1.03), Vector3(0, 0.08, -0.015))
			var pt := _mesh(head, capsule(0.05, 0.3), m, Vector3(0, -0.02, -0.22), Vector3.ONE, Vector3(0.5, 0, 0))
			pt.name = "Ponytail"
		"pigtails":
			cap.call(Vector3(1.04, 0.74, 1.03), Vector3(0, 0.08, -0.015))
			_mesh(head, capsule(0.055, 0.22), m, Vector3(-0.22, -0.05, -0.03), Vector3.ONE, Vector3(0, 0, -0.4))
			_mesh(head, capsule(0.055, 0.22), m, Vector3(0.22, -0.05, -0.03), Vector3.ONE, Vector3(0, 0, 0.4))
		"space_buns":
			cap.call(Vector3(1.04, 0.74, 1.03), Vector3(0, 0.08, -0.015))
			_mesh(head, sphere(0.075), m, Vector3(-0.13, 0.19, -0.03))
			_mesh(head, sphere(0.075), m, Vector3(0.13, 0.19, -0.03))
		"curly":
			for i in 14:
				var a := i * TAU / 14.0
				var y := 0.1 + (i % 3) * 0.045
				_mesh(head, sphere(0.07), m, Vector3(cos(a) * 0.17, y, sin(a) * 0.15 - 0.03))
			_mesh(head, sphere(0.1), m, Vector3(0, 0.2, -0.02))
		"afro":
			_mesh(head, sphere(0.3, 14), m, Vector3(0, 0.12, -0.04), Vector3(1.0, 0.9, 0.95))
		"mohawk":
			_mesh(head, box(Vector3(0.05, 0.16, 0.34)), m, Vector3(0, 0.2, -0.02))
		_:
			cap.call(Vector3(1.04, 0.72, 1.03))


func _build_accessory(a: String) -> void:
	var dark := mat("15151a", 0.3)
	var gold := mat("e0b030", 0.3, 0.6)
	match a:
		"glasses":
			for x in [-0.075, 0.075]:
				var t := TorusMesh.new()
				t.inner_radius = 0.038
				t.outer_radius = 0.048
				t.rings = 12
				t.ring_segments = 6
				_mesh(head, t, dark, Vector3(x, 0.045, 0.2), Vector3.ONE, Vector3(PI / 2, 0, 0))
			_mesh(head, box(Vector3(0.05, 0.01, 0.01)), dark, Vector3(0, 0.05, 0.205))
		"sunglasses":
			_mesh(head, box(Vector3(0.11, 0.06, 0.02)), dark, Vector3(-0.075, 0.045, 0.205))
			_mesh(head, box(Vector3(0.11, 0.06, 0.02)), dark, Vector3(0.075, 0.045, 0.205))
			_mesh(head, box(Vector3(0.05, 0.012, 0.012)), dark, Vector3(0, 0.06, 0.205))
		"mustache":
			_mesh(head, capsule(0.022, 0.13), mat(str(look.get("hair_color", "3a2a1a"))), Vector3(0, -0.05, 0.195), Vector3.ONE, Vector3(0, 0, PI / 2))
		"beard":
			_mesh(head, sphere(0.15), mat(str(look.get("hair_color", "3a2a1a"))), Vector3(0, -0.11, 0.07), Vector3(1.0, 0.75, 0.8))
		"bowtie":
			_mesh(torso, box(Vector3(0.06, 0.05, 0.03)), mat("c0392b"), Vector3(-0.035, 0.56, 0.14), Vector3.ONE, Vector3(0, 0, 0.3))
			_mesh(torso, box(Vector3(0.06, 0.05, 0.03)), mat("c0392b"), Vector3(0.035, 0.56, 0.14), Vector3.ONE, Vector3(0, 0, -0.3))
		"tie":
			_mesh(torso, box(Vector3(0.05, 0.28, 0.02)), mat("8e1b2a"), Vector3(0, 0.42, 0.155))
		"tie_gold":
			_mesh(torso, box(Vector3(0.05, 0.28, 0.02)), gold, Vector3(0, 0.42, 0.155))
		"scarf":
			var t := TorusMesh.new()
			t.inner_radius = 0.07
			t.outer_radius = 0.12
			_mesh(torso, t, mat("e9c46a"), Vector3(0, 0.58, 0.0))
		"earrings":
			_mesh(head, sphere(0.018), gold, Vector3(-0.205, -0.05, 0))
			_mesh(head, sphere(0.018), gold, Vector3(0.205, -0.05, 0))
		"headphones":
			var t2 := TorusMesh.new()
			t2.inner_radius = 0.2
			t2.outer_radius = 0.23
			_mesh(head, t2, dark, Vector3(0, 0.05, 0), Vector3(1, 1, 0.6), Vector3(0, 0, PI / 2))
			_mesh(head, cylinder(0.06, 0.06, 0.05), mat("e63946"), Vector3(-0.21, 0, 0), Vector3.ONE, Vector3(0, 0, PI / 2))
			_mesh(head, cylinder(0.06, 0.06, 0.05), mat("e63946"), Vector3(0.21, 0, 0), Vector3.ONE, Vector3(0, 0, PI / 2))
		"watch":
			_mesh(fore_l if fore_l else torso, box(Vector3(0.07, 0.04, 0.07)), gold, Vector3(0, -0.2, 0))
		"cardigan":
			_mesh(torso, capsule(0.215, 0.6), mat("b08968"), Vector3(0, 0.27, -0.015), Vector3(1.0, 1.0, 0.72))
		"apron":
			_mesh(torso, box(Vector3(0.3, 0.45, 0.02)), mat("f1faee"), Vector3(0, 0.15, 0.16))
		"foil_hat":
			_mesh(head, cylinder(0.0, 0.17, 0.25, 8), mat("c0c0c8", 0.2, 1.0), Vector3(0, 0.3, 0))
		"cap":
			_mesh(head, sphere(0.215, 12), mat("e63946"), Vector3(0, 0.08, 0), Vector3(1.02, 0.6, 1.02))
			_mesh(head, box(Vector3(0.22, 0.02, 0.14)), mat("e63946"), Vector3(0, 0.1, 0.22))
		"top_hat":
			_mesh(head, cylinder(0.14, 0.14, 0.25), dark, Vector3(0, 0.33, 0))
			_mesh(head, cylinder(0.22, 0.22, 0.02), dark, Vector3(0, 0.2, 0))
		"beanie":
			_mesh(head, sphere(0.218, 12), mat("457b9d"), Vector3(0, 0.08, -0.01), Vector3(1.03, 0.75, 1.03))
		"medal":
			_mesh(torso, cylinder(0.05, 0.05, 0.015), gold, Vector3(0, 0.35, 0.16), Vector3.ONE, Vector3(PI / 2, 0, 0))
		"pencil":
			_mesh(head, cylinder(0.008, 0.008, 0.16), mat("f4d35e"), Vector3(0.21, 0.05, 0.02), Vector3.ONE, Vector3(0.3, 0, 1.2))
		"cane":
			_mesh(fore_l, cylinder(0.015, 0.015, 0.8), mat("6b4226"), Vector3(0, -0.6, 0.05))
		"flower":
			_mesh(head, sphere(0.045), mat("ff5d8f"), Vector3(0.16, 0.15, 0.06))
		"cowboy":
			_mesh(head, cylinder(0.13, 0.15, 0.16), mat("8b5a2b"), Vector3(0, 0.28, 0))
			_mesh(head, cylinder(0.3, 0.3, 0.02), mat("8b5a2b"), Vector3(0, 0.2, 0))


func set_emotion(e: String) -> void:
	emotion = e


func play_gesture(g: String) -> void:
	if g == "":
		return
	_gesture = g
	_gesture_t = 0.0


func set_phone(on: bool) -> void:
	if phone_mesh:
		phone_mesh.visible = on


func _process(delta: float) -> void:
	if hips == null:
		return
	_t += delta
	var t := _t + _seed
	# Parpadeo
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink = 1.0
		_blink_t = randf_range(2.0, 5.0)
	_blink = maxf(0.0, _blink - delta * 7.0)
	# Pose base según estado
	var la := Vector3.ZERO
	var ra := Vector3.ZERO
	var lf := Vector3.ZERO
	var rf := Vector3.ZERO
	var ll := Vector3.ZERO
	var rl := Vector3.ZERO
	var lk := Vector3.ZERO
	var rk := Vector3.ZERO
	var hip_y := 0.82
	var torso_rot := Vector3.ZERO
	var head_rot := Vector3(0, look_yaw, 0)
	var breath := sin(t * 2.0) * 0.012
	match state:
		"walk":
			var w := t * (6.0 + walk_speed * 2.0)
			var amp := clampf(walk_speed / 3.0, 0.3, 1.0)
			ll.x = sin(w) * 0.6 * amp
			rl.x = -sin(w) * 0.6 * amp
			lk.x = maxf(0.0, -sin(w)) * 0.7 * amp
			rk.x = maxf(0.0, sin(w)) * 0.7 * amp
			la.x = -sin(w) * 0.5 * amp
			ra.x = sin(w) * 0.5 * amp
			lf.x = -0.3
			rf.x = -0.3
			hip_y += absf(sin(w)) * 0.04 * amp
			torso_rot.y = sin(w) * 0.08 * amp
		"sit", "sit_phone":
			hip_y = 0.5
			ll.x = -1.45
			rl.x = -1.45
			lk.x = 1.45
			rk.x = 1.45
			la.x = -0.6
			ra.x = -0.6
			lf.x = -0.9
			rf.x = -0.9
			if state == "sit":
				# Teclear
				lf.x += sin(t * 14.0) * 0.08
				rf.x += sin(t * 13.0 + 1.0) * 0.08
				head_rot.x += 0.12
		_:
			la.z = 0.08 + sin(t * 1.3) * 0.02
			ra.z = -0.08 - sin(t * 1.3) * 0.02
			lf.x = -0.15
			rf.x = -0.15
			head_rot.y += sin(t * 0.5) * 0.15
			head_rot.x += sin(t * 0.7) * 0.04
	if state == "phone" or state == "sit_phone":
		ra = Vector3(-0.3, 0, -0.35)
		rf = Vector3(-2.3, 0, 0.1)
		head_rot.z += 0.12
	# Hablar: gestos con la mano libre y cabeza
	if talk_amount > 0.05:
		head_rot.x += sin(t * 9.0) * 0.04 * talk_amount
		la.x += -0.4 + sin(t * 3.0) * 0.3
		lf.x += -0.7 + sin(t * 4.3) * 0.3
		la.z += 0.2
	# Emociones
	var brow_tilt := 0.0
	var brow_h := 0.0
	var lid := 0.0
	var smile := 0.0
	var eye_scale := 1.0
	var blush := 0.0
	var tint := Color(1, 1, 1)
	match emotion:
		"happy":
			smile = 0.7
			brow_h = 0.01
			blush = 0.25
		"joy":
			smile = 1.0
			brow_h = 0.02
			blush = 0.45
			hip_y += absf(sin(t * 6.0)) * 0.05
			la.z += 0.3 + absf(sin(t * 6.0)) * 0.4
			ra.z -= 0.3 + absf(sin(t * 6.0)) * 0.4
		"angry":
			smile = -0.8
			brow_tilt = 0.45
			brow_h = -0.012
			tint = Color(1.0, 0.8, 0.78)
			torso_rot.x += 0.06
			if state != "phone" and state != "sit_phone":
				ra.x = -0.8 + sin(t * 10.0) * 0.15
				rf.x = -1.2
		"confused":
			smile = -0.2
			brow_tilt = -0.3
			head_rot.z += 0.22 + sin(t * 1.5) * 0.05
			if state != "phone" and state != "sit_phone":
				ra = Vector3(-0.6, 0, -1.2)
				rf = Vector3(-1.8, 0, 0)
		"surprised":
			smile = 0.0
			brow_h = 0.03
			eye_scale = 1.3
			torso_rot.x -= 0.08
		"distrust":
			smile = -0.4
			brow_tilt = 0.25
			lid = 0.5
			head_rot.x -= 0.1
			if state == "idle":
				la = Vector3(-0.9, 0.5, 0.4)
				lf = Vector3(-1.6, 0, 0)
				ra = Vector3(-0.9, -0.5, -0.4)
				rf = Vector3(-1.6, 0, 0)
		"sad":
			smile = -0.6
			brow_tilt = -0.35
			head_rot.x += 0.25
	# Gestos de un solo uso
	if _gesture != "":
		_gesture_t += delta
		var g := _gesture_t
		match _gesture:
			"nod":
				head_rot.x += sin(g * 14.0) * 0.25
			"shake":
				head_rot.y += sin(g * 14.0) * 0.35
			"laugh":
				torso_rot.x += sin(g * 18.0) * 0.07
				smile = 1.0
			"point":
				la = Vector3(-1.5, 0, 0)
				lf = Vector3(-0.1, 0, 0)
			"head_scratch":
				if state != "phone" and state != "sit_phone":
					ra = Vector3(-0.6, 0, -1.2)
					rf = Vector3(-1.9 + sin(g * 20.0) * 0.15, 0, 0)
			"arms_crossed":
				la = Vector3(-0.9, 0.5, 0.4)
				lf = Vector3(-1.6, 0, 0)
			"angry":
				la = Vector3(-2.6 + sin(g * 12.0) * 0.2, 0, 0.3)
				lf = Vector3(-0.4, 0, 0)
			"surprised":
				la.z += 0.8
				ra.z -= 0.8
				eye_scale = 1.35
			"think":
				la = Vector3(-1.0, 0.3, 0.3)
				lf = Vector3(-2.0, 0, 0)
			"hangup":
				ra.x = 0.2
				rf.x = 0.0
			"wave":
				ra = Vector3(-0.2, 0, -2.6)
				rf = Vector3(0, 0, sin(g * 12.0) * 0.5)
		if _gesture_t > 1.3:
			_gesture = ""
	# Aplicar con suavizado
	var k := clampf(delta * 10.0, 0.0, 1.0)
	hips.position.y = lerpf(hips.position.y, hip_y, k)
	torso.rotation = torso.rotation.lerp(torso_rot, k)
	torso.scale = Vector3(1.0, 1.0 + breath, 1.0)
	head_pivot.rotation = head_pivot.rotation.lerp(head_rot, k)
	arm_l.rotation = arm_l.rotation.lerp(la, k)
	arm_r.rotation = arm_r.rotation.lerp(ra, k)
	fore_l.rotation = fore_l.rotation.lerp(lf, k)
	fore_r.rotation = fore_r.rotation.lerp(rf, k)
	leg_l.rotation = leg_l.rotation.lerp(ll, k)
	leg_r.rotation = leg_r.rotation.lerp(rl, k)
	knee_l.rotation = knee_l.rotation.lerp(lk, k)
	knee_r.rotation = knee_r.rotation.lerp(rk, k)
	# Cara
	brow_l.rotation.z = lerpf(brow_l.rotation.z, -brow_tilt, k)
	brow_r.rotation.z = lerpf(brow_r.rotation.z, brow_tilt, k)
	brow_l.position.y = lerpf(brow_l.position.y, 0.115 + brow_h, k)
	brow_r.position.y = lerpf(brow_r.position.y, 0.115 + brow_h, k)
	var lid_amt := maxf(lid, _blink)
	lid_l.scale.y = lerpf(lid_l.scale.y, 0.3 + lid_amt * 0.9, clampf(delta * 25.0, 0, 1))
	lid_r.scale.y = lid_l.scale.y
	lid_l.position.y = 0.06 - lid_amt * 0.03
	lid_r.position.y = lid_l.position.y
	eye_l.scale = eye_l.scale.lerp(Vector3.ONE * eye_scale, k)
	eye_r.scale = eye_l.scale
	var open := clampf(talk_amount, 0.0, 1.0)
	mouth.scale = Vector3(1.0 + smile * 0.25 - open * 0.15, 1.0 + open * 3.5, 1.0)
	mouth.position.y = -0.085 - open * 0.012
	corner_l.rotation.z = lerpf(corner_l.rotation.z, -smile * 0.7, k)
	corner_r.rotation.z = lerpf(corner_r.rotation.z, smile * 0.7, k)
	corner_l.position.y = -0.082 + smile * 0.008
	corner_r.position.y = corner_l.position.y
	var bm := cheek_l.material_override as StandardMaterial3D
	bm.albedo_color.a = lerpf(bm.albedo_color.a, blush, k)
	skin_mat.albedo_color = skin_mat.albedo_color.lerp(Color(str(look.get("skin", SKIN_DEFAULT))) * tint, k * 0.5)
