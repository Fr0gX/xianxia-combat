extends SceneTree

const Battle = preload("res://scripts/core/battle.gd")
var checks: int = 0
var failures: Array = []
var base: Dictionary


func _initialize() -> void:
	base = JSON.parse_string(FileAccess.get_file_as_string("res://data/duel.json"))
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)


func settings(left_mode: String = "normal", right_mode: String = "normal") -> Dictionary:
	var config: Dictionary = base.duplicate(true)
	# Isolate numerical regressions from the separately tested default pacing.
	config.cast_interval_frames = 0
	config.actors[0].actions = {"fireball_full" if left_mode == "full" else "fireball": {}}
	config.actors[1].actions = {"fireball_full" if right_mode == "full" else "fireball": {}}
	config.actors[0].passives = {}
	config.actors[1].passives = {}
	config.actors[0].mana = 100
	config.actors[1].mana = 100
	config.actors[0].hp = 100
	config.actors[1].hp = 100
	config.actors[0].quality_permille = 1000
	config.actors[1].quality_permille = 1000
	return config


func create(config: Dictionary) -> RefCounted:
	var battle = Battle.new()
	battle.reset(config)
	return battle


func until(battle: RefCounted, target_frame: int) -> void:
	while not battle.finished and battle.frame < target_frame:
		battle.step()


func complete(battle: RefCounted, batch: int = 1) -> void:
	var guard: int = 0
	while not battle.finished and guard < 10000:
		for i in range(batch):
			battle.step()
		guard += batch
	check(battle.finished, "Battle terminates within configured frame limit")


