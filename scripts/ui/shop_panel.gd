class_name ShopPanel
extends Control
## Haven Depot (spec step 5 upgrade shop), shown inside one player's HUD and
## driven only by that player's device: repairs, repair kits, upgrade tracks
## (Hull Strength, Cannon Count, Sail Speed, Ramming Damage, ...) and new hulls.
## Purchases come out of the shared treasury.

const TABS: Array[String] = ["REPAIRS", "UPGRADES", "SHIPWRIGHT"]
const W := 620.0
const H := 470.0

var ship: PlayerShip
var tab := 0
var sel := 0
var _items: Array = []
var _font: Font
var _bold: Font
var _cooldown := 0.0
var _was_visible := false
var _flash := 0.0
var _flash_ok := true


func _ready() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_font = ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.variation_embolden = 0.9
	_bold = fv


func bind(p_ship: PlayerShip) -> void:
	ship = p_ship


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 3.0)
	if not visible or ship == null:
		_was_visible = false
		return
	if not _was_visible:
		_was_visible = true
		_cooldown = 0.2   # ignore the key press that opened the depot
		sel = 0
	_rebuild()
	if _cooldown > 0.0:
		_cooldown -= delta
		queue_redraw()
		return
	var inp := ship.input
	if inp.just_pressed("menu_down"):
		sel = (sel + 1) % _items.size()
		Sfx.ui("ui_move", -10.0)
	elif inp.just_pressed("menu_up"):
		sel = (sel - 1 + _items.size()) % _items.size()
		Sfx.ui("ui_move", -10.0)
	elif inp.just_pressed("menu_right"):
		tab = (tab + 1) % TABS.size()
		sel = 0
		Sfx.ui("ui_move", -8.0)
	elif inp.just_pressed("menu_left"):
		tab = (tab - 1 + TABS.size()) % TABS.size()
		sel = 0
		Sfx.ui("ui_move", -8.0)
	elif inp.just_pressed("menu_accept"):
		_activate()
	elif inp.just_pressed("menu_back") or inp.just_pressed("interact"):
		ship.shop_open = false
		Sfx.ui("ui_move", -6.0)
	sel = clampi(sel, 0, maxi(0, _items.size() - 1))
	queue_redraw()


func _activate() -> void:
	if _items.is_empty():
		return
	var it: Array = _items[sel]
	var cost: int = it[2]
	if not it[3]:
		Sfx.ui("ui_error", -6.0)
		_flash = 1.0
		_flash_ok = false
		return
	if cost > 0 and not GameManager.spend(cost):
		Sfx.ui("ui_error", -6.0)
		GameManager.notify(ship.idx, "Not enough gold in the treasury.", Color("ff8a7a"))
		_flash = 1.0
		_flash_ok = false
		return
	_do(String(it[4]), String(it[5]))
	_flash = 1.0
	_flash_ok = true
	GameManager.profile_changed.emit(ship.idx)


func _do(action: String, arg: String) -> void:
	var prof = ship.profile
	match action:
		"repair":
			ship.hp = float(ship.stats["max_hp"])
			Sfx.ui("repair", -2.0)
		"kit":
			prof.repair_kits += 1
			Sfx.ui("coin", -4.0)
		"close":
			ship.shop_open = false
		"upgrade":
			prof.upgrades[arg] = int(prof.upgrades[arg]) + 1
			ship.apply_profile()
			Sfx.ui("ui_ok", -2.0)
			GameManager.notify(ship.idx, "Upgraded %s to Lv %d" % [ShipDB.upgrade_def(arg)["name"], int(prof.upgrades[arg])], Color("7dff9a"))
		"hull":
			if not prof.owned_hulls.has(arg):
				prof.owned_hulls.append(arg)
			prof.hull_id = arg
			ship.apply_profile(true)
			Sfx.ui("bell", -4.0)
			GameManager.notify(-1, "%s now sails a %s!" % [ship.display_name, ShipDB.HULLS[arg]["name"]], U.PLAYER_COLORS[ship.idx])


