extends Node3D
## Sets up the world and handles mall-view input: build tools, selecting units, entering your shops.

var world: WorldView
var shoppers: ShopperManager
var cam: CameraRig
var hud: HUD
var fp: FPPlayer

var tool := "select"
var unit_rot := 0
var selected_unit := -1
var fp_unit := -1
var ghost: Node3D
var _ghost_key := ""
var _painting := false
var _last_paint := Vector2i(-99, -99)

const TOOL_KEYS := ["select", "corridor", "unit", "bench", "plant", "bin", "lamp", "fountain", "bulldoze"]


func _ready() -> void:
	world = WorldView.new()
	add_child(world)
	shoppers = ShopperManager.new()
	shoppers.world = world
	add_child(shoppers)
	cam = CameraRig.new()
	add_child(cam)
	fp = FPPlayer.new()
	fp.hover_changed.connect(func(t): hud.set_fp_hover(t))
	ghost = Node3D.new()
	add_child(ghost)
	hud = HUD.new()
	hud.main = self
	add_child(hud)
	Game.reset.connect(_on_reset)
	Game.level_up.connect(func(_l): hud.refresh_panels())
	set_tool("select")
	if "--autotest" in OS.get_cmdline_user_args():
		_autotest()
	elif "--shots" in OS.get_cmdline_user_args():
		_screenshots()
	else:
		hud.show_main_menu()


## Plays days automatically at high speed and prints a summary. Run with: godot -- --autotest
func _autotest() -> void:
	Game.delete_save()
	Game.new_game()
	hud.close_popup()
	Engine.time_scale = 8.0
	Game.speed = 4
	Game.day_ended.connect(func(r):
		print("DAY %d  visitors=%d  profit=%s  money=%s  rating=%.2f  sat=%.2f  tenants_happy=%s  events=%s" % [
			r["day"], r["visitors"], Data.money_str(r["profit"]), Data.money_str(r["money"]), r["rating"], r["satisfaction"],
			_tenant_moods(), r["events"]])
		print("   complaints: ", r["complaints"])
		for u in Game.units:
			if u["state"] == "tenant":
				print("   tenant %s rent=%d sales_yday=%d" % [u["tenant"]["name"], u["tenant"]["rent"], u["tenant"]["sales_yday"]])
			elif u["state"] == "owned":
				print("   own shop sales_yday=%d back=%s" % [u["shop"]["sales_yday"], u["shop"]["back"]])
		if r["day"] >= int(OS.get_environment("AUTOTEST_DAYS") if OS.get_environment("AUTOTEST_DAYS") != "" else "6"):
			get_tree().quit()
		else:
			hud.close_popup()
			Game.start_next_day.call_deferred())
	# open a shop of our own in an empty unit and hire a cashier + stocker
	await get_tree().create_timer(0.5).timeout
	for u in Game.units:
		if u["state"] == "vacant":
			Game.open_own_shop(u, "toys")
			Game.toggle_staff(u, "cashier")
			Game.toggle_staff(u, "stocker")
			select_unit(u["id"])
			break


## Takes a few screenshots for checking the visuals. Run with: godot -- --shots
func _screenshots() -> void:
	Game.delete_save()
	Game.new_game()
	hud.close_popup()
	for u in Game.units:
		if u["state"] == "vacant":
			Game.open_own_shop(u, "toys")
			Game.toggle_staff(u, "stocker")
			break
	Game.place_decor(Vector2i(15, 16), "bench")
	Game.place_decor(Vector2i(16, 19), "bin")
	Game.place_decor(Vector2i(15, 19), "bench")
	Engine.time_scale = 1.0
	Game.speed = 4
	var dir := OS.get_environment("SHOT_DIR")
	await get_tree().create_timer(14.0).timeout
	Game.speed = 1
	set_tool("unit")
	get_viewport().warp_mouse(Vector2(1000, 300))
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(dir + "/shot_build.png")
	set_tool("select")
	select_unit(Game.units[1]["id"])
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(dir + "/shot_overview.png")
	select_unit(-1)
	cam._target_distance = 16.0
	cam.distance = 16.0
	cam.focus_on(Vector3(32, 0, 34))
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(dir + "/shot_close.png")
	enter_shop(Game.units[1]["id"])
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(dir + "/shot_fp.png")
	get_tree().quit()


