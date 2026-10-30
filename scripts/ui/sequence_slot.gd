extends Button

var bar: Control
var slot_index: int = 0
var action: String = "normal"
var action_key: String = "fireball"
var highlighted: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(56, 56)


func _get_drag_data(_position: Vector2) -> Variant:
	if bar == null or not bar.editable:
		return null
	var preview := get_script().new() as Button
	preview.action = action
	preview.slot_index = slot_index
	preview.size = custom_minimum_size
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.modulate.a = 0.85
	set_drag_preview(preview)
	return bar.drag_payload(action_key)


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return bar != null and bar.accepts_drag(data)


func _drop_data(_position: Vector2, data: Variant) -> void:
	if bar != null and bar.accepts_drag(data):
		bar.move_action(str(data.action_key), slot_index)


func _draw() -> void:
	var center: Vector2 = size * 0.5 + Vector2(0, 3)
	var color := Color("ed8953")
	match action:
		"normal", "full":
			if action == "full":
				draw_arc(center, 17, 0, TAU, 32, Color("d8af68"), 1.5, true)
			var flame := PackedVector2Array([center + Vector2(0, -17), center + Vector2(11, -3),
				center + Vector2(9, 10), center + Vector2(0, 14), center + Vector2(-10, 7), center + Vector2(-11, -3), center + Vector2(-5, -10), center + Vector2(-3, -1)])
			draw_colored_polygon(flame, color)
			draw_circle(center + Vector2(0, 6), 5, Color("f5c787"))
		"shield":
			var shield := PackedVector2Array([center + Vector2(-14, -13), center + Vector2(0, -17),
				center + Vector2(14, -13), center + Vector2(12, 4), center + Vector2(0, 16), center + Vector2(-12, 4)])
			draw_colored_polygon(shield, Color("50828b"))
			shield.append(shield[0])
			draw_polyline(shield, Color("9dc9cf"), 1.5, true)
			draw_line(center + Vector2(0, -9), center + Vector2(0, 8), Color("a0c5c8"), 2, true)
		"qingyun_sword":
			var direction := Vector2(0.66, -0.75)
			var across := Vector2(-direction.y, direction.x)
			var blade := PackedVector2Array([center + direction * 20, center + across * 4,
				center - direction * 9, center - across * 4])
			draw_colored_polygon(blade, Color("abd1c1"))
			draw_line(center - direction * 9 - across * 8, center - direction * 9 + across * 8, Color("b29b6e"), 3, true)
			draw_line(center - direction * 9, center - direction * 19, Color("6e887b"), 4, true)
	var font: Font = get_theme_font("font")
	draw_string(font, Vector2(5, 13), str(slot_index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("9ba79a"))
	if highlighted:
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color("c4aa71"), false, 2)
