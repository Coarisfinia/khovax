class_name NeighbourView
extends Node3D
## The instances next door (#188, seamless world #155): every instance an exit of the local
## player's instance leads to is drawn at its place in the world (`World.offset`), as a HexGrid of
## its own, so the ground goes on past the exits. Only the directly connected ones (owner's rule).
## Under FogCloud, their ground lies under thick cloud, or light fog where this machine's player
## explored it before (FogView keeps that per instance, #190).
##
## A loaded neighbour is drawn from its own region, so a tile a rule changed there in place shows
## next door too, easing into its new kind as the world hands the local instance the new ground
## (#538). One not loaded is read with `InstanceBlueprints.region_of`, the world's seed for it and
## its variant there (#529), never by loading the instance: the world's hash covers every loaded
## instance, so loading one from a view would change the simulation.

@export var driver: Session

## Each neighbour's grid, by blueprint name, placed relative to the local instance.
var grids: Dictionary[String, HexGrid] = {}
## How far each neighbour's tiles are shifted into the local instance's coordinates, by name.
var shifts: Dictionary[String, Vector2i] = {}
## The instance the neighbours were found for.
var _state: GameState
## Every neighbour tile in the local instance's coordinates.
var _placed: Array[Vector2i] = []
## Each blueprint's region for the world shown, read once per generation (#212) and variant (#529):
## a purged instance comes back arranged anew, and a flag can choose another variant of one not
## loaded. A loaded one's is its instance's own (`_region_now`).
var _regions: Dictionary[String, Region] = {}
## The generation and variant each region in `_regions` was read for, by name, and whether it is
## the loaded instance's own.
var _read_for: Dictionary[String, String] = {}
var _world: World
## The version of the ground next door the grids last showed (GameState.next_door_version).
var _next_door_version: int = 0


func _process(_delta: float) -> void:
	show_state()


## Finds and draws the neighbours of the local player's instance whenever it changes: walking into
## the next instance makes the old one a neighbour, and whenever a neighbour was purged. When the
## world hands the instance new ground next door, each grid eases its changed tiles instead. Called
## every frame; tests call it after changing the state.
func show_state() -> void:
	var state: GameState = driver.state if driver != null else null
	if state == _state and not _rearranged():
		if state != null and state.next_door_version != _next_door_version:
			_next_door_version = state.next_door_version
			for grid: HexGrid in grids.values():
				grid.show_changes()
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
	_next_door_version = state.next_door_version
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


## The region of the neighbour `target` drawn now, as it was read for its grid, or null: for the
## Survey (#353), which shows the neighbours' explored ground without loading them either.
func region_of(target: String) -> Region:
	show_state()
	if not grids.has(target):
		return null
	return _regions[target]


## Whether a neighbour drawn now has been purged since (#212), has another variant (#529) or was
## loaded or dropped (#538): it is drawn again, from its region now.
func _rearranged() -> bool:
	for target: String in grids:
		if _read_for[target] != _version(target):
			return true
	return false


## The generation and variant the neighbour `target` has in the world now, and whether it's loaded.
func _version(target: String) -> String:
	var loaded: bool = _world.instances.has(target)
	return "%d %s %s" % [_world.generation(target), WorldFlags.variant_of(_world, target), loaded]


## A grid drawing the instance `target` where it lies next to `current`.
func _grid_for(target: String, current: String) -> HexGrid:
	if not _regions.has(target) or _read_for[target] != _version(target):
		_regions[target] = _region_now(target)
		_read_for[target] = _version(target)
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


## The region of the neighbour `target`: the loaded instance's own, with its tiles changed in place
## (#530), or else arranged from its blueprint as it would load.
func _region_now(target: String) -> Region:
	if _world.instances.has(target):
		return _world.instances[target].region
	var variant: String = WorldFlags.variant_of(_world, target)
	return InstanceBlueprints.region_of(target, _world.seed_for(target), variant)


## The blueprint name `world` keeps `state` under, or "".
static func name_of(world: World, state: GameState) -> String:
	for instance_name: String in world.instances:
		if world.instances[instance_name] == state:
			return instance_name
	return ""
