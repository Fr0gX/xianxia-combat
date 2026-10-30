extends Control
## Presentation only. Projectile positions derive from simulation frames.

var battle: RefCounted
var title_font: Font
var body_font: Font
var clock: float = 0.0
var summary_visible: bool = false
const INK = Color("0b171a")
const BRONZE = Color("796b4e")
const PAPER = Color("dfdac8")
const FIRE = Color("ed8953")


func _process(delta: float) -> void:
	clock += delta
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_style_box(panel_style(), Rect2(Vector2.ZERO, size))
	# Mountain silhouettes and a quiet, enclosed cultivation ground.
	for layer in range(3):
		var points := PackedVector2Array([Vector2(0, h * 0.66)])
		for i in range(13):
			var px: float = w * i / 12.0
			var py: float = h * (0.34 + layer * 0.06) + sin(i * 2.1 + layer) * 32 + cos(i * 1.3) * 20
			points.append(Vector2(px, py))
		points.append(Vector2(w, h * 0.8))
		points.append(Vector2(0, h * 0.8))
		draw_colored_polygon(points, Color(0.055 + layer * 0.008, 0.105 + layer * 0.007, 0.115 + layer * 0.007))
	var center := Vector2(w * 0.5, h * 0.66)
	for ring in [1.0, 0.83, 0.5]:
		var points := PackedVector2Array()
		for i in range(97):
			var angle: float = TAU * i / 96.0
			points.append(center + Vector2(cos(angle) * w * 0.43 * ring, sin(angle) * h * 0.13 * ring))
		draw_polyline(points, Color(BRONZE, 0.3 if ring == 1.0 else 0.13), 1.0, true)
	for i in range(12):
		var angle: float = TAU * i / 12.0
		var p1: Vector2 = center + Vector2(cos(angle) * w * 0.38, sin(angle) * h * 0.115)
		var p2: Vector2 = center + Vector2(cos(angle) * w * 0.42, sin(angle) * h * 0.127)
		draw_line(p1, p2, Color(BRONZE, 0.35), 1, true)
	if battle == null or battle.actors.size() != 2:
		return
	var positions := [Vector2(w * 0.22, h * 0.66), Vector2(w * 0.78, h * 0.66)]
	for side in range(2):
		var shields: Array = battle.active_entities(side, "shield")
		for i in range(shields.size()):
			draw_shield(positions[side], shields[i], i)
		draw_cultivator(positions[side], side, h)
		for weapon in battle.active_entities(side, "artifact"):
			draw_weapon(weapon_position(weapon, positions), weapon, side)
	for shot in battle.projectiles:
		var span: int = int(shot.hit_frame) - int(shot.release_frame)
		var progress: float = clampf(float(battle.frame - int(shot.release_frame)) / maxf(span, 1), 0, 1)
		var source: Vector2 = positions[int(shot.side)] + Vector2(0, -55)
		var caster: Dictionary = battle.entities[int(shot.context.source_id)]
		if caster.kind == "artifact":
			source = weapon_position(caster, positions)
		var target: Vector2 = positions[int(shot.target)] + Vector2(0, -55)
		var defenders: Array = battle.defenders(int(shot.target))
		if not defenders.is_empty() and defenders[0].kind == "artifact":
			target = weapon_position(defenders[0], positions)
		var point: Vector2 = source.lerp(target, progress)
		var direction: float = 1 if int(shot.side) == 0 else -1
		var radius: float = 13 if shot.mode == "full" else 8
		for trail in range(9, 0, -1):
			draw_circle(point - Vector2(direction * trail * 6, sin(trail * 1.1) * 2), radius * (1 - trail / 12.0), Color(FIRE, 0.25 * (1 - trail / 10.0)))
		for glow in range(4, 0, -1):
			draw_circle(point, radius + glow * 5, Color(FIRE, 0.025 * (5 - glow)))
		draw_circle(point, radius, FIRE)
		draw_circle(point + Vector2(direction * 2, -1), radius * 0.55, Color("ffdc97"))
	# Recent impacts and floating damage last a fixed number of simulation frames.
	for i in range(maxi(0, battle.events.size() - 18), battle.events.size()):
		var event: Dictionary = battle.events[i]
		var age: int = battle.frame - int(event.frame)
		if event.kind != "damage" or age > 30:
			continue
		var target: Vector2 = positions[int(event.side)] + Vector2(0, -55)
		if battle.entities[int(event.entity_id)].kind == "artifact":
			target = weapon_position(battle.entities[int(event.entity_id)], positions)
		var fade: float = 1.0 - age / 31.0
		draw_arc(target, 18 + age * 1.2, 0, TAU, 32, Color(FIRE, fade * 0.6), 2, true)
		text_at("−" + number(float(event.damage_milli) / 1000.0), target + Vector2(-18, -48 - age * 0.7), 24, Color(FIRE, fade), title_font)
	if battle.finished and not summary_visible:
		var caption: String = {"left_win": "青衫修士胜", "right_win": "赤衣修士胜", "double_ko": "同归于尽", "stalemate": "僵持", "timeout": "未分胜负"}.get(battle.result, "")
		var caption_width: float = title_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		text_at(caption, Vector2((w - caption_width) / 2, h - 40), 20, PAPER, title_font)


