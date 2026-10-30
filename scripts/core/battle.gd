extends RefCounted
## Three action kinds: cast / presence / effect. Only casts are interruptible.
const Rules = preload("res://scripts/core/rules.gd")
const ActionSequence = preload("res://scripts/core/action_sequence.gd")
const MAX_EFFECTS_PER_FRAME: int = 1024

var config: Dictionary
var actors: Array = []
var entities: Dictionary = {}
var actions: Dictionary = {}
var statistics: Array = []
var projectiles: Array = []
var events: Array = []
var effect_queue: Array = []
var frame: int = -1
var finished: bool = false
var result: String = ""
var serial: int = 0
var entity_serial: int = 0
var action_serial: int = 0
var effects_this_frame: int = 0
var passive_bindings: Array = []
var passives_started: bool = false


func reset(settings: Dictionary) -> void:
	config = Rules.compile(settings)
	actors.clear()
	entities.clear()
	actions.clear()
	statistics.clear()
	projectiles.clear()
	events.clear()
	effect_queue.clear()
	passive_bindings.clear()
	passives_started = false
	frame = -1
	finished = false
	result = ""
	serial = 0
	entity_serial = 0
	action_serial = 0
	for side in range(2):
		statistics.append({"damage_dealt_milli": 0, "damage_taken_milli": 0,
			"taken_by_kind": {"shield": 0, "artifact": 0, "cultivator": 0}})
		var actor: Dictionary = config.actors[side].duplicate(true)
		entity_serial += 1
		actor.entity_id = entity_serial
		actor.owner_id = entity_serial
		actor.side = side
		actor.kind = "cultivator"
		actor.active = true
		actor.hp_milli = int(actor.hp) * 1000
		actor.max_hp_milli = actor.hp_milli
		actor.mana = int(actor.mana)
		actor.max_mana = actor.mana
		actor.mind_capacity = int(actor.get("mind_capacity", 2))
		actor.mind_cost = 0
		actor.sequence = ActionSequence.instantiate(actor.actions, entity_serial)
		actor.sequence_index = 0
		actor.cast = {}
		actor.ready_frame = 0
		actor.next_cast_frame = 0
		actor.last_cast_frame = -1
		actor.last_release_frame = -1
		actor.cooldowns = {}
		actor.deferred_actions = {}
		actor.defer_serial = 0
		actor.waiting_until = 0
		actor.blocked = false
		actor.waiting = ""
		actor.presence = new_action("presence", entity_serial, 0)
		entities[entity_serial] = actor
		actors.append(actor)
	for actor in actors:
		for passive_id in actor.passives:
			passive_bindings.append({"owner_id": actor.entity_id, "id": passive_id,
				"source": actor.passives[passive_id].get("source", {})})


func trigger_passives(trigger: String) -> void:
	if finished:
		return
	if trigger == "battle_start":
		if passives_started:
			return
		passives_started = true
	for binding in passive_bindings:
		var owner: Dictionary = entities[int(binding.owner_id)]
		if not owner.active:
			continue
		var definition: Dictionary = config.library.passives[binding.id]
		var effects: Array = definition.triggers.get(trigger, [])
		if effects.is_empty():
			continue
		var context := {"side": owner.side, "owner_id": owner.entity_id, "source_id": owner.entity_id,
			"ability": "", "mode": "normal", "cost": 0, "quality_permille": owner.quality_permille,
			"power_base": 0, "damage_milli": 0, "passive_id": binding.id, "provider": binding.source}
		emit_event("passive", {"side": owner.side, "entity_id": owner.entity_id,
			"passive_id": binding.id, "name": definition.name, "source": binding.source})
		queue_effects(effects, owner.entity_id, owner.presence.id, context)


func new_action(kind: String, source_id: int, parent_id: int) -> Dictionary:
	action_serial += 1
	var record := {"id": action_serial, "kind": kind, "source_id": source_id,
		"parent_id": parent_id, "start_frame": frame, "end_frame": -1, "status": "active"}
	actions[action_serial] = record
	return record


