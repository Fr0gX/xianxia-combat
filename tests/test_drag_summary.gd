extends SceneTree

const Battle = preload("res://scripts/core/battle.gd")
var checks: int = 0
var failures: Array = []


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)


func move_mouse(position: Vector2, relative: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(event)
	await process_frame


func mouse_button(position: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(event)
	await process_frame


func run() -> void:
	root.size = Vector2i(1440, 900)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var bar: Control = scene.actor_widgets[0].sequence
	var other: Control = scene.actor_widgets[1].sequence
	check(scene.game_display.is_ancestor_of(bar) and not scene.tech_panel.is_ancestor_of(bar), "Sequence editing lives in the game display")
	check(bar.is_visible_in_tree() and not scene.tech_panel.visible, "Sequence icons are visible with technical drawer closed")
	check(bar.slots.size() == 3 and bar.get_order() == ["shield", "qingyun_sword", "fireball"], "Three unique action instances match default order")
	var start: Vector2 = bar.slots[0].get_global_rect().get_center()
	var target: Vector2 = bar.slots[2].get_global_rect().get_center()
	await move_mouse(start, Vector2.ZERO, false)
	await mouse_button(start, true)
	await move_mouse(start + Vector2(24, 0), Vector2(24, 0), true)
	check(root.gui_is_dragging(), "Mouse movement begins an actual Godot drag")
	await move_mouse(target, target - start - Vector2(24, 0), true)
	await mouse_button(target, false)
	await process_frame
	check(bar.get_order() == ["qingyun_sword", "fireball", "shield"], "Mouse drag reorders the existing action identities")
	check(not bar.picker.visible, "Dragging does not accidentally open the skill picker")
	var foreign: Dictionary = bar.drag_payload("qingyun_sword")
	check(not other.slots[0]._can_drop_data(Vector2.ZERO, foreign), "Another cultivator cannot consume this sequence drag")
	other.slots[0]._drop_data(Vector2.ZERO, foreign)
	check(other.get_order() == ["fireball"], "Opposing action registry has one fireball identity")
	var original_fireball_id: String = bar.actions.fireball.instance_id
	bar.add_button.pressed.emit()
	await process_frame
	check(bar.picker.visible and bar.picker.item_count == 1, "Add picker contains only the missing independent full fireball")
	bar.picker.id_pressed.emit(1)
	check(bar.get_order() == ["qingyun_sword", "fireball", "shield", "fireball_full"], "Normal and full fireballs coexist as separate spell identities")
	bar.add_action("fireball")
	check(bar.actions.size() == 4 and bar.actions.fireball.instance_id == original_fireball_id, "Reusing an owned identity retains its existing instance")
	scene.single_step()
	check(scene.battle.actors[0].cast.ability == "qingyun_sword", "Edited icon order determines first actual cast")
	var locked_order: Array = bar.get_order()
	check(not bar.editable and not bar.slots[0]._can_drop_data(Vector2.ZERO, bar.drag_payload("shield")), "Combat locks drag and drop")
	bar.move_action("qingyun_sword", 2)
	check(bar.get_order() == locked_order, "Locked sequence cannot reorder")
	scene.reset_battle()
	bar.set_actions(scene.defaults.actors[0].actions)
	other.set_actions(scene.defaults.actors[1].actions)
	scene.single_step()
	while not scene.battle.finished:
		scene.advance_frame()
	check(scene.summary_overlay.visible and scene.summary_button.visible, "Battle end automatically opens the summary and enables reopening")
	check(scene.summary_title.text == "青衫修士胜", "Summary displays actual battle result")
	var totals: Array = scene.battle.get_statistics()
	check(totals[0].damage_dealt_milli == 40000 and totals[0].damage_taken_milli == 60000, "Default blue damage dealt and taken are 40 and 60")
	check(totals[0].taken_by_kind == {"shield": 50000, "artifact": 10000, "cultivator": 0}, "Blue taken damage splits into 50 shield and 10 sword")
	check(totals[1].damage_dealt_milli == 60000 and totals[1].damage_taken_milli == 40000, "Default red damage dealt and taken are 60 and 40")
	check(scene.summary_labels[0][0].text == "40" and scene.summary_labels[1][0].text == "60", "Summary shows exact blue totals")
	check(scene.summary_labels[2][0].text == "50" and scene.summary_labels[3][0].text == "10" and scene.summary_labels[4][0].text == "0", "Summary shows defender breakdown")
	check(totals[1].taken_by_kind.shield == 20000 and scene.summary_labels[2][1].text == "20", "Passive shield damage is included in the same statistics")
	check(totals[0].damage_dealt_milli == totals[1].damage_taken_milli and totals[1].damage_dealt_milli == totals[0].damage_taken_milli, "Dealt and taken totals conserve effective damage")
	var frozen: Dictionary = scene.battle.snapshot()
	scene.hide_summary()
	check(not scene.summary_overlay.visible, "Summary can be closed")
	scene.summary_button.pressed.emit()
	scene.single_step()
	check(scene.summary_overlay.visible and scene.battle.snapshot() == frozen, "Reopening or stepping a finished battle never double-counts statistics")
	check(bar.editable, "Finished battle permits editing next game's order")
	bar.move_action("shield", 2)
	scene.play_button.pressed.emit()
	check(scene.playing and not scene.summary_overlay.visible and scene.battle.frame == -1, "Replay closes summary and starts a clean battle")
	check(scene.battle.actors[0].sequence.keys() == ["qingyun_sword", "fireball", "shield"], "Replay uses post-battle reordered action identities")
	check(scene.battle.get_statistics()[0].damage_dealt_milli == 0 and scene.battle.get_statistics()[1].damage_taken_milli == 0, "Replay resets statistics")
	scene.play_button.pressed.emit()
	# A nominal 20-damage hit against five HP counts only the HP actually removed.
	var overkill_config: Dictionary = scene.defaults.duplicate(true)
	overkill_config.actors[0].actions = {"fireball_full": {}}
	overkill_config.actors[0].mana = 30
	overkill_config.actors[1].hp = 5
	overkill_config.actors[1].mana = 0
	overkill_config.actors[1].passives = {}
	var overkill = Battle.new()
	overkill.reset(overkill_config)
	while not overkill.finished:
		overkill.step()
	check(overkill.get_statistics()[0].damage_dealt_milli == 5000 and overkill.get_statistics()[1].damage_taken_milli == 5000, "Overkill counts effective HP damage rather than nominal hit power")
	var copied: Array = overkill.get_statistics()
	copied[0].damage_dealt_milli = 123456
	check(overkill.get_statistics()[0].damage_dealt_milli == 5000, "Summary receives a detached statistics snapshot")
	var expiry_config: Dictionary = scene.defaults.duplicate(true)
	expiry_config.actors[0].actions = {"qingyun_sword": {}}
	expiry_config.actors[0].mana = 10
	expiry_config.actors[1].hp = 1000
	expiry_config.actors[1].mana = 0
	expiry_config.actors[1].passives = {}
	var expiry = Battle.new()
	expiry.reset(expiry_config)
	while not expiry.finished:
		expiry.step()
	check(expiry.get_statistics()[0].taken_by_kind.artifact == 0 and expiry.get_statistics()[0].damage_taken_milli == 0, "Expiration is not counted as taking damage")
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	var file := FileAccess.open("res://test-drag-summary-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("DRAG / SUMMARY TESTS: ", JSON.stringify(report))
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
