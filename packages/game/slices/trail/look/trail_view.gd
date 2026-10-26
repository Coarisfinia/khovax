class_name TrailView
extends Node
## The trail feature's look: paints the allies' shared trail (#87) on the grid's trail layer. It
## reads the trail feature's state and never writes it; an instance without the trail paints
## nothing. Another view paints the sealing rings' fill over it, on a higher layer (#851).

@export var driver: Session
@export var grid: HexGrid
@export var trail_color: Color = Color(0.86, 0.74, 0.36):
	set(value):
		trail_color = value
		_shown_region = null
		if is_node_ready():
			show_state()

## The trail last painted and the region the grid showed then: the trail grows for as long as the
## players walk, so it's painted again only when it or the grid changed, never every frame (#1311).
var _shown: Dictionary[Vector2i, int] = {}
var _shown_region: Region = null


func _process(_delta: float) -> void:
	show_state()


## Paints the current trail, if it changed. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null or grid == null:
		return
	var feature: TrailFeature = driver.state.feature(TrailFeature.ID) as TrailFeature
	var tiles: Dictionary[Vector2i, int] = feature.shared.tiles if feature != null else {}
	if grid.shown_region() == _shown_region and tiles == _shown:
		return
	_shown = tiles.duplicate()
	_shown_region = grid.shown_region()
	var colors: Dictionary[Vector2i, Color] = {}
	for tile: Vector2i in tiles:
		colors[tile] = trail_color
	grid.paint(HexGrid.PaintLayer.TRAIL, colors)