func run() -> void:
	check(Engine.physics_ticks_per_second == 60, "Engine logic frequency remains fixed at 60Hz")
	check(Engine.max_fps == 60, "Engine render frame rate is capped at 60FPS")
	var original_duel: Dictionary = settings()
	original_duel.actors[0].hp = 20
	original_duel.actors[1].hp = 20
	var two_hits = create(original_duel)
	until(two_hits, 54)
	check(not two_hits.finished and two_hits.actors[0].hp_milli == 10000, "First default normal hit leaves 10 of 20 HP")
	until(two_hits, 101)
	check(not two_hits.finished, "Default duel cannot end before second arrival")
	two_hits.step()
	check(two_hits.frame == 102 and two_hits.result == "double_ko", "Second normal arrival ends default symmetric duel")
	check(two_hits.actors[0].mana == 80 and two_hits.actors[1].mana == 80, "Two released normal shots cost exactly 20 mana per actor")
	var hit_counts := [0, 0]
	for event in two_hits.events:
		if event.kind == "hit":
			hit_counts[int(event.target)] += 1
	check(hit_counts == [2, 2], "Default numerical HP reaches zero after exactly two hits per actor")
	var normal = create(settings())
	until(normal, 29)
	check(normal.actors[0].mana == 100, "Windup does not consume mana")
	check(normal.actors[1].hp_milli == 100000, "Windup does not deal damage")
	normal.step()
	check(normal.frame == 30 and normal.actors[0].mana == 90, "Normal release at frame 30 costs exactly 10")
	check(normal.projectiles.size() == 2, "Both sides release independently in same frame")
	until(normal, 53)
	check(normal.actors[1].hp_milli == 100000, "No damage before arrival")
	normal.step()
	check(normal.actors[1].hp_milli == 90000, "Normal arrival at frame 54 deals exactly 10")
	check(normal.actors[0].mana == 90, "Arrival does not consume mana again")
	check(normal.actors[0].cast.start_frame == 48, "Next cast starts at release + 18 recovery frames")
	var full = create(settings("full", "normal"))
	until(full, 54)
	check(full.actors[0].mana == 70, "Full release costs 3x base mana")
	check(full.actors[1].hp_milli == 80000, "Full impact deals 2x base damage, not 3x")
	var quality_config: Dictionary = settings()
	quality_config.actors[0].quality_permille = 1250
	var quality = create(quality_config)
	until(quality, 54)
	check(quality.actors[1].hp_milli == 87500, "Quality x1.25 gives exact 12.5 damage")
	check(quality.actors[0].mana == 90, "Quality does not multiply mana consumption")
	var low_config: Dictionary = settings("full", "normal")
	low_config.actors[0].mana = 29
	low_config.actors[1].mana = 0
	var low = create(low_config)
	complete(low)
	check(low.result == "stalemate", "Both sides unable to cast ends in stalemate")
	check(low.actors[0].mana == 29 and low.serial == 0, "Insufficient mana spends nothing and creates no projectile")
	check(low.actors[0].sequence_index == 0, "Insufficient mana does not skip configured action")
	var exact_config: Dictionary = settings("full", "normal")
	exact_config.actors[0].mana = 30
	exact_config.actors[1].mana = 0
	var exact = create(exact_config)
	complete(exact)
	check(exact.actors[0].mana == 0, "Mana equal to cost permits release")
	check(exact.actors[1].hp_milli == 80000 and exact.frame == 54, "Pending projectile resolves before stalemate")
	var lethal_config: Dictionary = settings()
	lethal_config.actors[0].hp = 10
	lethal_config.actors[1].hp = 10
	var lethal = create(lethal_config)
	complete(lethal)
	check(lethal.result == "double_ko" and lethal.frame == 54, "Same-frame lethal damage produces double KO")
	check(lethal.actors[0].hp_milli == 0 and lethal.actors[1].hp_milli == 0, "Both HP values clamp at zero")
	var stopped: Dictionary = lethal.snapshot()
	lethal.step()
	check(lethal.snapshot() == stopped, "Finished battle never advances or deals more damage")
	var cancelled_config: Dictionary = settings("full", "normal")
	cancelled_config.actors[0].hp = 10
	var cancelled = create(cancelled_config)
	until(cancelled, 48)
	check(not cancelled.actors[0].cast.is_empty(), "Second cast is winding up before lethal arrival")
	until(cancelled, 54)
	check(cancelled.actors[0].cast.is_empty(), "Death cancels unreleased cast")
	check(cancelled.actors[0].mana == 70, "Cancelled cast does not consume mana")
	check(cancelled.result == "right_win", "Survivor wins after pending shots resolve")
	# Owner death must not delete an already launched projectile.
	var persistence = create(lethal_config)
	until(persistence, 30)
	persistence.projectiles[1].hit_frame = 55
	until(persistence, 54)
	check(not persistence.finished and persistence.actors[1].hp_milli == 0, "Wait for dead owner's projectile still in flight")
	persistence.step()
	check(persistence.result == "double_ko", "Dead owner's released fireball still hits")
	var timeout_config: Dictionary = settings()
	timeout_config.max_frames = 5
	var timeout = create(timeout_config)
	complete(timeout)
	check(timeout.result == "timeout" and timeout.frame == 5, "Frame limit prevents unbounded simulation")
	var one = create(base)
	var four = create(base)
	complete(one, 1)
	complete(four, 4)
	check(one.snapshot() == four.snapshot(), "1x and 4x frame batching produce identical final state")
	check(one.events == four.events, "Playback speed leaves full event log identical")
	var repeat = create(base)
	complete(repeat)
	check(one.events == repeat.events, "Same configuration replays deterministically")
	var mirror_config: Dictionary = base.duplicate(true)
	mirror_config.actors.reverse()
	var mirror = create(mirror_config)
	complete(mirror)
	check(one.actors[0].hp_milli == mirror.actors[1].hp_milli, "Swapping sides preserves corresponding HP")
	check(one.actors[1].mana == mirror.actors[0].mana, "Swapping sides preserves corresponding mana")
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(),
		"default_duel": {"frame": one.frame, "result": one.result, "left_hp": one.actors[0].hp_milli / 1000.0,
			"right_hp": one.actors[1].hp_milli / 1000.0, "left_mana": one.actors[0].mana, "right_mana": one.actors[1].mana}}
	var file := FileAccess.open("res://test-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report, "  "))
	quit(0 if failures.is_empty() else 1)
