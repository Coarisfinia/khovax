class_name ExploredGround
extends RefCounted
## What this machine's player has explored in one world (#215): per instance by blueprint name, the
## tiles seen there, and the instance's generation then (#212). A purged instance comes back
## arranged anew, so what was seen in an earlier generation no longer fits its ground: it is
## dropped, here and only here, whoever remembers into it (FogView) or saves it (WorldSave).

## The tiles seen in each instance, by blueprint name.
var tiles_in: Dictionary[String, Dictionary] = {}
## The generation of each instance in `tiles_in` when its tiles were seen.
var generations: Dictionary[String, int] = {}


## The tiles seen in `instance_name` at its generation `generation`, to remember into: empty at
## first, and emptied when they were seen in another generation.
func tiles_of(instance_name: String, generation: int) -> Dictionary[Vector2i, bool]:
	if not tiles_in.has(instance_name) or generations[instance_name] != generation:
		var fresh: Dictionary[Vector2i, bool] = {}
		tiles_in[instance_name] = fresh
		generations[instance_name] = generation
	return tiles_in[instance_name]


## The tiles seen in `instance_name` at its generation `generation`, only to read: none when they
## were seen in another generation, and nothing is noted for it.
func seen(instance_name: String, generation: int) -> Dictionary:
	if generations.get(instance_name, -1) != generation:
		return {}
	return tiles_in[instance_name]


## Drops what was seen in an earlier generation of an instance `world` has purged since.
func forget_purged(world: World) -> void:
	for instance_name: String in tiles_in.keys():
		if generations[instance_name] != world.generation(instance_name):
			var _dropped: bool = tiles_in.erase(instance_name)
			var _forgotten: bool = generations.erase(instance_name)


## Forgets everything.
func clear() -> void:
	tiles_in.clear()
	generations.clear()
