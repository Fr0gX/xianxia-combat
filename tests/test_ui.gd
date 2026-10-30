extends SceneTree
## Exercise gameplay and collapsible developer controls in the actual scene.

var checks: int = 0
var failures: Array = []


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)


func collect_game_text(node: Node) -> String:
	var content: String = ""
	if node is Label or node is Button:
		content += node.text + "\n"
	for child in node.get_children():
		content += collect_game_text(child)
	return content


func run() -> void:
	root.size = Vector2i(1440, 900)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	check(scene.battle.frame == -1 and not scene.playing, "Scene opens paused and unadvanced")
	check(scene.actor_widgets[0].hp_label.text == "20 / 20", "Default game HP is 20")
	check(scene.actor_widgets[0].mana_label.text == "100 / 100", "Initial mana display matches configuration")
	check(scene.actor_widgets[1].hp_label.text == "20 / 20" and scene.actor_widgets[1].mana_label.text == "200 / 200", "Right body HP is 20 while mid-stage MP remains 200")
	check(scene.actor_widgets[1].quality_input.value == 1.5 and scene.actor_widgets[1].mind_label.text == "4 / 4", "Right mid-stage quality and mind are preserved through UI configuration")
	check(not scene.tech_panel.visible, "Technical drawer is collapsed by default")
	check(not scene.frame_label.is_visible_in_tree() and not scene.log_view.is_visible_in_tree(), "Frame counters and event log are hidden with drawer")
	check(not scene.actor_widgets[0].hp_input.is_visible_in_tree(), "Editable initial stats are absent from game display")
	check(scene.timing_inputs.cast_interval_frames.value == 1.5 and scene.timing_inputs.shield_cooldown_frames.value == 20 and scene.timing_inputs.sword_cooldown_frames.value == 20, "Technical controls expose default interval and cooldowns in seconds")
	var game_text: String = ""
	for area in get_nodes_in_group("game_display"):
		game_text += collect_game_text(area)
	for forbidden in ["帧", "FPS", "Hz", "HP", "MP", "日志"]:
		check(not game_text.contains(forbidden), "Gameplay vocabulary excludes developer term: " + forbidden)
	scene.tech_toggle.pressed.emit()
	await process_frame
	await process_frame
	check(scene.tech_panel.visible and scene.frame_label.is_visible_in_tree(), "Technical toggle exposes debugging controls")
	check(scene.log_view.get_global_rect().end.y <= root.size.y - 10, "Expanded technical log fits inside viewport")
	check(scene.game_display.get_global_rect().end.y <= scene.game_toolbar.get_global_rect().position.y, "Gameplay and control regions do not overlap")
	check(scene.arena.size.y >= 300, "Expanded drawer preserves usable game area")
	scene.play_button.pressed.emit()
	check(scene.playing, "Start button starts playback")
	check(not scene.actor_widgets[0].hp_input.editable, "Starting battle locks configuration")
	await physics_frame
	await physics_frame
	check(scene.battle.frame >= 0, "Fixed processing advances battle")
	scene.play_button.pressed.emit()
	check(not scene.playing, "Pause button pauses playback")
	var paused_frame: int = scene.battle.frame
	for i in range(4):
		await physics_frame
	check(scene.battle.frame == paused_frame, "Paused battle does not advance")
	var before_toggle: Dictionary = scene.battle.snapshot()
	scene.tech_toggle.pressed.emit()
	check(not scene.tech_panel.visible, "Technical drawer can collapse during paused battle")
	check(scene.battle.snapshot() == before_toggle, "Collapsing drawer does not reset or advance battle")
	scene.tech_toggle.pressed.emit()
	check(scene.battle.snapshot() == before_toggle, "Expanding drawer does not change battle state")
	while scene.battle.frame < 178:
		scene.single_step()
	check(scene.actor_widgets[0].mind_label.text == "0 / 2", "Shield and sword leave zero of two mind slots available")
	check(scene.actor_widgets[1].mind_label.text == "3 / 4", "Battle-start passive shield occupies one of four mind slots")
	check(scene.actor_widgets[0].entities_label.text.contains("护盾 20") and scene.actor_widgets[0].entities_label.text.contains("青云剑 20"), "Game HUD shows shield damage from stronger opponent and sword HP")
	check(scene.actor_widgets[0].mana_label.text == "40 / 100", "Shield and sword spend exactly 50 + 10 MP")
	check(scene.actor_widgets[0].sequence.get_order() == ["shield", "qingyun_sword", "fireball"], "Game icons represent the three unique actions")
	check(scene.log_view.get_parsed_text().contains("青/青云剑 施法·剑击"), "Technical log identifies the sword's own casting")
	var weapon: Dictionary = scene.battle.active_entities(0, "artifact")[0]
	var positions := [Vector2(scene.arena.size.x * 0.22, scene.arena.size.y * 0.66), Vector2(scene.arena.size.x * 0.78, scene.arena.size.y * 0.66)]
	var resting: Vector2 = positions[0] + Vector2(42, -119)
	check(scene.arena.weapon_position(weapon, positions).distance_to(resting) > 50 and not weapon.motion.is_empty(), "Rendered sword itself travels away from its resting position")
	check(scene.battle.config.library.abilities.sword_attack.windup_frames == 6 and scene.battle.config.library.abilities.sword_attack.cooldown_frames == 180, "Technical controls retain short entity windup and internal cooldown")
	paused_frame = scene.battle.frame
	scene.speed_control.select(3)
	scene.speed_control.item_selected.emit(3)
	check(scene.speed_halves == 8 and Engine.physics_ticks_per_second == 60 and Engine.max_fps == 60, "4x replay leaves engine logic and rendering limits at 60")
	scene.step_button.pressed.emit()
	check(scene.battle.frame == paused_frame + 1 and not scene.playing, "Single-step advances only one frame at 4x")
	scene.defaults.actors[1].passives = {}
	scene.reset_battle()
	check(scene.battle.frame == -1 and scene.actor_widgets[0].hp_input.editable, "Reset restores editable initial state")
	scene.actor_widgets[0].hp_input.value = 100
	scene.actor_widgets[1].hp_input.value = 100
	scene.actor_widgets[1].sequence.set_actions({"fireball": {"mode": "normal"}})
	scene.actor_widgets[0].mana_input.value = 60
	scene.actor_widgets[0].quality_input.value = 1.5
	scene.actor_widgets[0].sequence.set_actions({"fireball_full": {}})
	scene.single_step()
	check(scene.battle.actors[0].max_mana == 60, "Edited initial mana reaches simulation")
	check(scene.battle.actors[0].quality_permille == 1500, "Edited quality reaches simulation")
	while not scene.battle.finished and scene.battle.frame < 54:
		scene.single_step()
	check(scene.battle.actors[0].mana == 30, "Configured full fireball consumes 30 mana")
	check(scene.battle.actors[1].hp_milli == 70000, "Configured full fireball at x1.5 deals 30 damage")
	check(scene.actor_widgets[1].hp_label.text == "70 / 100", "Game HP matches settled damage")
	check(not scene.actor_widgets[0].state.text.contains("帧"), "Active casting status uses gameplay vocabulary")
	check(scene.log_view.get_parsed_text().contains("10 × 1.5 × 2 = 30"), "Technical log shows actual damage calculation")
	check(scene.actor_widgets[0].sequence.slots[0].tooltip_text == "全力火球", "Game sequence icons retain their skill names")
	while not scene.battle.finished:
		scene.advance_frame()
	check(scene.play_button.text == "再战", "Finished battle offers replay")
	scene.play_button.pressed.emit()
	check(scene.playing and scene.battle.frame == -1, "Replay starts fresh battle")
	check(scene.battle.actors[0].mana == 60, "Replay preserves edited configuration")
	scene.play_button.pressed.emit()
	scene.reset_battle()
	# Edited timing applies through the actual technical controls.
	scene.spell_inputs.mana_cost.value = 5
	scene.spell_inputs.windup_frames.value = 12
	scene.spell_inputs.flight_frames.value = 6
	scene.spell_inputs.recovery_frames.value = 8
	scene.timing_inputs.cast_interval_frames.value = 0.5
	scene.timing_inputs.shield_cooldown_frames.value = 10
	scene.timing_inputs.sword_cooldown_frames.value = 11
	scene.single_step()
	check(scene.battle.config.cast_interval_frames == 30 and scene.battle.config.shield_cooldown_frames == 600 and scene.battle.config.sword_cooldown_frames == 660, "Edited seconds convert to integer logic frames")
	while scene.battle.frame < 18:
		scene.single_step()
	check(scene.battle.actors[0].mana == 45, "Edited base cost changes full cast MP cost to 15")
	check(scene.battle.actors[1].hp_milli == 85000, "Edited cost and timing yield full hit for 15 HP at frame 18")
	check(scene.log_view.get_parsed_text().contains("5 × 1.5 × 2 = 15"), "Technical formula reflects edited base cost")
	check(scene.battle.actors[0].next_cast_frame == 42, "Edited interval starts at actual F12 release")
	check(not scene.timing_inputs.cast_interval_frames.editable, "Runtime locks timing edits along with other configuration")
	scene.reset_battle()
	scene.prepare_first_frame()
	scene.playing = true
	scene.speed_halves = 1
	scene._physics_process(1.0 / 60.0)
	check(scene.battle.frame == -1, "Half speed first update accumulates without advancing")
	scene._physics_process(1.0 / 60.0)
	check(scene.battle.frame == 0, "Half speed second update advances exactly once")
	scene.playing = false
	scene.reset_battle()
	scene.prepare_first_frame()
	scene.playing = true
	scene.speed_halves = 8
	scene._physics_process(1.0 / 60.0)
	check(scene.battle.frame == 3, "4x processes exactly four logical frames")
	scene.playing = false
	scene.reset_battle()
	scene.actor_widgets[0].mana_input.value = 200
	scene.actor_widgets[1].mana_input.value = 0
	scene.actor_widgets[0].sequence.set_actions({"shield": {}})
	while scene.battle.frame < 61:
		scene.single_step()
	check(scene.actor_widgets[0].state.text.begins_with("冷却"), "Game HUD shows concise cooldown state when all slots are cooling")
	check(scene.log_view.get_parsed_text().contains("跳过护盾"), "Technical log records skipped cooldown actions")
	# The smallest supported window must retain both distinct regions.
	root.size = Vector2i(1200, 900)
	await process_frame
	await process_frame
	var visible_size: Vector2 = scene.get_viewport_rect().size
	check(scene.log_view.get_global_rect().end.y <= visible_size.y - 10, "Expanded drawer fits minimum window height")
	check(scene.tech_panel.get_global_rect().end.x <= visible_size.x, "Expanded drawer fits minimum window width")
	check(scene.tech_scroll.get_v_scroll_bar().max_value > scene.tech_scroll.size.y, "Long parameter form is vertically scrollable")
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(),
		"viewport_size": str(root.size), "log_rect": str(scene.log_view.get_global_rect())}
	var file := FileAccess.open("res://test-ui-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("UI TESTS: ", JSON.stringify(report))
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
