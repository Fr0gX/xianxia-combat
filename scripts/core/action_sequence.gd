extends RefCounted
## An ordered spell registry. Each identity refers to one stable owned instance.

static func instantiate(definition: Dictionary, owner_id: int = 0) -> Dictionary:
	var result: Dictionary = {}
	for ability in definition:
		assert(definition[ability] is Dictionary, "Action properties must be a dictionary")
		var instance: Dictionary = definition[ability].duplicate(true)
		instance.ability = str(ability)
		instance.action_key = str(ability)
		instance.instance_id = "%d:%s" % [owner_id, ability]
		result[str(ability)] = instance
	return result


static func move(registry: Dictionary, action_key: String, destination: int) -> Dictionary:
	var keys: Array = registry.keys()
	if not registry.has(action_key) or destination < 0 or destination >= keys.size():
		return registry
	keys.erase(action_key)
	keys.insert(destination, action_key)
	var reordered: Dictionary = {}
	for key in keys:
		reordered[key] = registry[key]
	return reordered


static func definitions(registry: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in registry:
		var definition: Dictionary = registry[key].duplicate(true)
		for runtime_field in ["ability", "action_key", "instance_id"]:
			definition.erase(runtime_field)
		result[key] = definition
	return result
