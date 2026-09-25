class_name HUD
extends Control
## Player HUD canvas (lives inside that player's SubViewport, spec 3 / step 6).
## Custom-drawn: hull/crew/sails/speed panel, shared treasury + cargo, reload
## gauges, compass (teammate / bounty / Haven), minimap, off-screen indicators,
## context prompts, message feed and banners. Hosts the Depot shop panel.

const PANEL_BG := Color(0.05, 0.07, 0.1, 0.72)
const PANEL_EDGE := Color(0.85, 0.72, 0.45, 0.55)
const GOLD := Color("ffd34d")

var ui_scale := 1.0
var view: Node
var ship: PlayerShip
var shop: ShopPanel
var _font: Font
var _bold: Font
var _messages: Array = []        # [text, color, life]
var _banner := ""
var _banner_sub := ""
var _banner_t := 0.0
var _t := 0.0
var _gold_shown := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.variation_embolden = 0.9
	_bold = fv
	shop = ShopPanel.new()
	add_child(shop)
	GameManager.message.connect(_on_message)
	GameManager.banner.connect(_on_banner)
	_gold_shown = GameManager.treasury


func bind(p_view: Node, p_ship: PlayerShip) -> void:
	view = p_view
	ship = p_ship
	shop.bind(p_ship)


func _on_message(player_idx: int, text: String, color: Color) -> void:
	if ship == null:
		return
	if player_idx == -1 or player_idx == ship.idx:
		_messages.append([text, color, 6.0])
		if _messages.size() > 6:
			_messages.pop_front()


func _on_banner(text: String, sub: String) -> void:
	_banner = text
	_banner_sub = sub
	_banner_t = 4.5


func _process(delta: float) -> void:
	_t += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	for m in _messages:
		m[2] -= delta
	while _messages.size() > 0 and _messages[0][2] <= 0.0:
		_messages.pop_front()
	_gold_shown = lerpf(_gold_shown, float(GameManager.treasury), 1.0 - exp(-8.0 * delta))
	if ship:
		shop.visible = ship.shop_open
		shop.position = (size - shop.size) * 0.5
	queue_redraw()


# --- Drawing helpers ---------------------------------------------------------------------------

