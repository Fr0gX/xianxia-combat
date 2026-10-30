extends SceneTree

const Battle = preload("res://scripts/core/battle.gd")
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


func settings() -> Dictionary:
	var config: Dictionary = base.duplicate(true)
	for actor in config.actors:
		actor.hp = 1000
		actor.mind_capacity = 2
		actor.quality_permille = 1000
		actor.passives = {}
	config.actors[0].actions = {"qingyun_sword": {}}
	config.actors[0].mana = 10
	config.actors[1].actions = {"fireball": {}}
	config.actors[1].mana = 0
	return config


func create(config: Dictionary) -> RefCounted:
	var battle = Battle.new()
	battle.reset(config)
	return battle


func until(battle: RefCounted, target: int) -> void:
	while not battle.finished and battle.frame < target:
		battle.step()


func damage(battle: RefCounted, amount: int) -> void:
	battle.queue_effects([{"type": "damage"}], 2, battle.actors[1].presence.id,
		{"side": 1, "owner_id": 2, "source_id": 2, "damage_milli": amount * 1000})
	battle.flush_effects()


func releases(battle: RefCounted) -> Array:
	var result: Array = []
	for event in battle.events:
		if event.kind == "release" and event.ability == "sword_attack":
			result.append(event.frame)
	return result


