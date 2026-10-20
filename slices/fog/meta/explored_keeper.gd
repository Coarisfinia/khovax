class_name ExploredKeeper
extends WorldCompanion
## Keeps the ground this machine's player explored in the world (#215; FogView remembers it into
## `explored_in`, the Survey reads it) with the world, in the same file at the same moments
## (WorldKeeper, whose companion it is), so the two go together: a fresh world starts with none.

## What this machine's player has explored in `_explored_world` (`explored_in`).
var explored: ExploredGround = ExploredGround.new()
var _explored_world: World = null


func resumed(saved: World, path: String) -> void:
	# Nothing explored is kept unless the saved world is resumed.
	explored = ExploredGround.new()
	_explored_world = saved
	if saved == null:
		return
	var problem: String = ExploredSave.load_into(path, explored, saved.source)
	if not problem.is_empty():
		push_warning("the explored ground can't be read, so none is remembered: " + problem)
	# What was seen in an instance purged since won't fit its ground when it comes back.
	explored.forget_purged(saved)


func beside(world: World) -> Dictionary:
	return ExploredSave.beside(explored_in(world))


## The ground explored in `world`, to remember into: what was saved with it when it's the world
## resumed, and nothing yet in any other (a fresh one, or one started as the saved one was refused).
func explored_in(world: World) -> ExploredGround:
	if world != _explored_world:
		_explored_world = world
		explored = ExploredGround.new()
	return explored
