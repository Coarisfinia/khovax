class_name NeighbourDecorations
extends Node3D
## The decorations of the instances next door (#1043): for each neighbour NeighbourView draws, a
## TileDecorations of its own on that neighbour's region, placed like its grid, so its forests,
## rocks and stumps rise out of the fog with its ground, as the local instance's do (#945). The fog
## knows the neighbours' tiles shifted into the local instance's coordinates (NeighbourView.shifts).
## A tile changed in place next door swaps its decoration as the world hands the local instance the
## new ground (#538), as the neighbour's grid eases its color.

@export var neighbours: NeighbourView
## The fog the decorations rise out of; none shows every decoration.
@export var fog: FogView

## Each neighbour's decorations, by blueprint name.
var views: Dictionary[String, TileDecorations] = {}
## The grids the views were made for: another one (the neighbours drawn anew) makes them anew.
var _grids: Dictionary[String, HexGrid] = {}
## The version of the ground next door the views last showed (GameState.next_door_version).
var _next_door_version: int = 0


func _process(delta: float) -> void:
	show_state(delta)


## Matches the views to the neighbours drawn now and eases each one `delta` seconds towards the fog.
## Called every frame; tests call it with a long `delta` to let it settle.
func show_state(delta: float) -> void:
	if neighbours == null:
		return
	neighbours.show_state()
	if neighbours.grids != _grids:
		_build()
	var state: GameState = neighbours.driver.state if neighbours.driver != null else null
	if state != null and state.next_door_version != _next_door_version:
		_next_door_version = state.next_door_version
		for view: TileDecorations in views.values():
			view.show_changes()
	for view: TileDecorations in views.values():
		view.show_state(delta)


func _build() -> void:
	for old: TileDecorations in views.values():
		remove_child(old)
		old.queue_free()
	views.clear()
	_grids = neighbours.grids.duplicate()
	var state: GameState = neighbours.driver.state if neighbours.driver != null else null
	_next_door_version = state.next_door_version if state != null else 0
	for target: String in _grids:
		views[target] = _view_for(target)


## The decorations of the neighbour `target`, placed like its grid.
func _view_for(target: String) -> TileDecorations:
	var view: TileDecorations = TileDecorations.new()
	view.fixed_region = neighbours.region_of(target)
	view.shift = neighbours.shifts[target]
	view.fog = fog
	view.name = target
	view.position = _grids[target].position
	add_child(view)
	# Eased here, once a frame (show_state), not again by its own _process, which entering the tree
	# turned on.
	view.set_process(false)
	return view