## Rows: [label, detail, cost (-1 = none), enabled, action, arg]
func _rebuild() -> void:
	_items.clear()
	var prof = ship.profile
	match tab:
		0:
			var missing := float(ship.stats["max_hp"]) - ship.hp
			var tier := float(ShipDB.HULLS[prof.hull_id]["tier"])
			var cost := int(ceil(missing * ShipDB.REPAIR_COST_PER_HP * (0.8 + 0.2 * tier)))
			if missing < 1.0:
				_items.append(["Repair hull", "The hull is sound.", -1, false, "", ""])
			else:
				_items.append(["Repair hull", "Restore %d hull points" % int(missing), cost, true, "repair", ""])
			var kits: int = prof.repair_kits
			_items.append(["Buy repair kit", "Field repair or rescue at sea (%d/%d)" % [kits, ShipDB.MAX_REPAIR_KITS],
				ShipDB.REPAIR_KIT_COST, kits < ShipDB.MAX_REPAIR_KITS, "kit", ""])
			_items.append(["Crew", "%d / %d hands aboard (recruited free at Haven)" % [ship.crew, int(ship.stats["crew"])], -1, false, "", ""])
			_items.append(["Set sail", "Close the Depot", -1, true, "close", ""])
		1:
			for u in ShipDB.UPGRADES:
				var id: String = u["id"]
				var lv: int = int(prof.upgrades[id])
				var maxed := lv >= int(u["max"])
				var detail: String = u["desc"]
				var capped := false
				if id == "cannons":
					var h: Dictionary = ShipDB.HULLS[prof.hull_id]
					capped = int(h["cannons"]) + lv >= int(h["max_cannons"])
					detail += "  - now %d per side" % int(ship.stats["cannons"])
					if capped and not maxed:
						detail = "At this hull's gun-deck limit (%d). Try a bigger hull." % int(h["max_cannons"])
				var cost := -1 if maxed else ShipDB.upgrade_cost(id, lv)
				var label := "%s  Lv %d/%d" % [u["name"], lv, int(u["max"])]
				_items.append([label, "MAXED" if maxed else detail, cost, not maxed and not capped, "upgrade", id])
		2:
			for hid in ShipDB.PLAYER_HULL_ORDER:
				var h: Dictionary = ShipDB.HULLS[hid]
				var owned: bool = prof.owned_hulls.has(hid)
				var current: bool = prof.hull_id == hid
				var st := ShipDB.build_stats(hid, prof.upgrades)
				var detail := "%s  HP %d  %.0fkn  %d guns/side  crew %d  armor %d%%" % [h["desc"], int(st["max_hp"]),
					U.knots(float(st["max_speed"])), int(st["cannons"]), int(st["crew"]), int(float(st["armor"]) * 100.0)]
				var label := "%s%s" % [h["name"], "  (sailing)" if current else ("  (owned)" if owned else "")]
				var cost := -1 if owned else int(h["cost"])
				_items.append([label, detail, cost, not current, "hull", hid])


func _text(s: String, at: Vector2, fsize: int, color: Color, bold := false) -> void:
	var f := _bold if bold else _font
	draw_string_outline(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, 0.6))
	draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)


func _draw() -> void:
	if ship == null:
		return
	var col: Color = U.PLAYER_COLORS[ship.idx]
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.075, 0.05, 0.94))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.75, 0.45, 0.9), false, 2.5)
	draw_rect(Rect2(Vector2(0, 0), Vector2(size.x, 6)), col)
	_text("HAVEN DEPOT", Vector2(20, 40), 28, Color("ffe7a8"), true)
	_text("Treasury: %s gold" % U.fmt_gold(GameManager.treasury), Vector2(size.x - 250, 38), 18, Color("ffd34d"), true)
	# Tabs
	var tx := 20.0
	for i in TABS.size():
		var tw := _font.get_string_size(TABS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 26
		var r := Rect2(tx, 56, tw, 30)
		draw_rect(r, Color(col, 0.85) if i == tab else Color(1, 1, 1, 0.08))
		_text(TABS[i], Vector2(tx + 13, 77), 17, Color.WHITE if i == tab else Color(1, 1, 1, 0.55), true)
		tx += tw + 8
	_text("[%s] tabs" % ship.input.glyph("menu_tab"), Vector2(tx + 6, 76), 13, Color(1, 1, 1, 0.45))
	# Items
	var y := 100.0
	var row_h := minf(44.0, (size.y - 150.0) / maxf(1.0, float(_items.size())))
	for i in _items.size():
		var it: Array = _items[i]
		var r := Rect2(16, y, size.x - 32, row_h - 4)
		if i == sel:
			var fc := Color(col, 0.35)
			if _flash > 0.0:
				fc = fc.lerp(Color(0.3, 1, 0.4, 0.5) if _flash_ok else Color(1, 0.2, 0.2, 0.5), _flash)
			draw_rect(r, fc)
			draw_rect(r, Color(col), false, 1.5)
		var enabled: bool = it[3]
		var tc := Color.WHITE if enabled else Color(1, 1, 1, 0.45)
		_text(String(it[0]), r.position + Vector2(10, 18), 17, tc, true)
		var detail := String(it[1])
		if detail.length() > 78:
			detail = detail.substr(0, 76) + ".."
		_text(detail, r.position + Vector2(10, 36), 13, Color(0.85, 0.82, 0.75, 0.9 if enabled else 0.5))
		var cost: int = it[2]
		if cost > 0:
			var cs := "%s g" % U.fmt_gold(cost)
			var cw := _font.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			_text(cs, Vector2(r.end.x - cw - 12, r.position.y + 20), 17, Color("ffd34d") if GameManager.can_afford(cost) else Color("ff6b5b"), true)
		y += row_h
	var hint := "[%s] select   [%s] buy   [%s] leave" % [ship.input.glyph("menu_nav"), ship.input.glyph("menu_accept"), ship.input.glyph("menu_back")]
	_text(hint, Vector2(20, size.y - 18), 15, Color(1, 1, 1, 0.6))