func emit_event(kind: String, details: Dictionary = {}) -> void:
	var event: Dictionary = details.duplicate(true)
	event.kind = kind
	event.frame = frame
	events.append(event)


func combat_open() -> bool:
	return actors[0].hp_milli > 0 and actors[1].hp_milli > 0


func step() -> void:
	if finished:
		return
	frame += 1
	effects_this_frame = 0
	if frame == 0:
		trigger_passives("battle_start")
		flush_effects()
	# All arrivals resolve before new releases. Expiration is exclusive.
	for entity in entities.values():
		if not entity.active or entity.kind == "cultivator":
			continue
		var end_frame: int = int(entity.get("hit_frame", entity.presence.get("expires_frame", -1)))
		if end_frame >= 0 and end_frame <= frame:
			if entity.kind == "projectile":
				queue_effects(entity.get("on_end", []), entity.entity_id, entity.presence.id, entity.context)
			end_presence(entity, "impact" if entity.kind == "projectile" else "expired")
	# Motion is part of the same entity's presence; expiry/destruction cancels it.
	for entity in entities.values():
		if not entity.active or entity.get("motion", {}).is_empty():
			continue
		var motion: Dictionary = entity.motion
		if motion.state == "outbound" and frame >= int(motion.hit_frame):
			queue_effects([{"type": "damage"}], entity.entity_id, motion.effect_id, motion.context)
			motion.state = "returning"
			emit_event("contact", {"side": entity.side, "entity_id": entity.entity_id})
		if frame >= int(motion.return_frame):
			entity.motion = {}
			emit_event("return", {"side": entity.side, "entity_id": entity.entity_id})
	flush_effects()
	if not combat_open():
		for entity in entities.values():
			cancel_cast(entity, "combat_closed")
	else:
		for entity in entities.values():
			if entity.active and not entity.cast.is_empty() and int(entity.cast.release_frame) <= frame:
				release_cast(entity)
				flush_effects()
		for entity in entities.values():
			if not entity.active or entity.kind == "cultivator":
				continue
			if entity.has("sequence") and entity.cast.is_empty() and not entity.blocked and frame >= int(entity.ready_frame):
				schedule_actor(entity)
		flush_effects()
		for actor in actors:
			if actor.cast.is_empty() and not actor.blocked and frame >= int(actor.ready_frame):
				schedule_actor(actor)
				flush_effects()
	check_end()


func mind_used(owner_id: int) -> int:
	var used: int = 0
	for entity in entities.values():
		if entity.active and int(entity.owner_id) == owner_id:
			used += int(entity.get("mind_cost", 0))
	return used


func mind_required(ability_id: String, depth: int = 0) -> int:
	if depth >= 16:
		return 1000000
	var total: int = 0
	for effect in config.library.abilities[ability_id].effects:
		if effect.type == "spawn":
			var template: Dictionary = config.library.templates[effect.template]
			total += int(template.get("mind_cost", 1))
			for nested in template.get("on_enter", []):
				if nested.type == "cast" and nested.get("target", "self") == "self":
					total += mind_required(nested.ability, depth + 1)
	return total


func has_capacity(source: Dictionary, ability_id: String) -> bool:
	var owner: Dictionary = entities[int(source.owner_id)]
	return mind_used(owner.entity_id) + mind_required(ability_id) <= int(owner.mind_capacity)


func casting_cost(selection: Dictionary) -> int:
	return int(config.library.abilities[selection.ability].mana_cost)


