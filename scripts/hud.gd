class_name HUD
extends CanvasLayer
## All on-screen UI: top bar, build toolbar, goals, notifications, shop panel, popups.

var main  # Main node

var root: Control
var top_labels := {}
var speed_buttons := {}
var tool_buttons := {}
var hint_label: Label
var goals_box: VBoxContainer
var requests_box: VBoxContainer
var notes_box: VBoxContainer
var right_panel: PanelContainer
var right_box: VBoxContainer
var popup_layer: Control
var fp_layer: Control
var fp_hover: Label
var fp_info: Label
var game_ui: Control

var _dirty := true
var _refresh_t := 0.0
var _notes: Array = []   # {label, t}

const C_GOOD := Color(0.45, 0.95, 0.5)
const C_BAD := Color(1.0, 0.45, 0.4)
const C_INFO := Color(0.85, 0.9, 1.0)
const C_DIM := Color(0.7, 0.72, 0.78)
const C_GOLD := Color(1.0, 0.82, 0.3)


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	game_ui = Control.new()
	game_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(game_ui)
	_build_top_bar()
	_build_toolbar()
	_build_left()
	_build_right()

	fp_layer = Control.new()
	fp_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	fp_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fp_layer.visible = false
	root.add_child(fp_layer)
	_build_fp_overlay()

	popup_layer = Control.new()
	popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(popup_layer)

	Game.changed.connect(func(): _dirty = true)
	Game.notify.connect(add_note)
	Game.day_ended.connect(_on_day_ended)
	Game.game_over.connect(_on_game_over)


func _process(delta: float) -> void:
	_update_top_bar()
	_refresh_t -= delta
	if _dirty and _refresh_t <= 0.0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dirty = false
		_refresh_t = 0.35
		refresh_panels()
	for n in _notes.duplicate():
		n["t"] -= delta
		if n["t"] < 1.0:
			n["label"].modulate.a = maxf(0.0, n["t"])
		if n["t"] <= 0.0:
			n["label"].queue_free()
			_notes.erase(n)
	if fp_layer.visible:
		_update_fp_info()


# ===========================================================================
# Theme / helpers
# ===========================================================================

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.1, 0.14, 0.88)
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(10)
	panel.border_color = Color(1, 1, 1, 0.08)
	panel.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", panel)
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.22, 0.26, 0.36)
	b.set_corner_radius_all(6)
	b.content_margin_left = 10
	b.content_margin_right = 10
	b.content_margin_top = 5
	b.content_margin_bottom = 5
	var bh := b.duplicate()
	bh.bg_color = Color(0.3, 0.36, 0.5)
	var bp := b.duplicate()
	bp.bg_color = Color(0.95, 0.65, 0.2)
	var bd := b.duplicate()
	bd.bg_color = Color(0.16, 0.17, 0.2)
	t.set_stylebox("normal", "Button", b)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("hover_pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.1, 0.1, 0.1))
	t.set_color("font_hover_pressed_color", "Button", Color(0.1, 0.1, 0.1))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.55))
	t.set_color("font_color", "Label", Color(0.93, 0.94, 0.97))
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.2, 0.2, 0.25)
	pb_bg.set_corner_radius_all(4)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = Color(0.4, 0.8, 0.45)
	pb_fill.set_corner_radius_all(4)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	return t


