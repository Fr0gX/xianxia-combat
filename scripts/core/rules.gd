extends RefCounted

static func compile(settings: Dictionary) -> Dictionary:
	var result: Dictionary = settings.duplicate(true)
	var library: Dictionary = settings.get("library", {})
	if library.is_empty():
		library = JSON.parse_string(FileAccess.get_file_as_string("res://data/actions.json"))
	result.library = library.duplicate(true)
	if not result.library.has("passives"):
		result.library.passives = JSON.parse_string(FileAccess.get_file_as_string("res://data/passives.json"))
	for actor in result.actors:
		assert(actor.has("actions") and actor.actions is Dictionary and not actor.has("sequence"), "Use an ordered action registry, not sequence slots")
		actor.passives = actor.get("passives", {})
		assert(actor.passives is Dictionary, "Passives are keyed by identity")
		for ability in actor.actions:
			assert(result.library.abilities.has(ability), "Unknown action identity: " + str(ability))
	result.cast_interval_frames = int(result.get("cast_interval_frames", 90))
	for field in ["mana_cost", "windup_frames", "recovery_frames"]:
		result.library.abilities.fireball[field] = int(result.spell[field])
	var full: Dictionary = result.library.abilities.fireball_full
	full.mana_cost = int(result.spell.mana_cost) * 3
	full.power_base = int(result.spell.mana_cost)
	full.windup_frames = int(result.spell.windup_frames)
	full.recovery_frames = int(result.spell.recovery_frames)
	result.library.abilities.shield.mana_cost = int(result.get("shield_cost", 50))
	result.library.abilities.qingyun_sword.mana_cost = int(result.get("sword_cost", 10))
	result.library.abilities.shield.cooldown_frames = int(result.get("shield_cooldown_frames", 1200))
	result.library.abilities.qingyun_sword.cooldown_frames = int(result.get("sword_cooldown_frames", 1200))
	result.library.templates.fireball.duration_frames = int(result.spell.flight_frames)
	var sword: Dictionary = result.library.abilities.sword_attack
	sword.windup_frames = int(result.get("sword_windup_frames", sword.windup_frames))
	sword.cooldown_frames = int(result.get("sword_attack_cooldown_frames", sword.cooldown_frames))
	sword.effects[0].outbound_frames = int(result.get("sword_outbound_frames", sword.effects[0].outbound_frames))
	sword.effects[0].return_frames = int(result.get("sword_return_frames", sword.effects[0].return_frames))
	return result


static func action(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	if str(value) in ["normal", "full"]:
		return {"ability": "fireball_full" if str(value) == "full" else "fireball"}
	return {"ability": str(value), "mode": "normal"}


static func name(value: Variant) -> String:
	var item: Dictionary = action(value)
	match item.ability:
		"fireball":
			return "普通火球"
		"fireball_full":
			return "全力火球"
		"shield":
			return "护盾"
		"qingyun_sword":
			return "青云剑"
		"sword_attack":
			return "剑击"
	return str(item.ability)
