extends HBoxContainer

signal sequence_changed(actions: Dictionary)

const Slot = preload("res://scripts/ui/sequence_slot.gd")
const Rules = preload("res://scripts/core/rules.gd")
const ActionSequence = preload("res://scripts/core/action_sequence.gd")
const ABILITIES = ["fireball", "fireball_full", "shield", "qingyun_sword"]

var actions: Dictionary = {}
var slots: Array = []
var editable: bool = true
var side: int = 0
var active_slot: int = -1
var picker: PopupMenu
var picked_action: String = ""
var add_button: Button


func _init() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size.y = 56


func _ready() -> void:
	picker = PopupMenu.new()
	add_child(picker)
	picker.id_pressed.connect(choose_action)
	add_button = Button.new()
	add_button.text = "+"
	add_button.custom_minimum_size = Vector2(56, 56)
	add_button.pressed.connect(func(): open_picker(""))
	add_child(add_button)
	refresh()


func set_actions(definition: Dictionary) -> void:
	actions = ActionSequence.instantiate(definition, get_instance_id())
	refresh()


func get_actions() -> Dictionary:
	return ActionSequence.definitions(actions)


func get_order() -> Array:
	return actions.keys()


func set_editable(value: bool) -> void:
	editable = value
	if not editable and picker != null:
		picker.hide()
	refresh()


func set_active(index: int) -> void:
	if active_slot != index:
		active_slot = index
		refresh()


func refresh() -> void:
	while slots.size() > actions.size():
		var old: Control = slots.pop_back()
		remove_child(old)
		old.queue_free()
	while slots.size() < actions.size():
		var slot = Slot.new()
		slot.bar = self
		slot.pressed.connect(on_icon_pressed.bind(slot))
		add_child(slot)
		move_child(slot, slots.size())
		slots.append(slot)
	var keys: Array = actions.keys()
	var can_add: bool = editable and actions.size() < ABILITIES.size()
	var icon_width: int = 44 if actions.size() + int(can_add) >= 4 else 56
	add_theme_constant_override("separation", 4)
	for i in range(slots.size()):
		var slot: Button = slots[i]
		var key: String = keys[i]
		slot.slot_index = i
		slot.action_key = key
		slot.action = "normal" if key == "fireball" else ("full" if key == "fireball_full" else key)
		slot.custom_minimum_size.x = icon_width
		slot.highlighted = i == active_slot
		slot.disabled = not editable
		slot.mouse_default_cursor_shape = Control.CURSOR_DRAG if editable else Control.CURSOR_ARROW
		slot.tooltip_text = Rules.name(actions[key])
		slot.queue_redraw()
	if add_button != null:
		add_button.visible = can_add
		add_button.custom_minimum_size.x = icon_width


func on_icon_pressed(slot: Button) -> void:
	open_picker(slot.action_key)


func drag_payload(action_key: String) -> Dictionary:
	return {"kind": "cast_sequence", "source": get_instance_id(), "action_key": action_key}


func accepts_drag(data: Variant) -> bool:
	if not editable or not data is Dictionary:
		return false
	return data.get("kind", "") == "cast_sequence" and data.get("source", 0) == get_instance_id() and actions.has(data.get("action_key", ""))


func move_action(action_key: String, destination: int) -> void:
	if not editable:
		return
	actions = ActionSequence.move(actions, action_key, destination)
	refresh()
	sequence_changed.emit(get_actions())


func add_action(ability: String) -> void:
	if not editable or ability not in ABILITIES:
		return
	if not actions.has(ability):
		actions[ability] = ActionSequence.instantiate({ability: {}}, get_instance_id())[ability]
	refresh()
	sequence_changed.emit(get_actions())


func open_picker(action_key: String) -> void:
	if not editable or picker == null or get_viewport().gui_is_dragging():
		return
	picked_action = action_key
	picker.clear()
	if action_key.is_empty():
		for i in range(ABILITIES.size()):
			if not actions.has(ABILITIES[i]):
				picker.add_item(Rules.name(ABILITIES[i]), i)
	if not action_key.is_empty():
		if picker.item_count > 0:
			picker.add_separator()
		picker.add_item("移除", 99)
	if picker.item_count == 0:
		return
	var origin: Control = add_button
	if not action_key.is_empty():
		origin = slots[actions.keys().find(action_key)]
	picker.position = Vector2i(origin.get_global_rect().position + Vector2(0, 58))
	picker.popup()


func choose_action(index: int) -> void:
	if editable:
		if index == 99 and not picked_action.is_empty():
			actions.erase(picked_action)
			refresh()
			sequence_changed.emit(get_actions())
		elif picked_action.is_empty() and index >= 0 and index < ABILITIES.size():
			add_action(ABILITIES[index])
	if picker != null:
		picker.hide()
