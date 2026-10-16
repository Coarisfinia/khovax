class_name TileLooks
extends RefCounted
## Each tile kind's look (#116), by its number in Region.terrain: its tile blueprint, with the
## ground color and decoration model the views draw. Read from the content data once. The
## simulation keeps only a kind's id and traits (TileKinds); the look is the view's alone.

## How tall a tile's decoration stands, in hundredths of a tile's radius (#232).
const HEIGHT_UNITS: float = 100.0 / HexLayout.SIZE

## Every tile blueprint, by number; empty until first used.
static var _by_number: Dictionary[int, TileBlueprint] = {}
## Each kind's measured height, by number, once measured.
static var _heights: Dictionary[int, int] = {}


## The tile blueprint of kind `kind`, or null for a number no kind has.
static func of(kind: int) -> TileBlueprint:
	if _by_number.is_empty():
		var content: Content = Content.load_tiles()
		if not content.problem.is_empty():
			push_error("the tile blueprints didn't load: " + content.problem)
		for tile: TileBlueprint in content.tiles.values():
			_by_number[tile.number] = tile
	return _by_number.get(kind)


## How tall a tile of kind `kind` stands (#232): the top of its decoration's model, as drawn (its
## scale included), in hundredths of a tile's radius; 0 for a kind without one. Measured from the
## model, so it never drifts from what's drawn.
static func height_of(kind: int) -> int:
	if not _heights.has(kind):
		_heights[kind] = _measured(of(kind))
	return _heights[kind]


static func _measured(blueprint: TileBlueprint) -> int:
	if blueprint == null or blueprint.model.is_empty():
		return 0
	var model: Node3D = (load(blueprint.model) as PackedScene).instantiate() as Node3D
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	var top: float = 0.0
	for mesh: MeshInstance3D in meshes:
		var box: AABB = _in_model(model, mesh) * mesh.get_aabb()
		top = maxf(top, box.end.y)
	model.free()
	return ceili(top * blueprint.scale * HEIGHT_UNITS)


## `node`'s transform within `model`, every parent's on the way included: imported models nest.
static func _in_model(model: Node3D, node: Node3D) -> Transform3D:
	var placed: Transform3D = Transform3D.IDENTITY
	var step: Node = node
	while step != null and step != model:
		if step is Node3D:
			placed = (step as Node3D).transform * placed
		step = step.get_parent()
	return placed
