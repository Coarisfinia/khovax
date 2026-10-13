class_name TrailView
extends Node
## The trail feature's look: paints every trail's tiles on the grid. It reads the trail feature's
## state and never writes it; an instance without the trail paints nothing.

@export var driver: GameDriver
@export var grid: HexGrid
@export var trail_color: Color = Color(0.86, 0.74, 0.36):
	set(value):
		trail_color = value
		if is_node_ready():
			show_state()


func _process(_delta: float) -> void:
	show_state()


## Paints the current trail. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null or grid == null:
		return
	var colors: Dictionary[Vector2i, Color] = {}
	var feature: TrailFeature = driver.state.feature(Features.TRAIL) as TrailFeature
	if feature != null:
		for trail: Trail in feature.trails.values():
			for tile: Vector2i in trail.tiles:
				colors[tile] = trail_color
	grid.paint(colors)
