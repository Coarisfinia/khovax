class_name SealFillView
extends Node
## A sealing ring's fill (#219), on the grid's seal layer, over the trail (#851): the ring's wall
## tiles turn to the seal color one after another, going round the ring, so how far the seal has
## come shows as how much of the ring is filled, not only as a color (#68). A ring that breaks or
## holds is no longer sealing, so the fill clears. It reads the domination feature's state and never
## writes it; an instance without domination paints nothing.

@export var driver: Session
@export var grid: HexGrid
@export var seal_color: Color = Color(0.36, 0.62, 0.86)


func _process(_delta: float) -> void:
	show_state()


## Paints the sealing rings' fill. Called every frame; tests call it after stepping.
func show_state() -> void:
	if driver == null or driver.state == null or grid == null:
		return
	var colors: Dictionary[Vector2i, Color] = {}
	var domination: DominationFeature = (
		driver.state.feature(DominationFeature.ID) as DominationFeature
	)
	if domination != null:
		for seal: RingSeal in domination.seals.values():
			for tile: Vector2i in sealed_tiles(seal):
				colors[tile] = seal_color
	grid.paint(HexGrid.PaintLayer.SEALS, colors)


## The sealing ring's wall tiles its progress has filled so far, going round the ring from its
## westmost side.
static func sealed_tiles(seal: RingSeal) -> Array[Vector2i]:
	var middle: Vector3 = Vector3.ZERO
	for tile: Vector2i in seal.walls:
		middle += HexLayout.to_world(tile) / seal.walls.size()
	var around: Array[Vector2i] = seal.walls.duplicate()
	around.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return _angle(a, middle) < _angle(b, middle)
	)
	var filled: int = floori(seal.walls.size() * seal.progress() / float(Fixed.ONE))
	return around.slice(0, filled)


## The tile's angle around `middle`, seen from above.
static func _angle(tile: Vector2i, middle: Vector3) -> float:
	var offset: Vector3 = HexLayout.to_world(tile) - middle
	return atan2(offset.z, -offset.x)
