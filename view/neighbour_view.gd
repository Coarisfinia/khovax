class_name NeighbourView
extends Node3D
## The instances next door (#188, seamless world #155): every instance an exit of the local
## player's instance leads to is drawn at its place in the world (`World.offset`), as a HexGrid of
## its own, so the ground goes on past the exits. Only the directly connected ones (owner's rule).
## Their ground is unexplored, so it lies under FogCloud's thick cloud.
##
## A neighbour's region is read with `InstanceBlueprints.region_of` and the world's seed for it,
## never by loading the instance: the world's hash covers every loaded instance, so loading one
## from a view would change the simulation.

@export var driver: GameDriver

## Each neighbour's grid, by blueprint name, placed relative to the local instance.
var grids: Dictionary[String, HexGrid] = {}
## The instance the neighbours were found for.
var _state: GameState
## Every neighbour tile in the local instance's coordinates.
var _placed: Array[Vector2i] = []
## Each blueprint's region for the world shown, read once.
var _regions: Dictionary[String, Region] = {}
var _world: World


func _process(_delta: float) -> void:
	show_state()


## Finds and draws the neighbours of the local player's instance whenever it changes: walking into
## the next instance makes the old one a neighbour. Called every frame; tests call it after
## changing the state.
func show_state() -> void:
	var state: GameState = driver.state if driver != null else null
	if state == _state:
		return
	_state = state
	for old: HexGrid in grids.values():
		remove_child(old)
		old.queue_free()
	grids.clear()
	_placed.clear()
	if state == null:
		return
	if driver.world != _world:
		_world = driver.world
		_regions.clear()
	var current: String = _name_of(state)
	for target: String in state.region.exit_blueprints:
		if not grids.has(target):
			grids[target] = _grid_for(target, current)


## Every tile of every neighbour, in the local instance's coordinates: where the cloud has to reach.
func placed_tiles() -> Array[Vector2i]:
	show_state()
	return _placed


## A grid drawing the instance `target` where it lies next to `current`.
func _grid_for(target: String, current: String) -> HexGrid:
	if not _regions.has(target):
		_regions[target] = InstanceBlueprints.region_of(target, _world.seed_for(target))
	var shift: Vector2i = _world.offset(target) - _world.offset(current)
	var neighbour: HexGrid = HexGrid.new()
	neighbour.fixed_region = _regions[target]
	neighbour.name = target
	neighbour.position = HexLayout.to_world(shift)
	add_child(neighbour)
	for tile: Vector2i in _regions[target].sorted_tiles():
		_placed.append(tile + shift)
	return neighbour


## The blueprint name the world keeps `state` under.
func _name_of(state: GameState) -> String:
	for instance_name: String in _world.instances:
		if _world.instances[instance_name] == state:
			return instance_name
	return ""