func schedule_actor(actor: Dictionary, parent_id: int = 0) -> void:
	var trigger_parent: int = parent_id if parent_id > 0 else int(actor.presence.id)
	var keys: Array = actor.sequence.keys()
	if keys.is_empty():
		actor.blocked = true
		actor.waiting = "no_actions"
		return
	var affordable: bool = actor.kind != "cultivator"
	for item in actor.sequence.values():
		if actor.kind == "cultivator" and casting_cost(item) <= int(actor.mana):
			affordable = true
	if not affordable:
		actor.blocked = true
		emit_event("exhausted", {"side": actor.side, "entity_id": actor.entity_id,
			"cost": casting_cost(actor.sequence[keys[int(actor.sequence_index)]]), "mana": actor.mana})
		return
	if not actor.get("motion", {}).is_empty():
		actor.waiting = "return"
		actor.waiting_until = actor.motion.return_frame
		return
	if frame < int(actor.next_cast_frame):
		actor.waiting = "interval"
		actor.waiting_until = actor.next_cast_frame
		return
	var ready: Array = []
	for key in actor.deferred_actions:
		var ready_frame: int = int(actor.cooldowns.get(key, 0))
		if ready_frame <= frame:
			ready.append({"key": key, "order": actor.deferred_actions[key], "ready_frame": ready_frame})
	ready.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.ready_frame) < int(b.ready_frame) if a.ready_frame != b.ready_frame else int(a.order) < int(b.order))
	if not ready.is_empty():
		var key: String = ready[0].key
		var selection: Dictionary = actor.sequence[key].duplicate(true)
		selection.advance_sequence = true
		selection.sequence_slot = keys.find(key)
		selection.from_deferred = true
		start_cast(actor.entity_id, selection, trigger_parent)
		return
	for i in range(keys.size()):
		var index: int = int(actor.sequence_index)
		var key: String = keys[index]
		if actor.deferred_actions.has(key):
			actor.sequence_index = (index + 1) % keys.size()
			continue
		var selection: Dictionary = actor.sequence[key].duplicate(true)
		if frame < int(actor.cooldowns.get(key, 0)):
			actor.defer_serial += 1
			actor.deferred_actions[key] = actor.defer_serial
			emit_event("defer", {"side": actor.side, "entity_id": actor.entity_id,
				"ability": key, "ready_frame": actor.cooldowns[key]})
			actor.sequence_index = (index + 1) % keys.size()
			continue
		selection.advance_sequence = true
		selection.sequence_slot = index
		selection.from_deferred = false
		start_cast(actor.entity_id, selection, trigger_parent)
		return
	actor.waiting = "cooldown"
	actor.waiting_until = 2147483647
	for key in actor.deferred_actions:
		actor.waiting_until = mini(int(actor.waiting_until), int(actor.cooldowns.get(key, 0)))


func start_cast(source_id: int, selection: Dictionary, parent_id: int = 0) -> bool:
	if finished or not combat_open() or not entities.has(source_id):
		return false
	var source: Dictionary = entities[source_id]
	if not source.active or not source.cast.is_empty() or frame < int(source.ready_frame):
		return false
	if not source.get("motion", {}).is_empty():
		source.waiting = "return"
		source.waiting_until = source.motion.return_frame
		return false
	var ability_id: String = selection.ability
	var definition: Dictionary = config.library.abilities[ability_id]
	var mode: String = definition.get("mode", "normal")
	var cost: int = int(definition.mana_cost)
	var multiplier: int = int(definition.get("damage_multiplier", 1))
	if source.kind == "cultivator" and int(source.mana) < cost:
		source.blocked = true
		emit_event("exhausted", {"side": source.side, "entity_id": source_id, "cost": cost, "mana": source.mana})
		return false
	if frame < int(source.next_cast_frame):
		source.waiting = "interval"
		source.waiting_until = source.next_cast_frame
		return false
	if frame < int(source.cooldowns.get(ability_id, 0)):
		source.waiting = "cooldown"
		source.waiting_until = int(source.cooldowns[ability_id])
		return false
	if not has_capacity(source, ability_id):
		source.waiting = "mind"
		return false
	source.waiting = ""
	source.waiting_until = 0
	var cast: Dictionary = new_action("cast", source_id, parent_id)
	cast.ability = ability_id
	cast.mode = mode
	cast.cost = cost
	cast.damage_multiplier = multiplier
	cast.advance_sequence = selection.get("advance_sequence", false)
	cast.action_key = selection.get("action_key", ability_id)
	cast.spell_instance_id = source.get("sequence", {}).get(ability_id, {}).get("instance_id", "%d:%s" % [source_id, ability_id])
	cast.sequence_slot = selection.get("sequence_slot", source.get("sequence_index", 0))
	cast.from_deferred = selection.get("from_deferred", false)
	cast.release_frame = frame + int(definition.windup_frames)
	cast.recovery_frames = int(definition.recovery_frames)
	source.last_cast_frame = frame
	source.cast = cast
	emit_event("cast", {"side": source.side, "entity_id": source_id, "action_id": cast.id,
		"parent_id": parent_id, "ability": ability_id, "mode": mode, "from_deferred": cast.from_deferred,
		"spell_instance_id": cast.spell_instance_id})
	if cast.release_frame == frame:
		release_cast(source)
	return true


