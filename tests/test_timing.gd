extends SceneTree

const Battle = preload("res://scripts/core/battle.gd")
const Fixtures = preload("res://tests/action_fixtures.gd")
var base: Dictionary
var checks: int = 0
var failures: Array = []


func _initialize() -> void:
	base = JSON.parse_string(FileAccess.get_file_as_string("res://data/duel.json"))
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)


func settings(sequence: Array, mana: int = 1000) -> Dictionary:
	var config: Dictionary = base.duplicate(true)
	for actor in config.actors:
		actor.hp = 10000
		# Separate timing from already tested capacity restrictions.
		actor.mind_capacity = 10
		actor.quality_permille = 1000
		actor.passives = {}
	config.actors[0].actions = Fixtures.definitions(sequence)
	config.actors[0].mana = mana
	config.actors[1].actions = {"fireball": {"mode": "normal"}}
	config.actors[1].mana = 0
	return config


func create(config: Dictionary) -> RefCounted:
	var battle = Battle.new()
	battle.reset(config)
	return battle


func until(battle: RefCounted, target: int) -> void:
	while not battle.finished and battle.frame < target:
		battle.step()


func records(battle: RefCounted, kind: String, ability: String = "", entity_id: int = 1) -> Array:
	var result: Array = []
	for event in battle.events:
		if event.kind == kind and int(event.get("entity_id", -1)) == entity_id and (ability.is_empty() or event.get("ability", "") == ability):
			result.append(event)
	return result


func frames(items: Array) -> Array:
	var result: Array = []
	for item in items:
		result.append(item.frame)
	return result