func run() -> void:
	for attribute in ["mana", "quality_permille", "mind_capacity"]:
		check(base.actors[1][attribute] > base.actors[0][attribute], "Mid-stage right cultivator has higher " + attribute)
	check(base.actors[1].realm == "练气中期", "Right cultivator is labelled mid-stage")
	check(base.actors[1].hp == 20, "Right cultivator body HP is the requested 20")
	var sword = create(settings())
	until(sword, 30)
	var weapon: Dictionary = sword.active_entities(0, "artifact")[0]
	var identity: int = int(weapon.entity_id)
	check(weapon.cast.start_frame == 30 and weapon.cast.release_frame == 36, "Summoned sword starts its own six-frame windup")
	check(weapon.motion.is_empty() and weapon.cooldowns.is_empty(), "Before release there is neither flight nor internal cooldown")
	until(sword, 36)
	check(weapon.motion.state == "outbound" and weapon.motion.hit_frame == 81 and weapon.motion.return_frame == 126, "Release schedules 45-frame outbound and 45-frame return")
	check(weapon.cooldowns.sword_attack == 216, "Internal three-second cooldown begins at actual F36 release")
	check(sword.projectiles.is_empty() and sword.entities.size() == 3, "Attack is the same sword, with no extra sword projectile entity")
	check(sword.mind_used(1) == 1 and weapon.hp_milli == 20000, "Flight preserves the same HP and mind ownership")
	until(sword, 50)
	damage(sword, 10)
	check(weapon.hp_milli == 10000 and sword.actors[0].hp_milli == 1000000, "Outbound sword continues intercepting damage for its owner")
	check(not sword.interrupt_cast(identity), "Outbound presence cannot be interrupted as casting")
	until(sword, 80)
	check(sword.actors[1].hp_milli == 1000000, "No sword damage before physical contact")
	sword.step()
	check(weapon.motion.state == "returning" and sword.actors[1].hp_milli == 990000, "Contact deals damage once and begins return")
	check(not sword.interrupt_cast(identity), "Returning presence also cannot be interrupted")
	until(sword, 126)
	check(weapon.motion.is_empty() and weapon.entity_id == identity and weapon.hp_milli == 10000, "Return retains the same entity and damaged HP")
	until(sword, 215)
	check(weapon.cast.is_empty() and releases(sword) == [36], "Return does not restart or bypass internal cooldown")
	sword.step()
	check(weapon.cast.start_frame == 216 and weapon.cast.release_frame == 222, "Next windup starts exactly 180 frames after release")
	until(sword, 450)
	check(releases(sword) == [36, 222, 408], "Each repeated release includes its new windup duration")
	check(not weapon.active and weapon.motion.is_empty() and sword.actors[1].hp_milli == 980000, "Seven-second expiry cancels third flight before its scheduled contact")
	check(sword.mind_used(1) == 0, "Expiry during flight releases its one mind slot")
	var destroyed = create(settings())
	until(destroyed, 60)
	var destroyed_weapon: Dictionary = destroyed.active_entities(0, "artifact")[0]
	damage(destroyed, 20)
	until(destroyed, 81)
	check(not destroyed_weapon.active and destroyed_weapon.motion.is_empty(), "Destroying flying sword cancels its remaining motion")
	check(destroyed.actors[1].hp_milli == 1000000, "Sword destroyed before contact causes no delayed ghost damage")
	var returning = create(settings())
	until(returning, 90)
	damage(returning, 20)
	check(returning.actors[1].hp_milli == 990000, "Destruction during return does not undo settled damage")
	var protection_config: Dictionary = settings()
	protection_config.cast_interval_frames = 0
	protection_config.actors[0].actions = {"shield": {}, "qingyun_sword": {}}
	protection_config.actors[0].mana = 60
	var protection = create(protection_config)
	until(protection, 100)
	var protection_weapon: Dictionary = protection.active_entities(0, "artifact")[0]
	check(protection_weapon.motion.state == "outbound", "Defensive priority scenario attacks while sword is away")
	damage(protection, 60)
	check(protection.active_entities(0, "shield").is_empty() and protection_weapon.hp_milli == 10000 and protection.actors[0].hp_milli == 1000000, "Away sword still follows shield-before-sword-before-body ordering")
	var return_config: Dictionary = settings()
	return_config.cast_interval_frames = 0
	return_config.sword_attack_cooldown_frames = 0
	var must_return = create(return_config)
	until(must_return, 125)
	var return_weapon: Dictionary = must_return.active_entities(0, "artifact")[0]
	check(return_weapon.cast.is_empty() and releases(must_return) == [36], "Zero cooldown still cannot begin another cast before return")
	must_return.step()
	check(return_weapon.cast.start_frame == 126, "Return completion frees this same entity to cast again")
	var slow_return_config: Dictionary = settings()
	slow_return_config.sword_outbound_frames = 90
	slow_return_config.sword_return_frames = 150
	var slow_return = create(slow_return_config)
	until(slow_return, 275)
	var slow_weapon: Dictionary = slow_return.active_entities(0, "artifact")[0]
	check(slow_weapon.cooldowns.sword_attack == 216 and slow_weapon.cast.is_empty(), "Cooldown can finish while sword is still returning")
	slow_return.step()
	check(slow_weapon.cast.start_frame == 276, "Next cast waits for return without adding a second cooldown afterward")
	var slow_cast_config: Dictionary = settings()
	slow_cast_config.sword_windup_frames = 120
	var slow_cast = create(slow_cast_config)
	until(slow_cast, 150)
	var slow_caster: Dictionary = slow_cast.active_entities(0, "artifact")[0]
	check(slow_caster.cooldowns.sword_attack == 330 and releases(slow_cast) == [150], "Long entity windup starts cooldown at release rather than summon time")
	until(slow_cast, 330)
	check(slow_caster.cast.start_frame == 330, "Same autonomous model supports long-windup entity attacks")
	var boundary_config: Dictionary = settings()
	boundary_config.sword_outbound_frames = 414
	var boundary = create(boundary_config)
	until(boundary, 450)
	check(boundary.actors[1].hp_milli == 1000000, "Expiry on exact contact frame takes precedence and cancels damage")
	var concurrent_config: Dictionary = settings()
	concurrent_config.cast_interval_frames = 0
	concurrent_config.actors[0].actions = {"qingyun_sword": {}, "fireball": {}}
	concurrent_config.actors[0].mana = 20
	var concurrent = create(concurrent_config)
	until(concurrent, 78)
	check(concurrent.projectiles.size() == 1 and not concurrent.active_entities(0, "artifact")[0].motion.is_empty(), "Owner can cast fireball while its sword is in flight")
	var simultaneous_config: Dictionary = settings()
	simultaneous_config.spell.windup_frames = 57
	simultaneous_config.actors[1].mana = 10
	simultaneous_config.actors[1].quality_permille = 2000
	var simultaneous = create(simultaneous_config)
	until(simultaneous, 81)
	check(simultaneous.active_entities(0, "artifact").is_empty() and simultaneous.actors[1].hp_milli == 990000, "Same-frame sword contact and lethal interception settle together")
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	var file := FileAccess.open("res://test-sword-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("SWORD TESTS: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