func release_cast(source: Dictionary) -> void:
	var cast: Dictionary = source.cast
	if cast.is_empty():
		return
	if not has_capacity(source, cast.ability):
		source.waiting = "mind"
		cast.release_frame = frame + 1
		return
	source.waiting = ""
	var definition: Dictionary = config.library.abilities[cast.ability]
	var quality: int = int(source.get("quality_permille", 1000))
	var power_base: int = int(definition.get("power_base", definition.mana_cost))
	var damage_milli: int = power_base * quality * int(cast.damage_multiplier)
	if definition.get("inherit_power", false):
		damage_milli = int(source.context.damage_milli)
		power_base = int(source.context.power_base)
	if source.kind == "cultivator":
		source.mana -= int(cast.cost)
	if cast.advance_sequence:
		if cast.from_deferred:
			source.deferred_actions.erase(cast.action_key)
		else:
			source.sequence_index = (int(cast.sequence_slot) + 1) % source.sequence.size()
	var context := {"side": source.side, "owner_id": source.owner_id, "source_id": source.entity_id,
		"ability": cast.ability, "mode": cast.mode, "cost": cast.cost,
		"quality_permille": quality, "power_base": power_base, "damage_milli": damage_milli}
	cast.status = "released"
	cast.end_frame = frame
	source.cast = {}
	source.ready_frame = frame + int(cast.recovery_frames)
	source.last_release_frame = frame
	source.next_cast_frame = frame + int(source.get("cast_interval_frames", config.cast_interval_frames))
	source.cooldowns[cast.ability] = frame + int(definition.get("cooldown_frames", 0))
	emit_event("release", {"side": source.side, "entity_id": source.entity_id, "action_id": cast.id,
		"ability": cast.ability, "mode": cast.mode, "cost": cast.cost, "mana": source.get("mana", 0),
		"spell_instance_id": cast.spell_instance_id,
		"power_base": power_base, "damage_multiplier": cast.damage_multiplier,
		"damage_milli": damage_milli, "quality_permille": quality})
	queue_effects(definition.effects, source.entity_id, cast.id, context)


func queue_effects(definitions: Array, source_id: int, parent_id: int, context: Dictionary) -> void:
	for definition in definitions:
		var effect: Dictionary = new_action("effect", source_id, parent_id)
		effect.definition = definition.duplicate(true)
		effect.context = context.duplicate(true)
		effect_queue.append(effect)


func flush_effects() -> void:
	var damage_effects: Array = []
	while not effect_queue.is_empty() and not finished:
		var effect: Dictionary = effect_queue.pop_front()
		effects_this_frame += 1
		if effects_this_frame > MAX_EFFECTS_PER_FRAME:
			finish("effect_limit")
			push_error("Same-frame effect limit exceeded")
			return
		var definition: Dictionary = effect.definition
		match definition.type:
			"spawn":
				if not spawn_entity(definition.template, effect):
					effect.status = "blocked"
			"cast":
				var target: int = int(definition.get("target_id", effect.source_id))
				if definition.get("target", "self") == "owner":
					target = int(effect.context.owner_id)
				if definition.get("use_sequence", false):
					schedule_actor(entities[target], effect.id)
				else:
					start_cast(target, {"ability": definition.ability}, effect.id)
			"strike":
				var source: Dictionary = entities[effect.source_id]
				if source.active:
					source.motion = {"state": "outbound", "release_frame": frame,
						"hit_frame": frame + int(definition.outbound_frames),
						"return_frame": frame + int(definition.outbound_frames) + int(definition.return_frames),
						"effect_id": effect.id, "context": effect.context.duplicate(true)}
					emit_event("launch", {"side": source.side, "entity_id": source.entity_id,
						"action_id": effect.id, "hit_frame": source.motion.hit_frame})
			"damage":
				damage_effects.append(effect)
			"interrupt":
				interrupt_cast(int(definition.get("target_id", effect.source_id)), definition.get("reason", "control"))
		if definition.type != "damage":
			if effect.status == "active":
				effect.status = "completed"
			effect.end_frame = frame
	if not damage_effects.is_empty():
		resolve_damage(damage_effects)