func _tenant_moods() -> String:
	var out := []
	for u in Game.units:
		if u["state"] == "tenant":
			out.append("%s:%d" % [u["tenant"]["type"], int(u["tenant"]["happiness"])])
	return ",".join(out)


func _exit_tree() -> void:
	if fp and fp.get_parent() == null:
		fp.free()


func _on_reset() -> void:
	exit_shop()
	select_unit(-1)
	set_tool("select")


# ===========================================================================
# Tools
# ===========================================================================

func set_tool(t: String) -> void:
	if Data.BUILD.has(t) and Game.level < Data.BUILD[t]["level"]:
		Game.notify.emit("%s unlocks at owner level %d." % [Data.BUILD[t]["name"], Data.BUILD[t]["level"]], "bad")
		return
	tool = t
	_ghost_key = ""
	if t != "select":
		select_unit(-1)
	world.show_grid(t != "select")
	hud.update_tool(tool, tool_hint())


func tool_hint() -> String:
	match tool:
		"select":
			return "Click a shop to manage it. Number keys 1-9 pick tools."
		"corridor":
			return "Click and drag to lay floor. Shoppers walk on floor tiles."
		"unit":
			return "Place a 3x3 shop unit. [R] rotate. The arrow shows the door: it must touch a floor tile."
		"bulldoze":
			return "Click to remove floor, decorations or empty units (50% refund)."
		_:
			return "Place on a floor tile. Decorations make shoppers happier."


func select_unit(id: int) -> void:
	selected_unit = id
	world.select_unit(id)
	hud.refresh_panels()


func _unhandled_input(event: InputEvent) -> void:
	if fp_unit >= 0:
		_fp_input(event)
		return
	if hud.popup_open() or not Game.running:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if tool != "select":
					set_tool("select")
				else:
					select_unit(-1)
			KEY_R:
				unit_rot = (unit_rot + 1) % 4
				_ghost_key = ""
			KEY_SPACE:
				hud.set_speed(0 if Game.speed != 0 else 1)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var idx: int = event.keycode - KEY_1
				if idx < TOOL_KEYS.size():
					set_tool(TOOL_KEYS[idx])
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_painting = true
			_last_paint = Vector2i(-99, -99)
			_apply_tool(true)
		else:
			_painting = false
	elif event is InputEventMouseMotion and _painting and tool in ["corridor", "bulldoze"]:
		_apply_tool(false)


func _mouse_tile():
	var p = cam.mouse_ground_point()
	if p == null:
		return null
	return WorldView.world_to_tile(p)


func _unit_origin(t: Vector2i) -> Vector2i:
	return t - Vector2i(1, 1)


func _apply_tool(first_click: bool) -> void:
	var t = _mouse_tile()
	if t == null:
		return
	if t == _last_paint:
		return
	_last_paint = t
	match tool:
		"select":
			if not first_click:
				return
			var u = Game.unit_at(t)
			select_unit(u["id"] if u != null else -1)
		"corridor":
			if Game.can_place_floor(t):
				Game.place_floor(t)
		"unit":
			if first_click:
				Game.place_unit(_unit_origin(t), unit_rot)
		"bulldoze":
			if Game.grid.get(t, "") == "entrance":
				return
			var u = Game.unit_at(t)
			if u != null and not first_click:
				return
			Game.bulldoze(t)
		_:
			if first_click:
				Game.place_decor(t, tool)
	_ghost_key = ""


func _process(_delta: float) -> void:
	if fp_unit >= 0:
		return
	_update_ghost()


