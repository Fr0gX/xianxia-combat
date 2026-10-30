extends SceneTree

const Battle = preload("res://scripts/core/battle.gd")
const ActionSequence = preload("res://scripts/core/action_sequence.gd")
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


func create(config: Dictionary) -> RefCounted:
	var battle = Battle.new()
	battle.reset(config)
	return battle


func until(battle: RefCounted, frame: int) -> void:
	while not battle.finished and battle.frame < frame:
		battle.step()


func settings() -> Dictionary:
	var config: Dictionary = base.duplicate(true)
	config.actors[0].hp = 1000
	config.actors[0].actions = {"fireball": {}}
	return config


func run() -> void:
	var owned: Dictionary = ActionSequence.instantiate({"fireball": {}, "fireball_full": {}, "shield": {}}, 17)
	check(owned.size() == 3 and owned.fireball.instance_id != owned.fireball_full.instance_id, "Normal and full fireballs are distinct owned spell identities")
	var reference: Dictionary = owned.fireball
	var reordered: Dictionary = ActionSequence.move(owned, "fireball", 2)
	reference.marker = "same instance"
	check(reordered.keys() == ["fireball_full", "shield", "fireball"] and reordered.fireball.marker == "same instance", "Reordering preserves the original action instances")
	check(reordered.size() == owned.size() and reordered.fireball.instance_id == "17:fireball", "Order changes do not allocate extra owned spells")
	var saved: Dictionary = ActionSequence.definitions(reordered)
	check(saved.fireball.marker == "same instance" and not saved.fireball.has("instance_id"), "Saving preserves action properties without leaking runtime identity")
	var repeated_config: Dictionary = settings()
	repeated_config.actors[1].passives = {}
	repeated_config.actors[1].hp = 1000
	repeated_config.actors[1].mana = 0
	var repeated = create(repeated_config)
	until(repeated, 270)
	var invocation_ids: Array = []
	var spell_ids: Array = []
	for event in repeated.events:
		if event.kind == "cast" and event.entity_id == 1:
			invocation_ids.append(event.action_id)
			spell_ids.append(event.spell_instance_id)
	check(repeated.actors[0].sequence.size() == 1 and spell_ids == ["1:fireball", "1:fireball", "1:fireball"], "Repeated casting reuses one registered spell instance")
	check(invocation_ids[0] != invocation_ids[1], "Cast executions have their own lifecycle identities")
	var separate_config: Dictionary = repeated_config.duplicate(true)
	separate_config.actors[0].actions = {"fireball": {}, "fireball_full": {}}
	var separate = create(separate_config)
	until(separate, 150)
	var spells: Array = []
	for event in separate.events:
		if event.kind == "release" and event.entity_id == 1:
			spells.append(event.ability)
	check(spells == ["fireball", "fireball_full"] and separate.actors[0].mana == 60, "Both fireball spells can execute in the same ordered collection")
	var passive = create(settings())
	check(passive.active_entities(1, "shield").is_empty(), "Battle-start passive is not activated by merely editing configuration")
	passive.step()
	var shields: Array = passive.active_entities(1, "shield")
	check(shields.size() == 1 and shields[0].hp_milli == 20000, "First battle frame grants exactly 20 shield HP")
	check(passive.actors[1].hp_milli == 20000 and passive.actors[1].mana == 200, "Passive preserves body HP20 and consumes no MP")
	check(passive.actors[1].cooldowns.is_empty() and passive.actors[1].next_cast_frame == 0, "Passive starts neither a cooldown nor a casting interval")
	check(passive.actors[1].cast.start_frame == 0 and passive.actors[1].cast.ability == "fireball", "Passive does not delay the first active spell")
	check(passive.actors[1].sequence.keys() == ["fireball"], "Passive is not inserted into active action order")
	check(passive.mind_used(2) == 1, "Generated passive shield uses the same one-slot entity rule")
	var shield: Dictionary = shields[0]
	check(shield.context.passive_id == "innate_shield" and shield.context.provider.kind == "realm", "Generated entity retains passive and provider origin")
	var origin: Dictionary = passive.actions[int(shield.presence.parent_id)]
	check(origin.kind == "effect" and origin.parent_id == passive.actors[1].presence.id, "Passive uses effect-to-presence without creating a cast lifecycle")
	var shield_casts: int = 0
	var activations: int = 0
	for event in passive.events:
		if event.kind == "cast" and event.ability == "shield":
			shield_casts += 1
		if event.kind == "passive":
			activations += 1
	check(shield_casts == 0 and activations == 1, "One passive activation causes no shield spellcast")
	passive.trigger_passives("battle_start")
	passive.flush_effects()
	check(passive.active_entities(1, "shield").size() == 1, "Battle-start dispatch is idempotent within a battle")
	until(passive, 54)
	check(shield.hp_milli == 10000 and passive.actors[1].hp_milli == 20000, "Passive shield intercepts the first hit normally")
	check(passive.get_statistics()[1].taken_by_kind.shield == 10000, "Passive shield damage joins the existing summary statistics")
	until(passive, 174)
	check(not shield.active and passive.actors[1].hp_milli == 20000 and passive.mind_used(2) == 0, "Destroying passive shield returns its slot without harming the body")
	passive.trigger_passives("battle_start")
	passive.flush_effects()
	check(passive.active_entities(1, "shield").is_empty(), "Destroyed start shield does not regenerate from repeated start requests")
	passive.reset(settings())
	passive.step()
	check(passive.active_entities(1, "shield").size() == 1 and passive.get_statistics()[1].damage_taken_milli == 0, "Replay reactivates passive once and clears old damage")
	for provider in ["realm", "cultivation", "artifact"]:
		var provider_config: Dictionary = settings()
		provider_config.actors[1].passives.innate_shield.source = {"kind": provider}
		var sourced = create(provider_config)
		sourced.step()
		check(sourced.active_entities(1, "shield")[0].context.provider.kind == provider, "Same passive can originate from " + provider)
	var capacity_config: Dictionary = settings()
	capacity_config.actors[1].mind_capacity = 0
	var no_capacity = create(capacity_config)
	no_capacity.step()
	check(no_capacity.active_entities(1, "shield").is_empty() and no_capacity.actors[1].mana == 200, "Passive-generated entity obeys capacity without consuming MP on failure")
	var idle_config: Dictionary = settings()
	idle_config.actors[0].actions = {}
	idle_config.actors[1].actions = {}
	var idle = create(idle_config)
	idle.step()
	check(idle.active_entities(1, "shield").size() == 1 and idle.result == "stalemate", "Passive-only actors need no artificial active action slots")
	var normal = create(base)
	var fast = create(base)
	while not normal.finished:
		normal.step()
	while not fast.finished:
		for i in range(4):
			fast.step()
	check(normal.snapshot() == fast.snapshot() and normal.events == fast.events, "Passive setup and identity scheduling remain deterministic at 1x and 4x")
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	var file := FileAccess.open("res://test-passives-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("PASSIVE / IDENTITY TESTS: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