func spawn_entity(template_id: String, effect: Dictionary) -> bool:
	var entity: Dictionary = config.library.templates[template_id].duplicate(true)
	entity.merge(effect.definition.get("overrides", {}), true)
	var context: Dictionary = effect.context.duplicate(true)
	var owner: Dictionary = entities[int(context.owner_id)]
	if mind_used(owner.entity_id) + int(entity.get("mind_cost", 0)) > int(owner.mind_capacity):
		return false
	entity_serial += 1
	entity.entity_id = entity_serial
	entity.template = template_id
	entity.side = int(context.side)
	entity.owner_id = int(context.owner_id)
	entity.quality_permille = int(context.quality_permille)
	entity.active = true
	entity.cast = {}
	entity.waiting = ""
	entity.ready_frame = frame
	entity.next_cast_frame = frame
	entity.last_cast_frame = -1
	entity.last_release_frame = -1
	entity.waiting_until = 0
	entity.cooldowns = {}
	entity.motion = {}
	entity.sequence_index = 0
	entity.deferred_actions = {}
	entity.defer_serial = 0
	entity.blocked = false
	if entity.has("actions"):
		entity.sequence = ActionSequence.instantiate(entity.actions, entity_serial)
	entity.context = context
	entity.hp_milli = int(entity.get("hp", 0)) * 1000
	if entity.get("hp_from_cost", false):
		entity.hp_milli = int(context.cost) * 1000
	entity.max_hp_milli = entity.hp_milli
	entity.presence = new_action("presence", entity_serial, effect.id)
	var duration: int = int(entity.get("duration_frames", -1))
	entity.presence.expires_frame = frame + duration if duration >= 0 else -1
	entities[entity_serial] = entity
	if entity.kind == "projectile":
		serial += 1
		entity.id = serial
		entity.target = 1 - int(entity.side)
		entity.mode = context.mode
		entity.damage_milli = int(context.damage_milli)
		entity.release_frame = frame
		entity.hit_frame = frame + duration
		projectiles.append(entity)
	emit_event("spawn", {"side": entity.side, "entity_id": entity_serial, "action_id": entity.presence.id,
		"parent_id": effect.id, "template": template_id, "hp_milli": entity.hp_milli})
	queue_effects(entity.get("on_enter", []), entity_serial, entity.presence.id, context)
	if entity.has("sequence"):
		queue_effects([{"type": "cast", "use_sequence": true}], entity_serial, entity.presence.id, context)
	return true


func resolve_damage(effects: Array) -> void:
	var incoming := [0, 0]
	for effect in effects:
		var context: Dictionary = effect.context
		var target: int = 1 - int(context.side)
		incoming[target] += int(context.damage_milli)
		emit_event("hit", {"side": context.side, "target": target, "entity_id": effect.source_id,
			"action_id": effect.id, "damage_milli": context.damage_milli})
		effect.status = "completed"
		effect.end_frame = frame
	for side in range(2):
		var remaining: int = incoming[side]
		for defender in defenders(side):
			if remaining <= 0:
				break
			var before: int = int(defender.hp_milli)
			var absorbed: int = mini(before, remaining)
			defender.hp_milli -= absorbed
			remaining -= absorbed
			statistics[side].damage_taken_milli += absorbed
			statistics[1 - side].damage_dealt_milli += absorbed
			var kinds: Dictionary = statistics[side].taken_by_kind
			kinds[defender.kind] = int(kinds.get(defender.kind, 0)) + absorbed
			emit_event("damage", {"side": side, "entity_id": defender.entity_id, "name": defender.name,
				"damage_milli": absorbed, "hp_before": before, "hp_after": defender.hp_milli})
			if defender.hp_milli == 0:
				end_presence(defender, "destroyed")


