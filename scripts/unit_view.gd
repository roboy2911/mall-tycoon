class_name UnitView
extends Node3D

static var show_shelf_labels := false   # only shown in first person
## The 3D look of one shop unit. Local +Z is the side with the door.

const HALF := 3.0
const WALL_H := 2.6
const WALL_T := 0.2

var unit_id := 0
var shelf_items: Array = []    # per shelf: Array of MeshInstance3D product boxes
var queue_spots: Array = []    # local positions where customers wait to pay
var _sel_ring: MeshInstance3D


func setup(u: Dictionary) -> void:
	unit_id = u["id"]
	var p: Vector2i = u["pos"]
	position = Vector3((p.x + 1.5) * Data.TILE, 0, (p.y + 1.5) * Data.TILE)
	rotation.y = u["rot"] * PI / 2.0
	_build(u)


func _build(u: Dictionary) -> void:
	var state: String = u["state"]
	var type := ""
	if state == "tenant":
		type = u["tenant"]["type"]
	elif state == "owned":
		type = u["shop"]["type"]
	var tcol: Color = Data.SHOP_TYPES[type]["color"] if type != "" else Color(0.55, 0.55, 0.58)
	var floor_col := tcol.lerp(Color(0.78, 0.75, 0.7), 0.7) if type != "" else Color(0.45, 0.43, 0.41)
	var wall_col := Color(0.8, 0.77, 0.72) if type != "" else Color(0.6, 0.58, 0.56)

	# floor
	Art.box(self, Vector3(HALF * 2, 0.12, HALF * 2), Vector3(0, 0.06, 0), floor_col)
	# back and side walls (solid for first-person)
	Art.solid(self, Vector3(HALF * 2, WALL_H, WALL_T), Vector3(0, WALL_H / 2, -HALF + WALL_T / 2), wall_col)
	Art.solid(self, Vector3(WALL_T, WALL_H, HALF * 2), Vector3(-HALF + WALL_T / 2, WALL_H / 2, 0), wall_col)
	Art.solid(self, Vector3(WALL_T, WALL_H, HALF * 2), Vector3(HALF - WALL_T / 2, WALL_H / 2, 0), wall_col)
	# front: pillars, shop windows and a door gap in the middle
	var front_z := HALF - WALL_T / 2
	for side in [-1.0, 1.0]:
		Art.solid(self, Vector3(0.3, WALL_H, WALL_T), Vector3(side * (HALF - 0.15), WALL_H / 2, front_z), wall_col)
		Art.solid(self, Vector3(0.25, WALL_H, WALL_T), Vector3(side * 1.05, WALL_H / 2, front_z), wall_col)
		Art.solid(self, Vector3(1.6, 0.4, WALL_T + 0.05), Vector3(side * 2.0, 0.2, front_z), wall_col.darkened(0.1))
		var glass := Art.solid(self, Vector3(1.6, WALL_H - 0.8, 0.06), Vector3(side * 2.0, 0.4 + (WALL_H - 0.8) / 2, front_z), Color(0.6, 0.8, 0.95, 0.35))
		glass.get_child(0).material_override = Art.mat(Color(0.65, 0.85, 1.0, 0.3), 0.05)
	# fascia sign board above the door
	Art.box(self, Vector3(HALF * 2 + 0.1, 0.55, 0.3), Vector3(0, WALL_H + 0.1, front_z + 0.05), tcol.darkened(0.2) if type != "" else Color(0.4, 0.4, 0.42))

	var title := "FOR LEASE"
	if state == "tenant":
		title = u["tenant"]["name"]
	elif state == "owned":
		title = "★ My " + Data.SHOP_TYPES[type]["name"]
	var sign := Art.label(self, title, Vector3(0, WALL_H + 0.1, front_z + 0.22), 72)
	sign.pixel_size = 0.005
	# a floating copy so the name reads from the top-down camera
	var top := Art.label(self, title, Vector3(0, WALL_H + 1.0, 0), 64)
	top.pixel_size = 0.006
	top.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	top.name = "TopSign"

	if state == "vacant":
		_build_vacant()
	elif state == "tenant":
		_build_tenant(type, tcol)
	elif state == "owned":
		_build_owned(u, tcol)

	# selection ring (hidden until selected)
	_sel_ring = MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(HALF * 2 + 0.3, 0.05, HALF * 2 + 0.3)
	_sel_ring.mesh = tm
	_sel_ring.material_override = Art.mat(Color(1.0, 0.85, 0.2, 0.35))
	_sel_ring.position = Vector3(0, 0.15, 0)
	_sel_ring.visible = false
	add_child(_sel_ring)