func _update_ghost() -> void:
	var t = _mouse_tile() if Game.running and tool != "select" and not hud.popup_open() else null
	if t == null or not Game.in_bounds(t):
		ghost.visible = false
		return
	ghost.visible = true
	var key := "%s_%s_%d_%d" % [tool, t, unit_rot, Game.grid.size() + Game.decor.size() * 1000 + Game.units.size() * 100000]
	if key == _ghost_key:
		return
	_ghost_key = key
	for c in ghost.get_children():
		c.queue_free()
	match tool:
		"unit":
			var origin := _unit_origin(t)
			var ok := Game.can_place_unit(origin, unit_rot)
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(6, 2.6, 6)
			m.mesh = bm
			m.material_override = Art.ghost_mat(ok)
			m.position = Vector3((origin.x + 1.5) * Data.TILE, 1.3, (origin.y + 1.5) * Data.TILE)
			ghost.add_child(m)
			# door arrow
			var door := Game.door_tile(origin, unit_rot)
			var arrow := MeshInstance3D.new()
			var am := PrismMesh.new()
			am.size = Vector3(1.2, 1.2, 0.2)
			arrow.mesh = am
			var door_ok := Game.walkable(door)
			arrow.material_override = Art.ghost_mat(door_ok)
			arrow.position = WorldView.tile_center(door) + Vector3(0, 0.3, 0)
			arrow.rotation = Vector3(-PI / 2, unit_rot * PI / 2 + PI, 0)
			ghost.add_child(arrow)
		_:
			var ok := false
			if tool == "corridor":
				ok = Game.can_place_floor(t)
			elif tool == "bulldoze":
				ok = Game.decor.has(t) or Game.grid.get(t, "") == "floor" or (Game.unit_at(t) != null and Game.unit_at(t)["state"] == "vacant")
			else:
				ok = Game.can_place_decor(t)
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(Data.TILE, 0.3, Data.TILE)
			m.mesh = bm
			m.material_override = Art.ghost_mat(ok)
			m.position = WorldView.tile_center(t) + Vector3(0, 0.15, 0)
			ghost.add_child(m)
			if Data.BUILD.has(tool) and tool != "corridor":
				var d := Art.make_decor(tool)
				d.position = WorldView.tile_center(t) + Vector3(0, 0.1, 0)
				ghost.add_child(d)


# ===========================================================================
# First person
# ===========================================================================

func enter_shop(unit_id: int) -> void:
	var u = Game.unit_by_id(unit_id)
	var view := world.view_for(unit_id)
	if u == null or view == null or u["state"] != "owned":
		return
	fp_unit = unit_id
	ghost.visible = false
	if fp.get_parent() == null:
		add_child(fp)
	fp.shop_view = view
	fp.activate(view.door_inside_global() + Vector3(0, 0.12, -0.3), view.rotation.y)
	cam.enabled = false
	UnitView.show_shelf_labels = true
	view.set_first_person(true)
	view.refresh(u)
	hud.set_fp(true)


func exit_shop() -> void:
	if fp_unit < 0:
		return
	var view := world.view_for(fp_unit)
	UnitView.show_shelf_labels = false
	if view:
		view.set_first_person(false)
		view.refresh(Game.unit_by_id(fp_unit))
	fp_unit = -1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if fp.get_parent() != null:
		remove_child(fp)
	cam.enabled = true
	cam.camera.current = true
	hud.set_fp(false)
	hud.refresh_panels()


func _fp_input(event: InputEvent) -> void:
	var u = Game.unit_by_id(fp_unit)
	if u == null or u["state"] != "owned":
		exit_shop()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE, KEY_TAB:
				exit_shop()
			KEY_E:
				_fp_interact(u)
			KEY_F:
				var info = fp.looking_at()
				if info != null and info["kind"] == "shelf":
					Game.cycle_shelf_product(u, info["index"])
					fp.hover_changed.emit(fp.describe(info))
			KEY_SPACE:
				hud.set_speed(0 if Game.speed != 0 else 1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			_fp_interact(u)


func _fp_interact(u: Dictionary) -> void:
	var info = fp.looking_at()
	if info == null:
		return
	if info["kind"] == "shelf":
		var n := Game.restock_shelf(u, info["index"])
		if n > 0:
			Game.notify.emit("Restocked %d items." % n, "good")
		else:
			var sh: Dictionary = u["shop"]["shelves"][info["index"]]
			if int(sh["stock"]) >= Game.SHELF_CAP:
				Game.notify.emit("That shelf is already full.", "info")
			else:
				Game.notify.emit("No %s left in the back room. Order more!" % Game.product(u, sh["p"])[0], "bad")
		fp.hover_changed.emit(fp.describe(info))
	elif info["kind"] == "register":
		if not shoppers.serve_front(u["id"]):
			Game.notify.emit("Nobody is waiting to pay.", "info")
