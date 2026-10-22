class_name WorldView
extends Node3D
## Draws the mall: ground, floor tiles, outer walls, decorations, shop units and litter.

var tiles_root: Node3D
var litter_root: Node3D
var unit_views := {}   # unit id -> UnitView
var selected_unit_id := -1
var _litter_timer := 0.0
var grid_overlay: MeshInstance3D


static func tile_center(t: Vector2i) -> Vector3:
	return Vector3((t.x + 0.5) * Data.TILE, 0, (t.y + 0.5) * Data.TILE)


static func world_to_tile(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / Data.TILE), floori(p.z / Data.TILE))


func _ready() -> void:
	_build_environment()
	_build_ground()
	tiles_root = Node3D.new()
	add_child(tiles_root)
	litter_root = Node3D.new()
	add_child(litter_root)
	Game.tiles_changed.connect(_rebuild_tiles)
	Game.unit_changed.connect(_on_unit_changed)
	Game.changed.connect(_on_changed)
	Game.reset.connect(_on_reset)


func _on_reset() -> void:
	for id in unit_views:
		unit_views[id].queue_free()
	unit_views.clear()
	selected_unit_id = -1


func _process(delta: float) -> void:
	_litter_timer -= delta
	if _litter_timer <= 0.0:
		_litter_timer = 3.0
		_update_litter()


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sky_mat.ground_horizon_color = Color(0.7, 0.75, 0.8)
	sky_mat.ground_bottom_color = Color(0.3, 0.32, 0.35)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.tonemap_exposure = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _build_ground() -> void:
	var w := Data.GRID_W * Data.TILE
	var h := Data.GRID_H * Data.TILE
	var g := Node3D.new()
	add_child(g)
	# grass all around
	Art.box(g, Vector3(w + 80, 0.1, h + 80), Vector3(w / 2, -0.06, h / 2), Color(0.36, 0.52, 0.27))
	# the lot you own and can build on (lighter, trimmed grass with a curb)
	Art.box(g, Vector3(w, 0.02, h), Vector3(w / 2, -0.005, h / 2), Color(0.45, 0.6, 0.34))
	for side in [[Vector3(w, 0.15, 0.25), Vector3(w / 2, 0.05, 0)], [Vector3(w, 0.15, 0.25), Vector3(w / 2, 0.05, h)],
			[Vector3(0.25, 0.15, h), Vector3(0, 0.05, h / 2)], [Vector3(0.25, 0.15, h), Vector3(w, 0.05, h / 2)]]:
		Art.box(g, side[0], side[1], Color(0.7, 0.7, 0.68))
	# build grid overlay (shown while a build tool is active)
	grid_overlay = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, h)
	grid_overlay.mesh = pm
	grid_overlay.position = Vector3(w / 2, 0.12, h / 2)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = fract(wp.xz / 2.0);
	float line = step(0.95, max(g.x, g.y)) + step(max(g.x, g.y), 0.0);
	ALBEDO = vec3(1.0);
	ALPHA = clamp(line, 0.0, 1.0) * 0.28;
}
"""
	sm.shader = sh
	grid_overlay.material_override = sm
	grid_overlay.visible = false
	g.add_child(grid_overlay)
	# parking lot in front of the mall
	var pz := h + 8.0
	Art.box(g, Vector3(w, 0.04, 14.0), Vector3(w / 2, -0.0, pz), Color(0.22, 0.22, 0.24))
	for i in range(0, int(w / 3.0)):
		Art.box(g, Vector3(0.12, 0.05, 4.5), Vector3(1.5 + i * 3.0, 0.01, pz - 3.5), Color(0.95, 0.95, 0.9))
		Art.box(g, Vector3(0.12, 0.05, 4.5), Vector3(1.5 + i * 3.0, 0.01, pz + 3.5), Color(0.95, 0.95, 0.9))
	# road
	Art.box(g, Vector3(w + 80, 0.04, 8.0), Vector3(w / 2, 0.0, h + 21.0), Color(0.18, 0.18, 0.2))
	for i in range(-10, int(w / 4.0) + 10):
		Art.box(g, Vector3(2.0, 0.05, 0.2), Vector3(i * 4.0, 0.01, h + 21.0), Color(0.95, 0.85, 0.3))
	# parked cars
	var car_cols := [Color(0.8, 0.2, 0.2), Color(0.2, 0.4, 0.8), Color(0.9, 0.9, 0.9), Color(0.15, 0.15, 0.15), Color(0.9, 0.7, 0.2), Color(0.3, 0.6, 0.4)]
	for i in range(0, int(w / 3.0)):
		for row in [-1, 1]:
			if randf() < 0.45:
				_car(g, Vector3(3.0 + i * 3.0 - 1.5, 0, pz + row * 3.5), car_cols[randi() % car_cols.size()])
	# trees around the lot
	for i in 40:
		var side := randi() % 3
		var p := Vector3.ZERO
		if side == 0:
			p = Vector3(randf_range(-30, -3), 0, randf_range(-20, h + 10))
		elif side == 1:
			p = Vector3(randf_range(w + 3, w + 30), 0, randf_range(-20, h + 10))
		else:
			p = Vector3(randf_range(-20, w + 20), 0, randf_range(-25, -3))
		_tree(g, p)


func _car(parent: Node3D, pos: Vector3, col: Color) -> void:
	var c := Node3D.new()
	c.position = pos
	parent.add_child(c)
	Art.box(c, Vector3(1.7, 0.55, 3.8), Vector3(0, 0.5, 0), col, 0.4)
	Art.box(c, Vector3(1.5, 0.5, 2.0), Vector3(0, 1.0, -0.2), col.darkened(0.1), 0.4)
	Art.box(c, Vector3(1.52, 0.38, 1.9), Vector3(0, 1.02, -0.2), Color(0.2, 0.25, 0.3), 0.1)
	for x in [-0.8, 0.8]:
		for z in [-1.2, 1.2]:
			var wheel := Art.cyl(c, 0.32, 0.32, 0.25, Vector3(x, 0.32, z), Color(0.08, 0.08, 0.08))
			wheel.rotation.z = PI / 2


func _tree(parent: Node3D, pos: Vector3) -> void:
	var t := Node3D.new()
	t.position = pos
	var s := randf_range(0.8, 1.4)
	t.scale = Vector3(s, s, s)
	parent.add_child(t)
	Art.cyl(t, 0.18, 0.25, 1.6, Vector3(0, 0.8, 0), Color(0.45, 0.32, 0.2), 6)
	Art.cyl(t, 0.0, 1.3, 2.0, Vector3(0, 2.4, 0), Color(0.2, 0.5, 0.25), 7)
	Art.cyl(t, 0.0, 1.0, 1.6, Vector3(0, 3.3, 0), Color(0.25, 0.56, 0.28), 7)


func _rebuild_tiles() -> void:
	for c in tiles_root.get_children():
		c.queue_free()
	for t in Game.grid:
		var center := tile_center(t)
		var kind: String = Game.grid[t]
		var checker: bool = (t.x + t.y) % 2 == 0
		var col := Color(0.84, 0.81, 0.76) if checker else Color(0.74, 0.71, 0.67)
		if kind == "entrance":
			col = Color(0.55, 0.3, 0.25)
		Art.box(tiles_root, Vector3(Data.TILE, 0.1, Data.TILE), center + Vector3(0, 0.05, 0), col, 0.6)
		if kind == "entrance":
			_entrance(center)
		# low outer walls where the hallway meets open ground
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + dir
			if Game.grid.has(n) or Game.unit_at(n) != null:
				continue
			if kind == "entrance" and dir == Vector2i(0, 1):
				continue
			var edge := center + Vector3(dir.x, 0, dir.y) * (Data.TILE / 2 - 0.1)
			var size := Vector3(0.2, 1.0, Data.TILE) if dir.x != 0 else Vector3(Data.TILE, 1.0, 0.2)
			Art.solid(tiles_root, size, edge + Vector3(0, 0.5, 0), Color(0.62, 0.58, 0.54))
			var cap := size + Vector3(0.06, -0.92, 0.06)
			Art.box(tiles_root, cap, edge + Vector3(0, 1.02, 0), Color(0.45, 0.6, 0.4))
		if Game.decor.has(t):
			var d := Art.make_decor(Game.decor[t])
			d.position = center + Vector3(0, 0.1, 0)
			d.rotation.y = (t.x * 7 + t.y * 3) % 4 * PI / 2
			tiles_root.add_child(d)


func _entrance(center: Vector3) -> void:
	var e := Node3D.new()
	e.position = center
	tiles_root.add_child(e)
	for x in [-0.95, 0.95]:
		Art.box(e, Vector3(0.2, 3.2, 0.3), Vector3(x, 1.6, 0.9), Color(0.35, 0.35, 0.4))
	Art.box(e, Vector3(2.4, 0.5, 0.4), Vector3(0, 3.35, 0.9), Color(0.85, 0.25, 0.25))
	var l := Art.label(e, "MALL", Vector3(0, 3.35, 1.12), 110)
	l.pixel_size = 0.005
	Art.box(e, Vector3(1.4, 0.03, 1.0), Vector3(0, 0.12, 0.3), Color(0.25, 0.2, 0.2))


func _on_unit_changed(id: int) -> void:
	if unit_views.has(id):
		unit_views[id].queue_free()
		unit_views.erase(id)
	var u = Game.unit_by_id(id)
	if u == null:
		_rebuild_tiles()
		return
	var v := UnitView.new()
	add_child(v)
	v.setup(u)
	v.set_selected(id == selected_unit_id)
	unit_views[id] = v
	_rebuild_tiles()


func _on_changed() -> void:
	for id in unit_views:
		var u = Game.unit_by_id(id)
		if u != null and u["state"] == "owned":
			unit_views[id].refresh(u)


func select_unit(id: int) -> void:
	selected_unit_id = id
	for k in unit_views:
		unit_views[k].set_selected(k == id)


func view_for(id: int) -> UnitView:
	return unit_views.get(id)


func _update_litter() -> void:
	var want := int(Game.dirt / 4.0)
	var have := litter_root.get_child_count()
	if want == have:
		return
	if want < have:
		for i in have - want:
			litter_root.get_child(i).queue_free()
		return
	var tiles := []
	for t in Game.grid:
		if Game.walkable(t):
			tiles.append(t)
	if tiles.is_empty():
		return
	var cols := [Color(0.95, 0.95, 0.9), Color(0.8, 0.3, 0.25), Color(0.4, 0.6, 0.85), Color(0.75, 0.65, 0.4)]
	for i in want - have:
		var t: Vector2i = tiles[randi() % tiles.size()]
		var p := tile_center(t) + Vector3(randf_range(-0.8, 0.8), 0.13, randf_range(-0.8, 0.8))
		var piece := Art.box(litter_root, Vector3(0.18, 0.05, 0.14), p, cols[randi() % cols.size()])
		piece.rotation.y = randf() * TAU


func show_grid(on: bool) -> void:
	if grid_overlay:
		grid_overlay.visible = on
