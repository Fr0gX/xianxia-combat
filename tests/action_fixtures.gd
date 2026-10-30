extends RefCounted
## Compact fixture notation only. Runtime/configuration use keyed registries.
static func definitions(names: Array) -> Dictionary:
	var result: Dictionary = {}
	for ability in names:
		if ability in ["normal", "full"]:
			result["fireball_full" if ability == "full" else "fireball"] = {}
		else:
			result[ability] = {}
	return result
