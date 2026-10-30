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


func settings(left: Array, right: Array, left_mana: int, right_mana: int) -> Dictionary:
	var config: Dictionary = base.duplicate(true)
	# These fixtures isolate lifecycles; default pacing has dedicated timing tests.
	config.cast_interval_frames = 0
	config.shield_cooldown_frames = 0
	config.sword_cooldown_frames = 0
	for actor in config.actors:
		actor.hp = 1000
		actor.mind_capacity = 2
		actor.quality_permille = 1000
		actor.passives = {}
	config.actors[0].actions = Fixtures.definitions(left)
	config.actors[1].actions = Fixtures.definitions(right)
	config.actors[0].mana = left_mana
	config.actors[1].mana = right_mana
	return config


func create(config: Dictionary) -> RefCounted:
	var battle = Battle.new()
	battle.reset(config)
	return battle


func until(battle: RefCounted, target: int) -> void:
	while not battle.finished and battle.frame < target:
		battle.step()


func complete(battle: RefCounted, batch: int = 1) -> void:
	var guard: int = 0
	while not battle.finished and guard < 10000:
		for i in range(batch):
			battle.step()
		guard += batch
	check(battle.finished, "Framework scenario terminates")


func release_frames(battle: RefCounted, ability: String) -> Array:
	var frames: Array = []
	for event in battle.events:
		if event.kind == "release" and event.ability == ability:
			frames.append(event.frame)
	return frames


func inject_damage(battle: RefCounted, amount: int) -> void:
	battle.queue_effects([{"type": "damage"}], battle.actors[1].entity_id, battle.actors[1].presence.id,
		{"side": 1, "owner_id": battle.actors[1].entity_id, "source_id": battle.actors[1].entity_id, "damage_milli": amount * 1000})
	battle.flush_effects()