func defenders(side: int) -> Array:
	var targets: Array = []
	for entity in entities.values():
		if entity.active and int(entity.side) == side and int(entity.hp_milli) > 0:
			targets.append(entity)
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ap: int = int(a.get("intercept_priority", 0))
		var bp: int = int(b.get("intercept_priority", 0))
		return ap > bp if ap != bp else int(a.entity_id) < int(b.entity_id))
	return targets


func end_presence(entity: Dictionary, reason: String) -> void:
	if not entity.active:
		return
	entity.active = false
	entity.presence.status = reason
	entity.presence.end_frame = frame
	entity.ended_motion = entity.get("motion", {}).duplicate(true)
	entity.motion = {}
	cancel_cast(entity, "source_ended")
	if entity.kind == "projectile":
		projectiles.erase(entity)
	elif entity.kind == "cultivator":
		emit_event("death", {"side": entity.side, "entity_id": entity.entity_id})
	else:
		emit_event("expire" if reason == "expired" else "destroy", {"side": entity.side,
			"entity_id": entity.entity_id, "name": entity.name})


func cancel_cast(entity: Dictionary, reason: String) -> void:
	if entity.cast.is_empty():
		return
	entity.cast.status = "cancelled"
	entity.cast.reason = reason
	entity.cast.end_frame = frame
	entity.cast = {}


func interrupt_cast(entity_id: int, reason: String = "control") -> bool:
	if finished or not entities.has(entity_id):
		return false
	var entity: Dictionary = entities[entity_id]
	if entity.cast.is_empty():
		return false
	var cast: Dictionary = entity.cast
	cast.status = "interrupted"
	cast.reason = reason
	cast.end_frame = frame
	entity.cast = {}
	entity.ready_frame = frame + 1
	emit_event("interrupt", {"side": entity.side, "entity_id": entity_id,
		"action_id": cast.id, "ability": cast.ability, "reason": reason})
	return true


func active_entities(side: int, kind: String) -> Array:
	var found: Array = []
	for entity in entities.values():
		if entity.active and int(entity.side) == side and entity.kind == kind:
			found.append(entity)
	return found


func check_end() -> void:
	var pending_impact: bool = not projectiles.is_empty()
	for entity in entities.values():
		if entity.active and not entity.get("motion", {}).is_empty() and entity.motion.state == "outbound":
			pending_impact = true
	if not pending_impact:
		var left_dead: bool = actors[0].hp_milli <= 0
		var right_dead: bool = actors[1].hp_milli <= 0
		if left_dead or right_dead:
			finish("double_ko" if left_dead and right_dead else ("right_win" if left_dead else "left_win"))
		elif (actors[0].blocked or actors[0].waiting == "mind") and (actors[1].blocked or actors[1].waiting == "mind"):
			var future_work: bool = false
			for entity in entities.values():
				if entity.active and (not entity.cast.is_empty() or (entity.kind != "cultivator" and entity.has("sequence") and not entity.blocked) or int(entity.presence.get("expires_frame", -1)) >= 0):
					future_work = true
			if not future_work:
				finish("stalemate")
	if not finished and frame >= int(config.max_frames):
		finish("timeout")


func finish(outcome: String) -> void:
	finished = true
	result = outcome
	emit_event("end", {"result": outcome})


func snapshot() -> Dictionary:
	return {"frame": frame, "actors": actors.duplicate(true), "entities": entities.duplicate(true),
		"actions": actions.duplicate(true), "projectiles": projectiles.duplicate(true),
		"statistics": get_statistics(), "finished": finished, "result": result}


func get_statistics() -> Array:
	return statistics.duplicate(true)
