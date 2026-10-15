class_name NeighbourView
extends Node3D
## The instances next door (#188, seamless world #155): every instance an exit of the local
## player's instance leads to is drawn at its place in the world (`World.offset`), as a HexGrid of
## its own, so the ground goes on past the exits. Only the directly connected ones (owner's rule).
## Under FogCloud, their ground lies under thick cloud, or light fog where this machine's player
## explored it before (FogView keeps that per instance, #190).
##
## A neighbour's region is read with `InstanceBlueprints.region_of` and the world's seed for it,
## never by loading the instance: the world's hash covers every loaded instance, so loading one
## from a view would change the simulation.

@export var driver: GameDriver

## Each neighbour's grid, by blueprint name, placed relative to the local instance.
var grids: Dictionary[String, HexGrid] = {}
## How far each neighbour's tiles are shifted into the local instance's coordinates, by name.
var shifts: Dictionary[String, Vector2i] = {}
## The instance the neighbours were found for.
var _state: GameState
## Every neighbour tile in the local instance's coordinates.
var _placed: Array[Vector2i] = []
## Each blueprint's region for the world shown, read once per generation (#212): a purged
## instance comes back arranged anew.
var _regions: Dictionary[String, Region] = {}
## The generation each region in `_regions` was read for, by name.
var _generations: Dictionary[String, int] = {}
var _world: World


func _process(_delta: float) -> void:
	show_state()


## Finds and draws the neighbours of the local player's instance whenever it changes: walking into
## the next instance makes the old one a neighbour, and whenever a neighbour was purged. Called
## every frame; tests call it after
## changing the state.
func show_state() -> void:
	var state: GameState = driver.state if driver != null else null
	if state == _state and not _rearranged():
		return
	_state = state
	for old: HexGrid in grids.values():
		remove_child(old)
		old.queue_free()
	grids.clear()
	shifts.clear()
	_placed.clear()
	if state == null:
		return
	if driver.world != _world:
		_world = driver.world
		_regions.clear()
	var current: String = name_of(_world, state)
	for target: String in state.region.exit_blueprints:
		if not grids.has(target):
			grids[target] = _grid_for(target, current)


## Every tile of every neighbour, in the local instance's coordinates: where the cloud has to reach.
func placed_tiles() -> Array[Vector2i]:
	show_state()
	return _placed


## Whether a neighbour drawn now has been purged since (#212): it is drawn again, arranged anew.
func _rearranged() -> bool:
	for target: String in grids:
		if _generations[target] != _world.generation(target):
			return true
	return false


## A grid drawing the instance `target` where it lies next to `current`.
func _grid_for(target: String, current: String) -> HexGrid:
	if not _regions.has(target) or _generations[target] != _world.generation(target):
		_regions[target] = InstanceBlueprints.region_of(target, _world.seed_for(target))
		_generations[target] = _world.generation(target)
	var shift: Vector2i = _world.offset(target) - _world.offset(current)
	shifts[target] = shift
	var neighbour: HexGrid = HexGrid.new()
	neighbour.fixed_region = _regions[target]
	neighbour.name = target
	neighbour.position = HexLayout.to_world(shift)
	add_child(neighbour)
	for tile: Vector2i in _regions[target].sorted_tiles():
		_placed.append(tile + shift)
	return neighbour


## The blueprint name `world` keeps `state` under, or "".
static func name_of(world: World, state: GameState) -> String:
	for instance_name: String in world.instances:
		if world.instances[instance_name] == state:
			return instance_name
	return ""
