class_name TrailView
extends Node
## The trail feature's look: paints the allies' shared trail (#87) on the grid's trail layer. It
## reads the trail feature's state and never writes it; an instance without the trail paints
## nothing. A sealing ring's fill shows over it (SealFillView, #851).

@export var driver: Session
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
	var feature: TrailFeature = driver.state.feature(TrailFeature.ID) as TrailFeature
	if feature != null:
		for tile: Vector2i in feature.shared.tiles:
			colors[tile] = trail_color
	grid.paint(HexGrid.PaintLayer.TRAIL, colors)
