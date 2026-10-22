class_name Art
## Helpers for building low-poly 3D objects out of simple shapes.

static var _mats := {}


static func mat(color: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [color.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


static func glow_mat(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "glow_%s_%s" % [color.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


static func ghost_mat(ok: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.25, 0.2, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rough: float = 0.8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(color, rough)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, color: Color, segments: int = 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = h
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func ball(parent: Node3D, r: float, pos: Vector3, color: Color, segments: int = 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segments
	sm.rings = maxi(3, segments / 2)
	mi.mesh = sm
	mi.material_override = mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


static func label(parent: Node3D, text: String, pos: Vector3, size: int = 64, color: Color = Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.006
	l.modulate = color
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.position = pos
	parent.add_child(l)
	return l


## Solid box that the first-person player bumps into.
static func solid(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rough: float = 0.8) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)
	box(body, size, Vector3.ZERO, color, rough)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	return body


# --- Decorations -----------------------------------------------------------

static func make_decor(kind: String) -> Node3D:
	var n := Node3D.new()
	match kind:
		"bench":
			box(n, Vector3(1.5, 0.08, 0.5), Vector3(0, 0.45, 0), Color(0.62, 0.42, 0.25))
			box(n, Vector3(1.5, 0.45, 0.08), Vector3(0, 0.72, -0.22), Color(0.62, 0.42, 0.25))
			for x in [-0.65, 0.65]:
				box(n, Vector3(0.08, 0.45, 0.45), Vector3(x, 0.22, 0), Color(0.2, 0.2, 0.22))
		"plant":
			cyl(n, 0.38, 0.3, 0.55, Vector3(0, 0.27, 0), Color(0.85, 0.82, 0.78))
			ball(n, 0.5, Vector3(0, 0.95, 0), Color(0.25, 0.6, 0.3), 6)
			ball(n, 0.32, Vector3(0.25, 1.3, 0.1), Color(0.3, 0.68, 0.32), 6)
			ball(n, 0.28, Vector3(-0.22, 1.25, -0.12), Color(0.22, 0.55, 0.28), 6)
		"bin":
			cyl(n, 0.28, 0.24, 0.8, Vector3(0, 0.4, 0), Color(0.3, 0.45, 0.35))
			cyl(n, 0.3, 0.3, 0.06, Vector3(0, 0.82, 0), Color(0.2, 0.2, 0.2))
		"lamp":
			cyl(n, 0.06, 0.08, 2.6, Vector3(0, 1.3, 0), Color(0.15, 0.15, 0.17))
			var bulb := ball(n, 0.22, Vector3(0, 2.7, 0), Color(1, 0.9, 0.6))
			bulb.material_override = glow_mat(Color(1.0, 0.85, 0.55), 3.0)
			var light := OmniLight3D.new()
			light.position = Vector3(0, 2.5, 0)
			light.light_color = Color(1.0, 0.85, 0.6)
			light.light_energy = 1.2
			light.omni_range = 5.0
			n.add_child(light)
		"fountain":
			cyl(n, 0.95, 0.95, 0.45, Vector3(0, 0.22, 0), Color(0.75, 0.75, 0.8), 10)
			cyl(n, 0.8, 0.8, 0.05, Vector3(0, 0.44, 0), Color(0.3, 0.6, 0.95, 0.8), 10)
			cyl(n, 0.12, 0.15, 1.0, Vector3(0, 0.9, 0), Color(0.75, 0.75, 0.8))
			cyl(n, 0.4, 0.15, 0.15, Vector3(0, 1.4, 0), Color(0.75, 0.75, 0.8))
			var w := ball(n, 0.25, Vector3(0, 1.6, 0), Color(0.5, 0.8, 1.0, 0.6))
			w.material_override = mat(Color(0.5, 0.8, 1.0, 0.6), 0.1)
	return n


# --- People ----------------------------------------------------------------

static func make_person(shirt: Color, pants: Color, skin: Color, hair: Color) -> Node3D:
	var n := Node3D.new()
	box(n, Vector3(0.14, 0.75, 0.16), Vector3(-0.1, 0.38, 0), pants)
	box(n, Vector3(0.14, 0.75, 0.16), Vector3(0.1, 0.38, 0), pants)
	box(n, Vector3(0.44, 0.6, 0.26), Vector3(0, 1.05, 0), shirt)
	box(n, Vector3(0.1, 0.55, 0.12), Vector3(-0.28, 1.05, 0), shirt)
	box(n, Vector3(0.1, 0.55, 0.12), Vector3(0.28, 1.05, 0), shirt)
	box(n, Vector3(0.28, 0.3, 0.28), Vector3(0, 1.55, 0), skin)
	box(n, Vector3(0.3, 0.1, 0.3), Vector3(0, 1.72, 0), hair)
	box(n, Vector3(0.05, 0.05, 0.02), Vector3(-0.07, 1.58, 0.145), Color(0.1, 0.1, 0.1))
	box(n, Vector3(0.05, 0.05, 0.02), Vector3(0.07, 1.58, 0.145), Color(0.1, 0.1, 0.1))
	return n