func _lbl(text: String, size: int = 15, color: Color = Color(0.93, 0.94, 0.97)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _btn(text: String, cb: Callable, disabled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _row(children: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for c in children:
		h.add_child(c)
	return h


func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _sep() -> HSeparator:
	return HSeparator.new()


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# ===========================================================================
# Top bar
# ===========================================================================

func _build_top_bar() -> void:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_TOP_WIDE)
	p.offset_left = 8
	p.offset_right = -8
	p.offset_top = 8
	game_ui.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	p.add_child(h)
	for key in ["money", "day", "time", "rating", "visitors", "level", "trend"]:
		var l := _lbl("", 17)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		top_labels[key] = l
		h.add_child(l)
	h.add_child(_spacer())
	for s in [0, 1, 2, 4]:
		var b := _btn("❚❚" if s == 0 else "%dx" % s, func(): set_speed(s))
		b.toggle_mode = true
		speed_buttons[s] = b
		h.add_child(b)
	h.add_child(_btn("Finances", show_finances))
	h.add_child(_btn("Help", show_help))


func set_speed(s: int) -> void:
	Game.speed = s
	for k in speed_buttons:
		speed_buttons[k].set_pressed_no_signal(k == s)


func _update_top_bar() -> void:
	top_labels["money"].text = Data.money_str(Game.money)
	top_labels["money"].add_theme_color_override("font_color", C_BAD if Game.money < 0 else C_GOOD)
	top_labels["day"].text = "Day %d · %s" % [Game.day, Game.season()]
	top_labels["time"].text = "🕒 " + Data.time_str(Game.minute) + ("" if Game.is_open() else " (closed)")
	var stars := ""
	for i in 5:
		stars += "★" if Game.rating >= i + 0.75 else ("⯪" if Game.rating >= i + 0.25 else "☆")
	top_labels["rating"].text = stars + " %.1f" % Game.rating
	top_labels["rating"].add_theme_color_override("font_color", C_GOLD)
	top_labels["visitors"].text = "👥 %d today" % Game.today.get("visitors", 0)
	var next_xp: int = Data.LEVEL_XP[mini(Game.level, Data.LEVEL_XP.size() - 1)]
	top_labels["level"].text = "Owner Lv %d (%d/%d XP)" % [Game.level, Game.xp, next_xp] if Game.level < Data.LEVEL_XP.size() else "Owner Lv %d (MAX)" % Game.level
	top_labels["trend"].text = "🔥 Trending: " + Data.SHOP_TYPES[Game.trend_type]["name"]
	for k in speed_buttons:
		speed_buttons[k].set_pressed_no_signal(k == Game.speed)


# ===========================================================================
# Toolbar
# ===========================================================================

func _build_toolbar() -> void:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_bottom = -8
	game_ui.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	hint_label = _lbl("", 14, C_DIM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint_label)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	var tools := [["select", "🖱 Select", ""], ["corridor", "Floor", "corridor"], ["unit", "Shop Unit", "unit"],
		["bench", "Bench", "bench"], ["plant", "Plant", "plant"], ["bin", "Trash Bin", "bin"],
		["lamp", "Lamp", "lamp"], ["fountain", "Fountain", "fountain"], ["bulldoze", "🗑 Bulldoze", ""]]
	var i := 1
	for t in tools:
		var label: String = t[1]
		if t[2] != "":
			label += "\n" + Data.money_str(Data.BUILD[t[2]]["cost"])
		else:
			label += "\n "
		var b := _btn("%s" % label, func(): main.set_tool(t[0]))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(92, 52)
		b.tooltip_text = "Hotkey: %d" % i
		tool_buttons[t[0]] = b
		h.add_child(b)
		i += 1


func update_tool(tool: String, hint: String) -> void:
	for k in tool_buttons:
		tool_buttons[k].set_pressed_no_signal(k == tool)
		if Data.BUILD.has(k):
			var need: int = Data.BUILD[k]["level"]
			tool_buttons[k].disabled = Game.level < need
			if Game.level < need:
				tool_buttons[k].text = "%s\nLv %d" % [Data.BUILD[k]["name"], need]
			else:
				tool_buttons[k].text = "%s\n%s" % [Data.BUILD[k]["name"], Data.money_str(Data.BUILD[k]["cost"])]
	hint_label.text = hint


# ===========================================================================
# Left: goals, requests, notifications
# ===========================================================================

func _build_left() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(8, 64)
	col.custom_minimum_size = Vector2(320, 0)
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(col)
	var gp := PanelContainer.new()
	col.add_child(gp)
	goals_box = VBoxContainer.new()
	gp.add_child(goals_box)
	var rp := PanelContainer.new()
	rp.name = "RequestsPanel"
	col.add_child(rp)
	requests_box = VBoxContainer.new()
	rp.add_child(requests_box)
	notes_box = VBoxContainer.new()
	notes_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notes_box.add_theme_constant_override("separation", 4)
	col.add_child(notes_box)


func add_note(text: String, kind: String = "info") -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _lbl(text, 14, C_GOOD if kind == "good" else (C_BAD if kind == "bad" else C_INFO))
	l.custom_minimum_size = Vector2(300, 0)
	p.add_child(l)
	notes_box.add_child(p)
	notes_box.move_child(p, 0)
	_notes.append({"label": p, "t": 9.0})
	while _notes.size() > 6:
		var old = _notes.pop_front()
		old["label"].queue_free()


func _refresh_goals() -> void:
	_clear(goals_box)
	goals_box.add_child(_lbl("🎯 Goals", 17, C_GOLD))
	for i in Game.active_goals():
		var g := Game.goal(i)
		var prog := Game.goal_progress(g)
		var target: float = g["target"]
		var v := VBoxContainer.new()
		v.add_child(_lbl(g["text"], 14))
		var pb := ProgressBar.new()
		pb.max_value = target
		pb.value = minf(prog, target)
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 8)
		v.add_child(pb)
		var prog_text := ""
		if g["kind"] in ["money", "own_sales"]:
			prog_text = "%s / %s" % [Data.money_str(prog), Data.money_str(target)]
		elif g["kind"] == "rating":
			prog_text = "%.1f / %.1f stars" % [prog, target]
		else:
			prog_text = "%d / %d" % [prog, target]
		var reward := "+%d XP" % g["xp"]
		if g["cash"] > 0:
			reward = Data.money_str(g["cash"]) + ", " + reward
		v.add_child(_lbl("%s   Reward: %s" % [prog_text, reward], 12, C_DIM))
		goals_box.add_child(v)

	_clear(requests_box)
	requests_box.get_parent().visible = Game.requests.size() > 0
	if Game.requests.size() > 0:
		requests_box.add_child(_lbl("📨 Tenant requests", 16, C_GOLD))
		for i in Game.requests.size():
			var r: Dictionary = Game.requests[i]
			requests_box.add_child(_lbl(r["text"], 14))
			requests_box.add_child(_row([_btn("Accept", func(): Game.answer_request(i, true)), _btn("Decline", func(): Game.answer_request(i, false))]))


# ===========================================================================
# Right: selected unit panel
# ===========================================================================

func _build_right() -> void:
	right_panel = PanelContainer.new()
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.offset_left = -370
	right_panel.offset_right = -8
	right_panel.offset_top = 64
	right_panel.offset_bottom = -110
	right_panel.visible = false
	game_ui.add_child(right_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(scroll)
	right_box = VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.add_theme_constant_override("separation", 6)
	scroll.add_child(right_box)


func refresh_panels() -> void:
	_refresh_goals()
	update_tool(main.tool, main.tool_hint())
	var u = Game.unit_by_id(main.selected_unit) if main.selected_unit >= 0 else null
	right_panel.visible = u != null
	if u == null:
		return
	_clear(right_box)
	var head := _row([_lbl("", 1), _spacer(), _btn("✕", func(): main.select_unit(-1))])
	right_box.add_child(head)
	match u["state"]:
		"vacant":
			_panel_vacant(u)
		"tenant":
			_panel_tenant(u)
		"owned":
			_panel_owned(u)


func _panel_vacant(u: Dictionary) -> void:
	right_box.add_child(_lbl("Empty Shop Unit", 20, C_GOLD))
	if not Game.door_reachable(u):
		right_box.add_child(_lbl("⚠ Shoppers can't reach this door. Build floor tiles from the entrance to the door arrow.", 14, C_BAD))
	right_box.add_child(_sep())
	right_box.add_child(_lbl("Lease to a business owner", 16))
	if Game.applicants.is_empty():
		right_box.add_child(_lbl("No one wants to rent right now. New applicants arrive each day.", 13, C_DIM))
	for i in Game.applicants.size():
		var a: Dictionary = Game.applicants[i]
		var v := VBoxContainer.new()
		var title: String = a["name"] + (" ⭐ CHAIN" if a["chain"] else "")
		v.add_child(_lbl(title, 15, C_GOLD if a["chain"] else Color.WHITE))
		var rel := int(a["reliability"] * 100)
		v.add_child(_lbl("%s · Rent %s/day · Pays on time: %d%% · Leaves in %d day(s)" % [Data.SHOP_TYPES[a["type"]]["name"], Data.money_str(a["rent"]), rel, a["expires"]], 13, C_DIM))
		v.add_child(_btn("Lease to %s" % a["name"], func(): Game.lease_unit(u, i)))
		right_box.add_child(v)
	right_box.add_child(_sep())
	var used := Game.owned_count()
	var max_own := Data.max_owned_shops(Game.level)
	right_box.add_child(_lbl("Run it yourself (%s setup) · %d/%d of your shops" % [Data.money_str(Game.SHOP_SETUP_COST), used, max_own], 16))
	var grid := GridContainer.new()
	grid.columns = 2
	for k in Data.SHOP_TYPES:
		var st: Dictionary = Data.SHOP_TYPES[k]
		var locked: bool = st["level"] > Game.level
		var txt: String = st["name"] + (" (Lv %d)" % st["level"] if locked else "")
		var b := _btn(txt, func(): Game.open_own_shop(u, k), locked or used >= max_own)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	right_box.add_child(grid)
	right_box.add_child(_sep())
	right_box.add_child(_btn("Bulldoze unit (refund %s)" % Data.money_str(Data.BUILD["unit"]["cost"] * 0.5), func():
		Game.bulldoze(u["pos"])
		main.select_unit(-1)))


func _panel_tenant(u: Dictionary) -> void:
	var t: Dictionary = u["tenant"]
	right_box.add_child(_lbl(t["name"], 20, C_GOLD))
	right_box.add_child(_lbl("%s%s · Tenant for %d day(s)" % [Data.SHOP_TYPES[t["type"]]["name"], " · Chain store" if t["chain"] else "", t["days"]], 14, C_DIM))
	if not Game.door_reachable(u):
		right_box.add_child(_lbl("⚠ Shoppers can't reach this door!", 14, C_BAD))
	right_box.add_child(_sep())
	right_box.add_child(_lbl("Happiness: %d%%" % int(t["happiness"]), 15))
	var pb := ProgressBar.new()
	pb.max_value = 100
	pb.value = t["happiness"]
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 10)
	right_box.add_child(pb)
	if t["happiness"] < 30:
		right_box.add_child(_lbl("This tenant might move out soon!", 13, C_BAD))
	right_box.add_child(_lbl("Sales today: %s · Yesterday: %s" % [Data.money_str(t["sales_today"]), Data.money_str(t["sales_yday"])], 14))
	right_box.add_child(_lbl("Shoppers today: %d" % t["visits_today"], 14))
	right_box.add_child(_lbl("Pays on time: %d%%" % int(t["reliability"] * 100), 14))
	if t["owed"] > 0:
		right_box.add_child(_lbl("Owes you: %s" % Data.money_str(t["owed"]), 14, C_BAD))
	right_box.add_child(_sep())
	right_box.add_child(_lbl("Rent: %s / day" % Data.money_str(t["rent"]), 16))
	right_box.add_child(_lbl("Higher rent = more money, but unhappier tenants.", 12, C_DIM))
	right_box.add_child(_row([_btn("-$10", func(): Game.change_rent(u, -10)), _btn("+$10", func(): Game.change_rent(u, 10)),
		_btn("-$50", func(): Game.change_rent(u, -50)), _btn("+$50", func(): Game.change_rent(u, 50))]))
	right_box.add_child(_sep())
	right_box.add_child(_btn("Evict tenant", func(): Game.evict(u)))


func _panel_owned(u: Dictionary) -> void:
	var s: Dictionary = u["shop"]
	var st: Dictionary = Data.SHOP_TYPES[s["type"]]
	right_box.add_child(_lbl("★ My " + st["name"], 20, C_GOLD))
	if not Game.door_reachable(u):
		right_box.add_child(_lbl("⚠ Shoppers can't reach this door!", 14, C_BAD))
	var work := _btn("🚶 Work in shop (first person)", func(): main.enter_shop(u["id"]))
	work.custom_minimum_size = Vector2(0, 40)
	right_box.add_child(work)
	right_box.add_child(_lbl("Sales today: %s · Yesterday: %s" % [Data.money_str(s["sales_today"]), Data.money_str(s["sales_yday"])], 14))
	right_box.add_child(_lbl("Customers: %d · Lost sales: %d · Waiting in line: %d" % [s["customers_today"], s["lost_today"], main.shoppers.queue_length(u["id"])], 14))
	if not s["cashier"]:
		right_box.add_child(_lbl("No cashier! Go in and serve customers yourself, or hire one.", 13, C_BAD))
	right_box.add_child(_sep())
	right_box.add_child(_lbl("Prices: %d%% of normal" % int(round(s["price_mult"] * 100)), 16))
	right_box.add_child(_lbl("Higher prices = more money per sale, fewer buyers.", 12, C_DIM))
	right_box.add_child(_row([_btn("-10%", func(): Game.set_price_mult(u, s["price_mult"] - 0.1)), _btn("-5%", func(): Game.set_price_mult(u, s["price_mult"] - 0.05)),
		_btn("+5%", func(): Game.set_price_mult(u, s["price_mult"] + 0.05)), _btn("+10%", func(): Game.set_price_mult(u, s["price_mult"] + 0.1))]))
	right_box.add_child(_sep())
	right_box.add_child(_lbl("Shelves", 16))
	for i in s["shelves"].size():
		var sh: Dictionary = s["shelves"][i]
		var pr: Array = st["products"][sh["p"]]
		var col := C_BAD if sh["stock"] == 0 else (C_GOLD if sh["stock"] < 6 else Color.WHITE)
		var l := _lbl("%d. %s  %d/%d  (%s)" % [i + 1, pr[0], sh["stock"], Game.SHELF_CAP, Data.money_str(Game.product_price(u, sh["p"]))], 14, col)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_box.add_child(_row([l, _btn("Switch", func(): Game.cycle_shelf_product(u, i))]))
	right_box.add_child(_lbl("Restock shelves yourself inside the shop, or hire a stocker.", 12, C_DIM))
	right_box.add_child(_sep())
	right_box.add_child(_lbl("Back room stock & ordering", 16))
	var pending := {}
	for o in s["orders"]:
		pending[int(o["p"])] = int(pending.get(int(o["p"]), 0)) + int(o["qty"])
	for p in st["products"].size():
		var pr: Array = st["products"][p]
		var txt := "%s: %d" % [pr[0], s["back"][p]]
		if pending.has(p):
			txt += " (+%d coming)" % pending[p]
		var l := _lbl(txt, 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right_box.add_child(_row([l, _btn("+10 %s" % Data.money_str(pr[1] * 10), func(): Game.order_stock(u, p, 10)),
			_btn("+40 %s" % Data.money_str(pr[1] * 40), func(): Game.order_stock(u, p, 40))]))
	right_box.add_child(_sep())
	right_box.add_child(_lbl("Staff", 16))
	right_box.add_child(_row([_lbl("Cashier (%s/day)" % Data.money_str(Data.CASHIER_WAGE), 14), _spacer(),
		_btn("Fire" if s["cashier"] else "Hire", func(): Game.toggle_staff(u, "cashier"))]))
	right_box.add_child(_row([_lbl("Stocker (%s/day)" % Data.money_str(Data.STOCKER_WAGE), 14), _spacer(),
		_btn("Fire" if s["stocker"] else "Hire", func(): Game.toggle_staff(u, "stocker"))]))
	right_box.add_child(_sep())
	right_box.add_child(_btn("Close this shop", func(): Game.close_own_shop(u)))


# ===========================================================================
# First-person overlay
# ===========================================================================

func _build_fp_overlay() -> void:
	var cross := _lbl("+", 26)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.position -= Vector2(8, 18)
	fp_layer.add_child(cross)
	fp_hover = _lbl("", 18)
	fp_hover.set_anchors_preset(Control.PRESET_CENTER)
	fp_hover.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fp_hover.custom_minimum_size = Vector2(600, 0)
	fp_hover.position += Vector2(-300, 30)
	fp_layer.add_child(fp_hover)
	var p := PanelContainer.new()
	p.position = Vector2(12, 12)
	fp_layer.add_child(p)
	fp_info = _lbl("", 15)
	fp_info.custom_minimum_size = Vector2(340, 0)
	p.add_child(fp_info)


func set_fp(on: bool) -> void:
	fp_layer.visible = on
	game_ui.visible = not on
	fp_hover.text = ""


func set_fp_hover(text: String) -> void:
	fp_hover.text = text


func _update_fp_info() -> void:
	var u = Game.unit_by_id(main.fp_unit)
	if u == null or u["state"] != "owned":
		return
	var s: Dictionary = u["shop"]
	var t := "My %s  ·  %s  ·  %s\n" % [Data.SHOP_TYPES[s["type"]]["name"], Data.time_str(Game.minute), Data.money_str(Game.money)]
	t += "Sales today: %s\nWaiting in line: %d\n\n" % [Data.money_str(s["sales_today"]), main.shoppers.queue_length(u["id"])]
	t += "[WASD] Walk  [Mouse] Look\n[E] Restock / Serve  [F] Switch product\n[Tab] or [Esc] Back to mall view"
	fp_info.text = t


# ===========================================================================
# Popups
# ===========================================================================

func _popup(width: int = 520) -> VBoxContainer:
	_clear(popup_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.add_child(center)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	return v


func close_popup() -> void:
	_clear(popup_layer)


func popup_open() -> bool:
	return popup_layer.get_child_count() > 0


func show_main_menu() -> void:
	var v := _popup(460)
	var title := _lbl("MALL TYCOON", 40, C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _lbl("Build it. Run it. Don't go bankrupt.", 16, C_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(_sep())
	if Game.has_save():
		var c := _btn("Continue", func():
			close_popup()
			Game.load_game())
		c.custom_minimum_size = Vector2(0, 44)
		v.add_child(c)
	var n := _btn("New Mall", func():
		close_popup()
		Game.delete_save()
		Game.new_game()
		show_help())
	n.custom_minimum_size = Vector2(0, 44)
	v.add_child(n)
	v.add_child(_btn("Quit", func(): get_tree().quit()))


func show_help() -> void:
	var v := _popup(620)
	v.add_child(_lbl("How to play", 24, C_GOLD))
	v.add_child(_lbl("You own the whole mall. Grow it from a tiny strip mall into a 5-star shopping center that lasts forever.", 15))
	v.add_child(_lbl(
		"• Click a shop unit to lease it to a business owner, or run it yourself.\n" +
		"• Tenants pay rent every night. Keep them happy or they move out.\n" +
		"• Your own shops: order stock, set prices, then walk inside (first person) to restock shelves and work the register. Or hire staff.\n" +
		"• Build floor tiles, new shop units and decorations. Shoppers need a floor path from the entrance to each shop's door.\n" +
		"• Keep the mall clean (hire cleaners, add trash bins) and offer lots of shop types to raise your star rating.\n" +
		"• Finish goals to earn cash and XP. Level up to unlock more shops and decorations.\n" +
		"• If your money ends the day below $0 for 3 days in a row, you go bankrupt and lose everything!", 15))
	v.add_child(_sep())
	v.add_child(_lbl("Mall view: WASD / arrows move · Q/E or right-drag rotate · Mouse wheel zoom · R rotate shop unit · 1-9 tools · Space pause · Esc cancel", 14, C_DIM))
	v.add_child(_lbl("Inside your shop: WASD walk · Mouse look · E restock / serve · F switch shelf product · Tab or Esc leave", 14, C_DIM))
	v.add_child(_btn("Got it!", close_popup))


func show_finances() -> void:
	var v := _popup(560)
	v.add_child(_row([_lbl("Finances & Mall", 24, C_GOLD), _spacer(), _btn("✕", close_popup)]))
	v.add_child(_lbl("Money: %s" % Data.money_str(Game.money), 16, C_GOOD if Game.money >= 0 else C_BAD))
	if Game.debt_days > 0:
		v.add_child(_lbl("⚠ In debt for %d day(s)! Bankrupt at %d." % [Game.debt_days, Data.BANKRUPT_DAYS], 15, C_BAD))
	v.add_child(_sep())
	v.add_child(_lbl("Bank loan: %s (limit %s, 1%% interest per day)" % [Data.money_str(Game.loan), Data.money_str(Game.max_loan())], 15))
	v.add_child(_row([_btn("Borrow $5,000", func():
		Game.take_loan(5000)
		show_finances()), _btn("Borrow $20,000", func():
		Game.take_loan(20000)
		show_finances()), _btn("Repay $5,000", func():
		Game.repay_loan(5000)
		show_finances()), _btn("Repay all", func():
		Game.repay_loan(Game.loan)
		show_finances())]))
	v.add_child(_sep())
	v.add_child(_lbl("Marketing", 16))
	var active := []
	for m in Game.marketing:
		active.append("%s (%d day(s) left)" % [m["name"], m["days"]])
	v.add_child(_lbl("Active: " + (", ".join(active) if active.size() > 0 else "none"), 14, C_DIM))
	var mrow := []
	for k in Game.MARKETING:
		var m: Dictionary = Game.MARKETING[k]
		mrow.append(_btn("%s %s" % [m["name"], Data.money_str(m["cost"])], func():
			Game.buy_marketing(k)
			show_finances()))
	v.add_child(_row(mrow))
	v.add_child(_sep())
	v.add_child(_lbl("Mall staff", 16))
	v.add_child(_row([_lbl("Cleaners: %d (%s/day each)" % [Game.cleaners, Data.money_str(Data.CLEANER_WAGE)], 14), _spacer(),
		_btn("-", func():
			Game.hire("cleaner", -1)
			show_finances()), _btn("+", func():
			Game.hire("cleaner", 1)
			show_finances())]))
	v.add_child(_row([_lbl("Security guards: %d (%s/day each)" % [Game.security, Data.money_str(Data.SECURITY_WAGE)], 14), _spacer(),
		_btn("-", func():
			Game.hire("security", -1)
			show_finances()), _btn("+", func():
			Game.hire("security", 1)
			show_finances())]))
	v.add_child(_sep())
	v.add_child(_lbl("Mall status", 16))
	v.add_child(_lbl("Dirtiness: %d%%" % int(Game.dirt), 14, C_BAD if Game.dirt > 50 else Color.WHITE))
	v.add_child(_lbl("Expected shoppers per day: ~%d" % int(Game.expected_visitors()), 14))
	if Game.rival_strength > 0:
		v.add_child(_lbl("Rival mall Sunset Plaza strength: %.1f stars (you: %.1f)" % [Game.rival_strength, Game.rating], 14, C_BAD if Game.rival_strength > Game.rating else C_GOOD))
	if Game.history.size() > 0:
		var lines := []
		for h in Game.history.slice(maxi(0, Game.history.size() - 7)):
			lines.append("Day %d: %s profit, %d visitors" % [h["day"], Data.money_str(h["profit"]), h["visitors"]])
		v.add_child(_lbl("Recent days:\n" + "\n".join(lines), 13, C_DIM))


func _on_day_ended(r: Dictionary) -> void:
	if r.get("bankrupt", false):
		return
	var v := _popup(540)
	v.add_child(_lbl("End of Day %d" % r["day"], 26, C_GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	for line in r["lines"]:
		var a := _lbl(line[0], 15)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(a)
		var val: float = line[1]
		grid.add_child(_lbl(Data.money_str(val), 15, C_GOOD if val > 0 else (C_BAD if val < 0 else C_DIM)))
	v.add_child(grid)
	v.add_child(_sep())
	var profit: float = r["profit"]
	v.add_child(_lbl("Profit today: %s   ·   Bank: %s" % [Data.money_str(profit), Data.money_str(r["money"])], 18, C_GOOD if profit >= 0 else C_BAD))
	var rating_change: float = r["rating"] - r["rating_old"]
	v.add_child(_lbl("Visitors: %d · Happiness: %d%% · Rating %.1f★ (%s%.2f)" % [r["visitors"], int(r["satisfaction"] * 100), r["rating"], "+" if rating_change >= 0 else "", rating_change], 15))
	var comps: Dictionary = r["complaints"]
	if comps.size() > 0:
		var keys := comps.keys()
		keys.sort_custom(func(a, b): return comps[a] > comps[b])
		var parts := []
		for k in keys.slice(0, 3):
			parts.append("\"%s\" (%d)" % [k, comps[k]])
		v.add_child(_lbl("Top complaints: " + ", ".join(parts), 14, C_DIM))
	for e in r["events"]:
		v.add_child(_lbl("• " + e, 15, C_BAD if e.begins_with("WARNING") else C_INFO))
	var b := _btn("Start Day %d ▶" % (r["day"] + 1), func():
		close_popup()
		Game.start_next_day())
	b.custom_minimum_size = Vector2(0, 44)
	v.add_child(b)


func _on_game_over(reason: String) -> void:
	main.exit_shop()
	var v := _popup(480)
	var t := _lbl("BANKRUPT", 40, C_BAD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(_lbl(reason, 16))
	v.add_child(_lbl("You lasted %d days and reached owner level %d." % [Game.day, Game.level], 15, C_DIM))
	v.add_child(_btn("Start a new mall", func():
		close_popup()
		Game.new_game()))
	v.add_child(_btn("Quit", func(): get_tree().quit()))