func _text(s: String, at: Vector2, fsize: int, color: Color, bold := false, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := _bold if bold else _font
	draw_string_outline(f, at, s, align, width, fsize, 4, Color(0, 0, 0, 0.75 * color.a))
	draw_string(f, at, s, align, width, fsize, color)


func _text_w(s: String, fsize: int, bold := false) -> float:
	return (_bold if bold else _font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x


func _panel(r: Rect2) -> void:
	draw_rect(r, PANEL_BG)
	draw_rect(r, PANEL_EDGE, false, 1.5)


func _bar(r: Rect2, ratio: float, col: Color, back := Color(0, 0, 0, 0.55)) -> void:
	draw_rect(r, back)
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(ratio, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)


func _draw() -> void:
	if ship == null or not is_instance_valid(ship) or size.x < 320.0 or size.y < 320.0:
		return
	var col: Color = U.PLAYER_COLORS[ship.idx]
	_draw_status(col)
	_draw_treasury()
	_draw_reload_gauge(col)
	_draw_compass(col)
	_draw_minimap(col)
	_draw_offscreen_markers()
	_draw_prompts()
	_draw_messages()
	_draw_center_status()
	_draw_banner()
	# Thin frame in the player's colour to tell the halves apart
	draw_rect(Rect2(Vector2.ZERO, size), Color(col, 0.55), false, 3.0)


func _draw_status(col: Color) -> void:
	var r := Rect2(14, 14, 330, 150)
	_panel(r)
	draw_rect(Rect2(r.position, Vector2(6, r.size.y)), col)
	_text("%s" % ship.display_name, r.position + Vector2(18, 30), 22, col, true)
	_text(String(ship.stats["name"]), r.position + Vector2(18 + _text_w(ship.display_name, 22, true) + 10, 30), 17, Color(0.9, 0.88, 0.8))
	# Hull
	var ratio := ship.hull_ratio()
	var hc := Color("4cd964") if ratio > 0.5 else (Color("ffcc00") if ratio > 0.25 else Color("ff3b30"))
	_bar(Rect2(r.position + Vector2(18, 44), Vector2(296, 18)), ratio, hc)
	_text("HULL  %d / %d" % [int(ceil(ship.hp)), int(ship.stats["max_hp"])], r.position + Vector2(24, 59), 15, Color.WHITE)
	# Crew + kits + armor
	var crew_ratio := float(ship.crew) / maxf(1.0, float(ship.stats["crew"]))
	_text("CREW %d/%d" % [ship.crew, int(ship.stats["crew"])], r.position + Vector2(18, 88), 16, Color("cfe8ff") if crew_ratio > 0.6 else Color("ffb347"))
	_text("KITS %d" % ship.profile.repair_kits, r.position + Vector2(140, 88), 16, Color("7dff9a"))
	_text("ARMOR %d%%" % int(float(ship.stats["armor"]) * 100.0), r.position + Vector2(214, 88), 16, Color(0.8, 0.82, 0.86))
	# Sail gear pips
	var gx := r.position.x + 18
	var gy := r.position.y + 104
	for i in 4:
		var on := i == ship.sail_index
		var pr := Rect2(gx + i * 58, gy, 52, 18)
		draw_rect(pr, Color(col, 0.85) if on else Color(1, 1, 1, 0.1))
		draw_rect(pr, Color(1, 1, 1, 0.3), false, 1.0)
		var lbl: String = ["REV", "STOP", "HALF", "FULL"][i]
		_text(lbl, pr.position + Vector2(pr.size.x * 0.5 - _text_w(lbl, 13, true) * 0.5, 14), 13, Color.WHITE if on else Color(1, 1, 1, 0.5), true)
	_text("%.1f kn" % absf(U.knots(ship.forward_speed())), Vector2(gx + 238, gy + 15), 16, Color(0.9, 0.95, 1.0))
	_text("[%s/%s] sails" % [ship.input.glyph("sail_up"), ship.input.glyph("sail_down")], r.position + Vector2(18, 142), 13, Color(1, 1, 1, 0.45))


func _draw_treasury() -> void:
	var w := 250.0
	var r := Rect2(size.x - w - 14, 14, w, 104)
	_panel(r)
	draw_circle(r.position + Vector2(24, 26), 11, GOLD)
	draw_circle(r.position + Vector2(24, 26), 7, GOLD.darkened(0.25))
	_text(U.fmt_gold(int(round(_gold_shown))), r.position + Vector2(44, 34), 24, GOLD, true)
	_text("shared", r.position + Vector2(w - 60, 32), 13, Color(1, 1, 1, 0.5))
	var hold := int(ship.stats["hold"])
	var n: int = ship.profile.cargo.size()
	_text("CARGO %d/%d  (%dg)" % [n, hold, ship.profile.cargo_value()], r.position + Vector2(14, 62), 16, Color("e8c79a") if n < hold else Color("ffb347"))
	var stars := ""
	for i in mini(GameManager.notoriety, 10):
		stars += "*"
	_text("NOTORIETY %d %s" % [GameManager.notoriety, stars], r.position + Vector2(14, 88), 14, Color("ff9a8a"))


func _draw_reload_gauge(col: Color) -> void:
	var c := Vector2(size.x * 0.5, size.y - 74)
	var r := Rect2(c - Vector2(150, 58), Vector2(300, 116))
	_panel(r)
	# Ship silhouette pointing up
	var hull := Ship.hull_polygon(58.0, 22.0, "brig")
	var pts := PackedVector2Array()
	for p in hull:
		pts.append(c + Vector2(p.y, -p.x))
	draw_colored_polygon(pts, Color(0.55, 0.38, 0.22))
	draw_polyline(PackedVector2Array(Array(pts) + [pts[0]]), Color(1, 1, 1, 0.4), 1.5, true)
	for side in ["port", "starboard"]:
		var bat: Battery = ship.batteries[side]
		var sx := -1.0 if side == "port" else 1.0
		var bar := Rect2(c + Vector2(sx * 32.0 - (18.0 if sx < 0 else 0.0), -40), Vector2(18, 80))
		var prog := bat.progress() if not ship.dismasted else 0.0
		draw_rect(bar, Color(0, 0, 0, 0.55))
		var fill_h := bar.size.y * prog
		var ready := bat.is_ready() and not ship.dismasted
		draw_rect(Rect2(bar.position + Vector2(0, bar.size.y - fill_h), Vector2(bar.size.x, fill_h)), Color(col, 0.95) if ready else Color(0.75, 0.75, 0.75, 0.7))
		draw_rect(bar, Color(1, 1, 1, 0.3), false, 1.0)
		for i in bat.count:
			var y := bar.position.y + 6 + i * (bar.size.y - 12) / maxf(1.0, float(bat.count - 1)) if bat.count > 1 else bar.get_center().y
			draw_circle(Vector2(bar.position.x + (bar.size.x + 12 if sx > 0 else -12), y), 4.0, Color(0.15, 0.15, 0.17) if not ready else Color(1, 0.85, 0.4))
		var lbl := "PORT [%s]" % ship.input.glyph("fire_port") if side == "port" else "STBD [%s]" % ship.input.glyph("fire_starboard")
		var lx := r.position.x + 10 if sx < 0 else r.end.x - 10 - _text_w(lbl, 13, true)
		_text(lbl, Vector2(lx, r.position.y + 18), 13, Color.WHITE if ready else Color(1, 1, 1, 0.5), true)
		var status := "READY" if ready else "%.1fs" % (bat.timer * ship.reload_mult)
		if ship.dismasted:
			status = "DOWN"
		_text(status, Vector2(lx, r.position.y + 36), 15, Color(col) if ready else Color(1, 1, 1, 0.6), true)
	var bow: Battery = ship.batteries["bow"]
	if bow.count > 0:
		var bar2 := Rect2(c + Vector2(-20, -54), Vector2(40, 8))
		_bar(bar2, bow.progress(), Color(col) if bow.is_ready() else Color(0.7, 0.7, 0.7))
		_text("BOW [%s]" % ship.input.glyph("fire_bow"), Vector2(r.end.x - 90, r.end.y - 10), 12, Color(1, 1, 1, 0.6))
	var crew_pen := ship.reload_mult
	if crew_pen > 1.05:
		_text("short-handed: reload x%.1f" % crew_pen, Vector2(r.position.x + 10, r.end.y - 10), 12, Color("ffb347"))


func _draw_compass(col: Color) -> void:
	var rad := 62.0
	var c := Vector2(14 + rad + 34, size.y - 14 - rad - 30)
	draw_circle(c, rad + 10, PANEL_BG)
	draw_arc(c, rad + 10, 0, TAU, 48, PANEL_EDGE, 1.5, true)
	draw_arc(c, rad, 0, TAU, 48, Color(1, 1, 1, 0.2), 1.0, true)
	for i in 4:
		var a := -PI * 0.5 + i * PI * 0.5
		var lbl: String = ["N", "E", "S", "W"][i]
		var p := c + Vector2.from_angle(a) * (rad - 12)
		_text(lbl, p + Vector2(-_text_w(lbl, 14, true) * 0.5, 6), 14, Color(1, 0.4, 0.35) if i == 0 else Color(1, 1, 1, 0.7), true)
	for i in 16:
		var a := TAU * i / 16.0
		draw_line(c + Vector2.from_angle(a) * (rad - 2), c + Vector2.from_angle(a) * (rad + 3), Color(1, 1, 1, 0.3), 1.0)
	# Own heading
	var h := Vector2.from_angle(ship.rotation)
	draw_line(c, c + h * (rad - 22), Color(col, 0.9), 3.0, true)
	draw_circle(c, 4, col)
	var markers := []
	var mate: PlayerShip = GameManager.world.teammate_of(ship) if GameManager.world else null
	if mate != null:
		markers.append([mate.global_position, U.PLAYER_COLORS[mate.idx], "P%d" % (mate.idx + 1)])
	var d = GameManager.director
	if d != null and d.bounty_ship != null and is_instance_valid(d.bounty_ship):
		markers.append([d.bounty_ship.global_position, Color("ff3b30"), "$"])
	if GameManager.world and GameManager.world.port:
		markers.append([GameManager.world.port.global_position, Color("7dff9a"), "H"])
	for m in markers:
		var to: Vector2 = (m[0] as Vector2) - ship.global_position
		var dirv := to.normalized()
		var p: Vector2 = c + dirv * (rad + 6)
		var mc: Color = m[1]
		var tri := PackedVector2Array([p + dirv * 11, p + dirv.orthogonal() * 7 - dirv * 3, p - dirv.orthogonal() * 7 - dirv * 3])
		draw_colored_polygon(tri, mc)
		var lp := c + dirv * (rad + 28)
		_text(String(m[2]), lp + Vector2(-_text_w(String(m[2]), 14, true) * 0.5, 5), 14, mc, true)
	# Distance readouts
	var x := c.x + rad + 18
	var lines := []
	for m in markers:
		var dist := ((m[0] as Vector2) - ship.global_position).length() / U.M
		var tag: String = m[2]
		var nm := tag
		if tag == "$":
			nm = "Bounty"
		elif tag == "H":
			nm = "Haven"
		lines.append([("%s %dm" % [nm, int(dist)]), m[1]])
	for i in lines.size():
		_text(lines[i][0], Vector2(x, c.y - 20 + i * 18), 14, lines[i][1])


func _draw_minimap(col: Color) -> void:
	var w := GameManager.world
	if w == null:
		return
	var s := 170.0
	var r := Rect2(size.x - s - 14, size.y - s - 14, s, s)
	_panel(r)
	var k := s / U.WORLD_SIZE.x
	var to_map := func(p: Vector2) -> Vector2: return r.position + p * k
	for lane in w.lanes:
		for i in lane.size() - 1:
			draw_line(to_map.call(lane[i]), to_map.call(lane[i + 1]), Color(1, 1, 1, 0.08), 1.0)
	for isl in w.islands:
		draw_circle(to_map.call(isl.position), maxf(2.0, isl.radius * k), Color("c9b47a"))
	draw_arc(to_map.call(w.port.global_position), Port.SAFE_RADIUS * k, 0, TAU, 24, Color(0.5, 1, 0.7, 0.5), 1.0)
	for f in w.forts:
		var fp: Vector2 = to_map.call(f.global_position)
		draw_rect(Rect2(fp - Vector2(4, 4), Vector2(8, 8)), Color("ff6b5b") if not f.destroyed else Color(0.4, 0.4, 0.4))
	for e in w.enemies:
		if not is_instance_valid(e) or e.sinking:
			continue
		var near := false
		for p in w.players:
			if is_instance_valid(p) and p.global_position.distance_to(e.global_position) < 160.0 * U.M:
				near = true
		if e.is_bounty:
			var bp: Vector2 = to_map.call(e.global_position)
			draw_circle(bp, 5, Color("ff3b30"))
			draw_arc(bp, 8 + 2 * sin(_t * 5.0), 0, TAU, 12, Color("ff3b30"), 1.5)
		elif near:
			var c2 := Color(0.85, 0.85, 0.85) if e.state == EnemyShip.AI.PRIZE else (Color("e8c79a") if e.role == "merchant" else Color("ff8a7a"))
			draw_circle(to_map.call(e.global_position), 2.5, c2)
	for p in w.players:
		if not is_instance_valid(p) or not p.is_active():
			continue
		var pp: Vector2 = to_map.call(p.global_position)
		var f := Vector2.from_angle(p.rotation)
		var pc: Color = U.PLAYER_COLORS[p.idx]
		draw_colored_polygon(PackedVector2Array([pp + f * 7, pp + f.orthogonal() * 4 - f * 4, pp - f.orthogonal() * 4 - f * 4]), pc)
		if p == ship:
			draw_arc(pp, 9, 0, TAU, 12, Color(pc, 0.6), 1.0)
	_text("SEA CHART", r.position + Vector2(6, 14), 11, Color(1, 1, 1, 0.45), true)


func _draw_offscreen_markers() -> void:
	if view == null or view.camera == null:
		return
	var cam: Camera2D = view.camera
	var center := cam.get_screen_center_position()
	var items := []
	var mate: PlayerShip = GameManager.world.teammate_of(ship) if GameManager.world else null
	if mate != null:
		items.append([mate.global_position, U.PLAYER_COLORS[mate.idx], "P%d%s" % [mate.idx + 1, " SOS" if mate.dismasted else ""]])
	var d = GameManager.director
	if d != null and d.bounty_ship != null and is_instance_valid(d.bounty_ship):
		items.append([d.bounty_ship.global_position, Color("ff3b30"), "BOUNTY"])
	var margin := 40.0
	for it in items:
		var sp: Vector2 = ((it[0] as Vector2) - center) * cam.zoom / ui_scale + size * 0.5
		var inner := Rect2(Vector2(margin, 190.0), Vector2(size.x - margin * 2, size.y - 190.0 - 270.0))
		if inner.has_point(sp):
			continue
		var dirv := (sp - size * 0.5).normalized()
		# Clamp to the inner rect border
		var half := inner.size * 0.5
		var cen := inner.get_center()
		var tx := half.x / maxf(0.001, absf(dirv.x))
		var ty := half.y / maxf(0.001, absf(dirv.y))
		var p := cen + dirv * minf(tx, ty)
		var mc: Color = it[1]
		var pulse := 1.0 + 0.12 * sin(_t * 6.0)
		draw_colored_polygon(PackedVector2Array([p + dirv * 16 * pulse, p + dirv.orthogonal() * 10 - dirv * 6, p - dirv.orthogonal() * 10 - dirv * 6]), mc)
		var dist := ((it[0] as Vector2) - ship.global_position).length() / U.M
		var lbl := "%s %dm" % [it[2], int(dist)]
		_text(lbl, p - dirv * 22 - Vector2(_text_w(lbl, 14, true) * 0.5, -5), 14, mc, true)


func _draw_prompts() -> void:
	var y := size.y - 150.0
	for i in range(ship.prompts.size() - 1, -1, -1):
		var p: String = ship.prompts[i]
		var w := _text_w(p, 18, true) + 24
		var r := Rect2(size.x * 0.5 - w * 0.5, y - 26, w, 30)
		draw_rect(r, Color(0, 0, 0, 0.55))
		draw_rect(r, Color(1, 0.85, 0.4, 0.6), false, 1.0)
		_text(p, Vector2(r.position.x + 12, y - 5), 18, Color("fff3c4"), true)
		y -= 36.0
	# Boarding odds preview
	if ship.boarding_target == null and not ship.dismasted and GameManager.world:
		var b: Ship = GameManager.world.find_boardable(ship)
		if b != null:
			var odds: float = GameManager.world.boarding_odds(b, ship)
			_text("boarding odds %d%%" % int(odds * 100.0), Vector2(size.x * 0.5 - 60, y - 4), 14, Color(1, 1, 1, 0.7))
	if ship.boarding_target != null:
		var ratio := ship.boarding_t / PlayerShip.BOARD_TIME
		_bar(Rect2(size.x * 0.5 - 150, size.y * 0.5 + 60, 300, 16), ratio, Color("ffd34d"))
		_text("BOARDING ACTION", Vector2(size.x * 0.5 - _text_w("BOARDING ACTION", 20, true) * 0.5, size.y * 0.5 + 52), 20, Color("ffd34d"), true)


func _draw_messages() -> void:
	var y := 196.0
	for m in _messages:
		var a := clampf(float(m[2]), 0.0, 1.0)
		var c: Color = m[1]
		c.a = a
		_text(String(m[0]), Vector2(18, y), 16, c)
		y += 22.0


func _draw_center_status() -> void:
	var cy := size.y * 0.32
	if ship.respawn_timer >= 0.0 or (ship.sinking and ship.dismasted):
		var s := "YOUR SHIP WENT DOWN"
		_text(s, Vector2(size.x * 0.5 - _text_w(s, 34, true) * 0.5, cy), 34, Color("ff6b5b"), true)
		var s2 := "A new ship is being readied at Haven..."
		_text(s2, Vector2(size.x * 0.5 - _text_w(s2, 18) * 0.5, cy + 32), 18, Color.WHITE)
	elif ship.dismasted:
		var s := "DISMASTED  -  SINKING IN %ds" % int(ceil(ship.dismast_timer))
		_text(s, Vector2(size.x * 0.5 - _text_w(s, 30, true) * 0.5, cy), 30, Color("ff6b5b"), true)
		var s2 := "Wait for a tow to Haven, or use a repair kit [%s]" % ship.input.glyph("interact")
		if ship.towed_by != null:
			s2 = "Under tow! Hold on..."
		_text(s2, Vector2(size.x * 0.5 - _text_w(s2, 18) * 0.5, cy + 30), 18, Color.WHITE)
	elif ship.hull_ratio() < 0.25 and fmod(_t, 1.0) < 0.6:
		var s := "HULL CRITICAL"
		_text(s, Vector2(size.x * 0.5 - _text_w(s, 26, true) * 0.5, cy), 26, Color("ff3b30"), true)


func _draw_banner() -> void:
	if _banner_t <= 0.0:
		return
	var a := clampf(_banner_t, 0.0, 1.0) * clampf((4.5 - _banner_t) * 4.0, 0.0, 1.0)
	var y := size.y * 0.42
	var w := maxf(_text_w(_banner, 40, true), _text_w(_banner_sub, 18)) + 60
	draw_rect(Rect2(size.x * 0.5 - w * 0.5, y - 46, w, 80), Color(0.04, 0.05, 0.08, 0.7 * a))
	draw_rect(Rect2(size.x * 0.5 - w * 0.5, y - 46, w, 80), Color(0.9, 0.75, 0.4, 0.8 * a), false, 2.0)
	_text(_banner, Vector2(size.x * 0.5 - _text_w(_banner, 40, true) * 0.5, y), 40, Color(1, 0.85, 0.4, a), true)
	_text(_banner_sub, Vector2(size.x * 0.5 - _text_w(_banner_sub, 18) * 0.5, y + 26), 18, Color(1, 1, 1, a))