func run() -> void:
	var fire = create(settings(["normal"]))
	until(fire, 29)
	check(fire.config.cast_interval_frames == 90, "Default release-to-next-cast interval is 90 frames")
	check(fire.actors[0].next_cast_frame == 0, "Windup does not start interval timer")
	fire.step()
	check(fire.actors[0].next_cast_frame == 120, "Release at F30 permits next windup at F120")
	check(fire.config.library.abilities.fireball.cooldown_frames == 0, "Fireball has no ability cooldown")
	until(fire, 60)
	check(not fire.start_cast(1, {"ability": "fireball"}), "Direct triggers also obey entity cast interval")
	check(fire.actors[0].mana == 990 and fire.actors[0].next_cast_frame == 120, "Failed interval check spends nothing and does not extend timer")
	until(fire, 119)
	check(frames(records(fire, "cast")) == [0], "No second cast before release plus 90 frames")
	fire.step()
	check(fire.actors[0].cast.start_frame == 120, "Second cast starts on exact interval boundary")
	until(fire, 270)
	check(frames(records(fire, "cast")) == [0, 120, 240], "Default fireball windups have correct release-based cadence")
	check(frames(records(fire, "release")) == [30, 150, 270], "Windup adds to release-to-next-windup interval")
	var duel_config: Dictionary = settings(["normal"], 100)
	duel_config.actors[0].hp = 20
	duel_config.actors[1].hp = 20
	duel_config.actors[1].mana = 100
	var duel = create(duel_config)
	until(duel, 174)
	check(duel.result == "double_ko" and duel.frame == 174, "Two-hit 20HP duel now ends at F174")
	check(duel.actors[0].mana == 80 and duel.actors[1].mana == 80, "Timing changes preserve damage and mana accounting")
	var shield = create(settings(["shield"]))
	until(shield, 29)
	check(shield.actors[0].cooldowns.is_empty(), "Shield windup does not start cooldown")
	shield.step()
	check(shield.actors[0].cooldowns.shield == 1230, "Shield cooldown is 1200 frames from successful release")
	until(shield, 120)
	check(shield.actors[0].waiting == "cooldown" and shield.actors[0].deferred_actions.size() == 1, "Single cooling skill waits in deferred queue")
	check(shield.actors[0].mana == 950 and not shield.finished, "Waiting cooldown neither consumes mana nor falsely ends battle")
	until(shield, 1229)
	check(frames(records(shield, "cast")) == [0], "Shield cannot recast one frame before cooldown boundary")
	shield.step()
	check(shield.actors[0].cast.start_frame == 1230 and shield.actors[0].cast.from_deferred, "Deferred shield starts exactly when cooldown expires")
	until(shield, 1260)
	check(shield.actors[0].cooldowns.shield == 2460 and shield.actors[0].mana == 900, "Second release starts its own cooldown and pays once")
	check(shield.actors[0].deferred_actions.is_empty(), "Released deferred entry is removed once")
	var mixed_config: Dictionary = settings(["shield", "qingyun_sword", "normal"])
	var mixed = create(mixed_config)
	until(mixed, 360)
	check(frames(records(mixed, "cast")) == [0, 120, 240, 360], "Cooling shield and sword are skipped to cast the next fireball")
	check(mixed.actors[0].cast.ability == "fireball", "Skipped cooldowns do not block available next skill")
	check(mixed.actors[0].deferred_actions.size() == 2, "Cooling sequence slots are deferred without duplicates")
	check(mixed.actors[0].mana == 930, "Skipping cooling abilities does not consume MP")
	until(mixed, 1229)
	check(mixed.actors[0].cast.ability == "fireball" and mixed.actors[0].cast.start_frame == 1200, "Current cast continues while a higher-priority cooldown approaches completion")
	mixed.step()
	check(mixed.actors[0].cast.is_empty() and mixed.actors[0].next_cast_frame == 1320, "Cooldown readiness cannot bypass ongoing release interval")
	check(mixed.actors[0].deferred_actions.size() == 2, "Ready deferred slots remain pending until actually released")
	until(mixed, 1320)
	check(mixed.actors[0].cast.ability == "shield" and mixed.actors[0].cast.from_deferred, "First ready deferred shield takes front priority")
	until(mixed, 1440)
	check(mixed.actors[0].cast.ability == "qingyun_sword" and mixed.actors[0].cast.from_deferred, "Next ready deferred sword precedes normal rotation")
	until(mixed, 1560)
	check(mixed.actors[0].cast.ability == "fireball" and not mixed.actors[0].cast.from_deferred, "Normal rotation resumes after priority casts")
	# Repeated slots share the ability cooldown, including after priority insertion.
	var duplicate = create(settings(["shield", "normal"]))
	until(duplicate, 1440)
	check(frames(records(duplicate, "release", "shield")) == [30, 1350], "Unique shield action retains its cooldown across rotations")
	check(duplicate.actors[0].cast.ability == "fireball", "Normal rotation resumes after the priority shield cast")
	var sword = create(settings(["qingyun_sword"], 10))
	until(sword, 450)
	var weapon_id: int = 0
	for entity in sword.entities.values():
		if entity.kind == "artifact":
			weapon_id = int(entity.entity_id)
	check(frames(records(sword, "release", "sword_attack", weapon_id)) == [36, 222, 408], "Sword's independent cooldown starts at each release")
	check(sword.actors[0].cooldowns.qingyun_sword == 1230, "Summon cooldown belongs to the summoner")
	check(not sword.entities[weapon_id].cooldowns.has("qingyun_sword"), "Summon cooldown does not leak into weapon attack cooldowns")
	check(sword.entities[weapon_id].presence.end_frame == 450 and sword.result == "stalemate", "Expiry and permanent mana exhaustion still terminate promptly")
	var interrupted = create(settings(["shield"], 200))
	until(interrupted, 10)
	check(interrupted.interrupt_cast(1, "silence"), "Pending cast can be interrupted with new timers")
	check(interrupted.actors[0].cooldowns.is_empty() and interrupted.actors[0].next_cast_frame == 0, "Interrupted pre-release cast starts neither cooldown nor interval")
	until(interrupted, 41)
	check(frames(records(interrupted, "release")) == [41], "Retry releases after interruption without a phantom interval")
	check(interrupted.actors[0].cooldowns.shield == 1241 and interrupted.actors[0].next_cast_frame == 131, "Successful retry starts both timers at its actual release")
	var recovery_config: Dictionary = settings(["normal"])
	recovery_config.spell.recovery_frames = 180
	var recovery = create(recovery_config)
	until(recovery, 209)
	check(frames(records(recovery, "cast")) == [0], "Long recovery remains an independent action gate")
	recovery.step()
	check(recovery.actors[0].cast.start_frame == 210, "Recovery and interval overlap instead of adding together")
	var no_mind_config: Dictionary = settings(["shield"], 100)
	no_mind_config.actors[0].mind_capacity = 0
	var no_mind = create(no_mind_config)
	no_mind.step()
	check(no_mind.actors[0].mana == 100 and no_mind.actors[0].cooldowns.is_empty() and no_mind.actors[0].next_cast_frame == 0, "Capacity failure starts no timers and consumes no MP")
	var replay_config: Dictionary = mixed_config.duplicate(true)
	replay_config.max_frames = 2000
	var one = create(replay_config)
	var four = create(replay_config)
	while not one.finished:
		one.step()
	while not four.finished:
		for i in range(4):
			four.step()
	check(one.snapshot() == four.snapshot() and one.events == four.events, "Cooldown queues are deterministic under 1x and 4x playback")
	one.reset(replay_config)
	check(one.actors[0].cooldowns.is_empty() and one.actors[0].deferred_actions.is_empty() and one.actors[0].next_cast_frame == 0, "Reset clears cooldowns, deferred order and interval")
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	var file := FileAccess.open("res://test-timing-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("TIMING TESTS: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