func set_selected(on: bool) -> void:
	if _sel_ring:
		_sel_ring.visible = on


func _build_vacant() -> void:
	for i in 3:
		Art.box(self, Vector3(0.6, 0.5, 0.6), Vector3(randf_range(-2, 2), 0.37, randf_range(-2, 1)), Color(0.6, 0.48, 0.32))
	Art.box(self, Vector3(1.2, 0.05, 0.8), Vector3(0.8, 0.14, -1.0), Color(0.75, 0.72, 0.7))


func _build_tenant(type: String, tcol: Color) -> void:
	var products: Array = Data.SHOP_TYPES[type]["products"]
	# display racks along back and sides
	var racks := [Vector3(-1.5, 0, -2.4), Vector3(1.5, 0, -2.4)]
	for r in racks:
		_rack(r, Vector3(2.0, 1.6, 0.55), tcol, false)
	_rack(Vector3(-2.4, 0, 0.2), Vector3(0.55, 1.6, 2.0), tcol, true)
	# counter with the owner behind it
	Art.box(self, Vector3(0.7, 1.0, 1.6), Vector3(2.0, 0.5, 1.0), tcol.darkened(0.3))
	Art.box(self, Vector3(0.75, 0.06, 1.65), Vector3(2.0, 1.02, 1.0), Color(0.9, 0.9, 0.9))
	var owner_npc := Art.make_person(tcol.lightened(0.2), Color(0.2, 0.2, 0.25), Color(0.9, 0.75, 0.6), Color(0.25, 0.15, 0.1))
	owner_npc.position = Vector3(2.55, 0.12, 1.0)
	owner_npc.rotation.y = -PI / 2
	add_child(owner_npc)
	if products.size() > 0:
		Art.box(self, Vector3(1.0, 0.8, 0.6), Vector3(0, 0.52, -0.3), tcol.lightened(0.1))


func _rack(pos: Vector3, size: Vector3, tcol: Color, along_z: bool) -> void:
	Art.box(self, size, pos + Vector3(0, size.y / 2, 0), Color(0.45, 0.33, 0.22))
	for tier in 3:
		for k in 5:
			var off := (k - 2) * 0.36
			var c := tcol.lightened(randf_range(-0.2, 0.4))
			var item_pos := pos + Vector3(0, 0.35 + tier * 0.5, 0)
			if along_z:
				item_pos += Vector3(0.3, 0, off)
			else:
				item_pos += Vector3(off, 0, 0.3)
			Art.box(self, Vector3(0.22, 0.3, 0.18), item_pos, c)


# --- Owned shop: interactive shelves, register, queue ----------------------

const SHELVES := [
	{"pos": Vector3(-1.5, 0, -2.4), "size": Vector3(2.0, 1.6, 0.6), "access": Vector3(-1.5, 0, -1.5), "along_z": false},
	{"pos": Vector3(1.5, 0, -2.4), "size": Vector3(2.0, 1.6, 0.6), "access": Vector3(1.5, 0, -1.5), "along_z": false},
	{"pos": Vector3(-2.4, 0, 0.2), "size": Vector3(0.6, 1.6, 2.0), "access": Vector3(-1.5, 0, 0.2), "along_z": true},
	{"pos": Vector3(0.0, 0, -0.4), "size": Vector3(1.4, 1.1, 0.6), "access": Vector3(0.0, 0, 0.35), "along_z": false},
]
const REGISTER_POS := Vector3(2.1, 0, 1.0)
const DOOR_INSIDE := Vector3(0, 0, 2.3)
const CASHIER_POS := Vector3(2.6, 0, 1.0)