func weapon_position(weapon: Dictionary, positions: Array) -> Vector2:
	var side: int = int(weapon.side)
	var home: Vector2 = positions[side] + Vector2(42 if side == 0 else -42, -119)
	var motion: Dictionary = weapon.get("motion", {})
	var time_frame: int = battle.frame
	if not weapon.active:
		motion = weapon.get("ended_motion", {})
		time_frame = int(weapon.presence.end_frame)
	if motion.is_empty():
		return home
	var contact: Vector2 = positions[1 - side] + Vector2(0, -55)
	if time_frame <= int(motion.hit_frame):
		var progress: float = clampf(float(time_frame - int(motion.release_frame)) / maxi(1, int(motion.hit_frame) - int(motion.release_frame)), 0, 1)
		return home.lerp(contact, progress)
	var progress: float = clampf(float(time_frame - int(motion.hit_frame)) / maxi(1, int(motion.return_frame) - int(motion.hit_frame)), 0, 1)
	return contact.lerp(home, progress)


func draw_weapon(position: Vector2, weapon: Dictionary, side: int) -> void:
	var direction := Vector2(0.65 if side == 0 else -0.65, -0.76)
	if not weapon.motion.is_empty():
		direction = Vector2(1 if side == 0 else -1, 0)
		if weapon.motion.state == "returning":
			direction = -direction
		for i in range(1, 5):
			draw_line(position - direction * (18 + i * 5), position - direction * (26 + i * 7), Color(0.55, 0.8, 0.7, 0.2 / i), 2, true)
	elif not weapon.cast.is_empty():
		var cast: Dictionary = weapon.cast
		var progress: float = clampf(float(battle.frame - int(cast.start_frame)) / maxi(1, int(cast.release_frame) - int(cast.start_frame)), 0, 1)
		draw_arc(position, 27, -PI / 2, -PI / 2 + TAU * progress, 24, Color("89cbb8"), 1.5, true)
	var across := Vector2(-direction.y, direction.x)
	var points := PackedVector2Array([position + direction * 24, position + across * 4,
		position - direction * 14, position - across * 4])
	draw_colored_polygon(points, Color("a3c5b8"))
	draw_line(position - direction * 12 - across * 8, position - direction * 12 + across * 8, Color("ad9166"), 3, true)
	draw_line(position - direction * 12, position - direction * 23, Color("667a68"), 4, true)
	draw_line(position + Vector2(-18, 34), position + Vector2(18, 34), Color("203532"), 3)
	draw_line(position + Vector2(-18, 34), position + Vector2(-18 + 36.0 * float(weapon.hp_milli) / maxi(1, int(weapon.max_hp_milli)), 34), Color("8bb6a4"), 3)


func draw_shield(position: Vector2, shield: Dictionary, index: int) -> void:
	var center: Vector2 = position + Vector2(0, -44)
	var radii := Vector2(43 + index * 5, 63 + index * 5)
	draw_ground_shadow(center, radii, Color(0.32, 0.65, 0.72, 0.07))
	var outline := PackedVector2Array()
	for i in range(65):
		var angle: float = TAU * i / 64
		outline.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_polyline(outline, Color(0.47, 0.76, 0.81, 0.6), 1.5, true)
	draw_line(position + Vector2(-24, 19 + index * 5), position + Vector2(24, 19 + index * 5), Color("203532"), 3)
	draw_line(position + Vector2(-24, 19 + index * 5), position + Vector2(-24 + 48.0 * float(shield.hp_milli) / maxi(1, int(shield.max_hp_milli)), 19 + index * 5), Color("7aafb9"), 3)


func draw_cultivator(position: Vector2, side: int, _height: float) -> void:
	var actor: Dictionary = battle.actors[side]
	var alive: bool = actor.hp_milli > 0
	var robe: Color = Color("527d78") if side == 0 else Color("a45c4a")
	if not alive:
		robe = robe.darkened(0.7)
	draw_ground_shadow(position + Vector2(0, 3), Vector2(34, 8), Color(0, 0, 0, 0.28))
	var direction: float = 1 if side == 0 else -1
	var casting: bool = not actor.cast.is_empty() and alive
	if casting:
		var progress: float = float(battle.frame - int(actor.cast.start_frame)) / maxi(1, int(actor.cast.release_frame) - int(actor.cast.start_frame))
		draw_arc(position + Vector2(direction * 24, -57), 9 + progress * 12, -PI / 2, -PI / 2 + TAU * progress, 32, Color(FIRE, 0.75), 2, true)
	var body := PackedVector2Array([position + Vector2(-10, -70), position + Vector2(10, -70), position + Vector2(25, -3), position + Vector2(-26, -3)])
	draw_colored_polygon(body, robe)
	draw_line(position + Vector2(-7, -64), position + Vector2(6, -5), robe.lightened(0.35), 2, true)
	draw_line(position + Vector2(-15, -32), position + Vector2(16, -32), Color("b2a27f"), 3, true)
	draw_circle(position + Vector2(0, -84), 12, Color("bbb09a") if alive else Color("504d43"))
	draw_arc(position + Vector2(0, -87), 12, PI, TAU, 16, Color("192525"), 6, true)
	draw_circle(position + Vector2(-direction * 3, -100), 5, Color("192525"))
	var hand: Vector2 = position + Vector2(direction * (30 if casting else 18), -56 if casting else -35)
	draw_line(position + Vector2(direction * 9, -65), hand, robe.lightened(0.12), 11, true)
	draw_circle(hand, 4, Color("bbb09a"))


func draw_ground_shadow(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(48):
		var angle: float = TAU * i / 48
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)


func text_at(value: String, position: Vector2, font_size: int, color: Color, font: Font) -> void:
	if font != null:
		draw_string(font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.border_color = Color("384137")
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style


func number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else ("%.3f" % value).trim_suffix("0").trim_suffix("0")
