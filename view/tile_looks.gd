class_name TileLooks
extends RefCounted
## Each tile kind's look (#116), by its number in Region.terrain: its tile blueprint, with the
## ground color and decoration model the views draw. Read from the content data once. The
## simulation keeps only a kind's id and traits (TileKinds); the look is the view's alone.

## Every tile blueprint, by number; empty until first used.
static var _by_number: Dictionary[int, TileBlueprint] = {}


## The tile blueprint of kind `kind`, or null for a number no kind has.
static func of(kind: int) -> TileBlueprint:
	if _by_number.is_empty():
		var content: Content = Content.load_tiles()
		if not content.problem.is_empty():
			push_error("the tile blueprints didn't load: " + content.problem)
		for tile: TileBlueprint in content.tiles.values():
			_by_number[tile.number] = tile
	return _by_number.get(kind)