func run() -> void:
	# A shield is an independent HP-bearing presence, with cost matching its HP.
	var shield = create(settings(["shield"], ["normal"], 50, 30))
	until(shield, 30)
	var guard: Dictionary = shield.active_entities(0, "shield")[0]
	check(shield.actors[0].mana == 0 and guard.hp_milli == 50000, "50 MP creates exactly 50 shield HP")
	check(shield.mind_used(shield.actors[0].entity_id) == 1, "Shield occupies one mind slot")
	check(not shield.interrupt_cast(guard.entity_id), "A shield presence cannot be interrupted")
	check(not shield.interrupt_cast(shield.actors[0].entity_id), "Released casting cannot be interrupted retroactively")
	until(shield, 54)
	check(guard.hp_milli == 40000 and shield.actors[0].hp_milli == 1000000, "Shield takes fireball damage before body")
	complete(shield)
	check(guard.hp_milli == 20000 and guard.active, "Shield persists independently after creator runs out of mana")
	var custom_config: Dictionary = settings(["shield"], ["normal"], 25, 0)
	custom_config.shield_cost = 25
	var custom_shield = create(custom_config)
	until(custom_shield, 30)
	check(custom_shield.active_entities(0, "shield")[0].hp_milli == 25000, "Shield effect stays linked to configured MP cost")
	var poor = create(settings(["shield"], ["normal"], 49, 0))
	complete(poor)
	check(poor.actors[0].mana == 49 and poor.active_entities(0, "shield").is_empty(), "Insufficient MP creates no shield and spends nothing")
	# Sword attacks are nested casts, not direct periodic damage callbacks.
	var sword_config: Dictionary = settings(["qingyun_sword"], ["normal"], 10, 0)
	var sword = create(sword_config)
	until(sword, 30)
	var weapon: Dictionary = sword.active_entities(0, "artifact")[0]
	check(weapon.hp_milli == 20000, "Sword has its own 20 HP")
	check(sword.actors[0].mana == 0 and not weapon.cast.is_empty(), "10 MP summon immediately starts weapon's own casting")
	check(sword.mind_used(sword.actors[0].entity_id) == 1, "Sword occupies one slot throughout its own flight")
	var attack_cast: Dictionary = weapon.cast
	var trigger_effect: Dictionary = sword.actions[int(attack_cast.parent_id)]
	check(attack_cast.kind == "cast" and attack_cast.source_id == weapon.entity_id, "Sword is the caster of its own attack")
	check(trigger_effect.kind == "effect", "Effect links entity presence to nested casting")
	check(trigger_effect.parent_id == weapon.presence.id, "Nested attack retains presence parent lineage")
	until(sword, 81)
	check(sword.actors[1].hp_milli == 990000, "Sword attack deals fireball-equivalent 10 damage")
	until(sword, 449)
	check(weapon.active and release_frames(sword, "sword_attack") == [36, 222, 408], "Weapon waits 180 frames from each release before its next windup")
	check(sword.actors[0].mana == 0, "Recurring sword attacks do not charge creator again")
	sword.step()
	check(not weapon.active and weapon.presence.end_frame == 450, "Sword expires exactly 420 frames after summon")
	check(sword.mind_used(sword.actors[0].entity_id) == 0, "Sword expiration returns its mind slot")
	check(sword.actors[1].hp_milli == 980000, "Sword expiry cancels third outbound attack before contact")
	check(sword.result == "stalemate", "Expired weapon leaves no phantom future attacks")
	# Cost / quality power is inherited by the child cast; durability stays 20.
	var stronger_config: Dictionary = settings(["qingyun_sword"], ["normal"], 10, 0)
	stronger_config.actors[0].quality_permille = 1500
	var stronger = create(stronger_config)
	until(stronger, 81)
	check(stronger.actors[1].hp_milli == 985000, "Nested attack inherits caster quality for 15 damage")
	check(stronger.actors[0].mana == 0 and stronger.active_entities(0, "artifact")[0].hp_milli == 20000, "Quality changes damage without changing cost or sword HP")
	# Damage spills through shield -> artifact -> body in one settlement.
	var defense = create(settings(["shield", "qingyun_sword"], ["normal"], 60, 0))
	until(defense, 78)
	var defense_shield: Dictionary = defense.active_entities(0, "shield")[0]
	var defense_sword: Dictionary = defense.active_entities(0, "artifact")[0]
	check(defense.mind_used(defense.actors[0].entity_id) == 2, "Shield and sword can coexist in two slots")
	inject_damage(defense, 80)
	check(defense_shield.hp_milli == 0 and defense_sword.hp_milli == 0 and defense.actors[0].hp_milli == 990000, "80 damage consumes 50 shield + 20 sword + 10 body HP")
	var damaged: Array = []
	for event in defense.events:
		if event.kind == "damage" and event.side == 0:
			damaged.append(event.entity_id)
	check(damaged == [defense_shield.entity_id, defense_sword.entity_id, defense.actors[0].entity_id], "Actual damage event order is shield, artifact, body")
	check(defense.mind_used(defense.actors[0].entity_id) == 0, "Destroyed defenses return both mind slots immediately")
	until(defense, 102)
	check(defense.actors[1].hp_milli == 1000000, "Sword destroyed during windup never deals future damage")
	check(release_frames(defense, "sword_attack").is_empty(), "Destroyed sword cannot release its interrupted-by-destruction attack")
	# Capacity waits spend nothing and do not skip the action sequence.
	var crowded = create(settings(["shield"], ["normal"], 200, 100))
	until(crowded, 100)
	check(crowded.active_entities(0, "shield").size() == 2 and crowded.mind_used(crowded.actors[0].entity_id) == 2, "Two long-lived entities fill capacity")
	check(crowded.actors[0].waiting == "mind" and crowded.actors[0].mana == 100, "Third summon waits without spending mana")
	check(not crowded.actors[0].blocked, "Mind shortage is retryable rather than permanent MP exhaustion")
	inject_damage(crowded, 50)
	crowded.step()
	check(not crowded.actors[0].cast.is_empty(), "Freed slot lets waiting caster resume")
	until(crowded, 131)
	check(crowded.active_entities(0, "shield").size() == 2 and crowded.actors[0].mana == 50, "Replacement shield pays once and respects capacity")
	# A released fireball consumes no mind even with a full defensive loadout.
	var free_projectile = create(settings(["shield", "qingyun_sword", "normal"], ["normal"], 100, 0))
	until(free_projectile, 126)
	check(free_projectile.mind_used(free_projectile.actors[0].entity_id) == 2 and not free_projectile.projectiles.is_empty(), "Full long-lived capacity still allows fireball casting")
	# Only a pending cast is interrupted; existing presence and projectiles survive.
	var interrupted = create(settings(["normal"], ["normal"], 100, 0))
	until(interrupted, 10)
	check(interrupted.interrupt_cast(interrupted.actors[0].entity_id, "silence"), "Control interrupts a pending cast")
	until(interrupted, 30)
	check(interrupted.actors[0].mana == 100 and interrupted.projectiles.is_empty(), "Interrupted cast neither releases nor spends MP")
	until(interrupted, 41)
	check(interrupted.projectiles.size() == 1 and interrupted.actors[0].mana == 90, "Caster can begin a later cast after interruption")
	check(not interrupted.interrupt_cast(interrupted.projectiles[0].entity_id), "Existing projectile presence cannot be interrupted")
	# Nonzero nested windup exercises interrupting a weapon's own casting.
	var nested_config: Dictionary = sword_config.duplicate(true)
	nested_config.library = JSON.parse_string(FileAccess.get_file_as_string("res://data/actions.json"))
	nested_config.library.abilities.sword_attack.windup_frames = 12
	nested_config.sword_windup_frames = 12
	var nested = create(nested_config)
	until(nested, 35)
	var nested_weapon: Dictionary = nested.active_entities(0, "artifact")[0]
	check(nested.interrupt_cast(nested_weapon.entity_id, "bind"), "Persistent weapon's pending cast can be interrupted")
	check(nested_weapon.active and nested.mind_used(nested.actors[0].entity_id) == 1, "Interrupting cast preserves weapon and its slot")
	until(nested, 246)
	check(release_frames(nested, "sword_attack") == [48, 240], "Weapon retries after interruption, then uses release-based cooldown")
	check(nested.actors[1].hp_milli == 990000, "Resumed nested attack settles normally")
	# Incoming lethal damage on the release frame cancels shield creation first.
	var boundary_config: Dictionary = settings(["shield"], ["normal"], 50, 10)
	boundary_config.actors[0].hp = 10
	boundary_config.spell.windup_frames = 6
	var boundary = create(boundary_config)
	until(boundary, 30)
	check(boundary.actors[0].hp_milli == 0 and boundary.active_entities(0, "shield").is_empty(), "Same-frame lethal hit precedes shield release")
	check(boundary.actors[0].mana == 50, "Cancelled lethal-frame shield does not spend MP")
	var replay = create(sword_config)
	complete(replay, 4)
	check(sword.snapshot() == replay.snapshot() and sword.events == replay.events, "Nested lifecycles are identical under 1x and 4x playback")
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	var file := FileAccess.open("res://test-framework-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("FRAMEWORK TESTS: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