func _build_owned(u: Dictionary, tcol: Color) -> void:
	var s: Dictionary = u["shop"]
	shelf_items.clear()
	for i in SHELVES.size():
		var d: Dictionary = SHELVES[i]
		var body := Art.solid(self, d["size"], d["pos"] + Vector3(0, d["size"].y / 2, 0), Color(0.42, 0.3, 0.2))
		body.set_meta("interact", {"kind": "shelf", "index": i, "unit": unit_id})
		var items := []
		var tiers := 3 if d["size"].y > 1.3 else 2
		for tier in tiers:
			for k in 8:
				var off := (k - 3.5) * 0.22
				var item_pos: Vector3 = d["pos"] + Vector3(0, 0.3 + tier * 0.48, 0)
				if d["along_z"]:
					item_pos += Vector3(0.32, 0, off)
				else:
					item_pos += Vector3(off, 0, 0.32 if i != 3 else 0.0)
				var mi := Art.box(self, Vector3(0.17, 0.26, 0.17), item_pos, Color.WHITE)
				items.append(mi)
		shelf_items.append(items)
		var lbl := Art.label(self, "", d["pos"] + Vector3(0, d["size"].y + 0.2, 0.0), 28)
		lbl.pixel_size = 0.004
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.name = "ShelfLabel%d" % i
	# register counter
	var reg := Art.solid(self, Vector3(0.7, 1.0, 1.6), REGISTER_POS + Vector3(0, 0.5, 0), tcol.darkened(0.35))
	reg.set_meta("interact", {"kind": "register", "unit": unit_id})
	Art.box(self, Vector3(0.75, 0.06, 1.65), REGISTER_POS + Vector3(0, 1.03, 0), Color(0.92, 0.92, 0.92))
	Art.box(self, Vector3(0.35, 0.25, 0.4), REGISTER_POS + Vector3(0.1, 1.18, 0.3), Color(0.15, 0.15, 0.18))
	Art.box(self, Vector3(0.05, 0.22, 0.3), REGISTER_POS + Vector3(-0.08, 1.38, 0.3), Color(0.3, 0.8, 0.5))
	# back room stock crates
	for k in 3:
		Art.box(self, Vector3(0.55, 0.45, 0.55), Vector3(2.45, 0.35 + k * 0.46, -1.6), Color(0.65, 0.5, 0.3))
	var cashier := Art.make_person(Color(0.2, 0.4, 0.8), Color(0.15, 0.15, 0.2), Color(0.95, 0.8, 0.65), Color(0.1, 0.08, 0.05))
	cashier.name = "Cashier"
	cashier.position = CASHIER_POS + Vector3(0, 0.12, 0)
	cashier.rotation.y = -PI / 2
	add_child(cashier)
	var ceiling := Node3D.new()
	ceiling.name = "Ceiling"
	ceiling.visible = false
	add_child(ceiling)
	Art.box(ceiling, Vector3(HALF * 2, 0.1, HALF * 2), Vector3(0, WALL_H, 0), Color(0.9, 0.9, 0.88))
	for lx in [-1.5, 1.5]:
		var panel := Art.box(ceiling, Vector3(1.2, 0.04, 0.4), Vector3(lx, WALL_H - 0.06, 0), Color.WHITE)
		panel.material_override = Art.glow_mat(Color(1, 0.97, 0.9), 1.5)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, WALL_H - 0.4, 0)
	lamp.omni_range = 6.0
	lamp.light_energy = 1.3
	ceiling.add_child(lamp)
	queue_spots.clear()
	for k in 6:
		queue_spots.append(Vector3(1.3, 0, 1.0 - k * 0.6))
	refresh(u)


## Update shelf stock visuals and labels from the game data.
func refresh(u: Dictionary) -> void:
	if u == null or u["state"] != "owned" or shelf_items.is_empty():
		return
	var s: Dictionary = u["shop"]
	var products: Array = Data.SHOP_TYPES[s["type"]]["products"]
	for i in s["shelves"].size():
		var sh: Dictionary = s["shelves"][i]
		var items: Array = shelf_items[i]
		var show := int(ceil(float(sh["stock"]) / Game.SHELF_CAP * items.size()))
		var col: Color = Data.SHOP_TYPES[s["type"]]["color"].lightened(0.15 + 0.12 * sh["p"])
		for k in items.size():
			items[k].visible = k < show
			items[k].material_override = Art.mat(col)
		var lbl: Label3D = get_node_or_null("ShelfLabel%d" % i)
		if lbl:
			lbl.text = "%s  %d/%d" % [products[sh["p"]][0], sh["stock"], Game.SHELF_CAP]
			lbl.modulate = Color(1, 0.4, 0.35) if sh["stock"] == 0 else Color.WHITE
			lbl.visible = show_shelf_labels
	var cashier := get_node_or_null("Cashier")
	if cashier:
		cashier.visible = s["cashier"]


func set_first_person(on: bool) -> void:
	var c := get_node_or_null("Ceiling")
	if c:
		c.visible = on
	for n in ["TopSign"]:
		var l := get_node_or_null(n)
		if l:
			l.visible = not on


func shelf_access_global(i: int) -> Vector3:
	return to_global(SHELVES[i]["access"])


func queue_global(k: int) -> Vector3:
	return to_global(queue_spots[mini(k, queue_spots.size() - 1)])


func door_inside_global() -> Vector3:
	return to_global(DOOR_INSIDE)


func random_inside_global() -> Vector3:
	return to_global(Vector3(randf_range(-1.6, 1.0), 0, randf_range(-1.4, 1.4)))
