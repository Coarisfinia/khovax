class_name TileContent
extends Content
## The tile blueprints (#116), which the core's TileKinds needs, so they live in the core (#506):
## one JSONC file per tile kind in core/data/tiles/, checked against its schema in
## core/data/schemas/ in CI.

const DIR: String = "res://core/data/tiles/"

## Every tile blueprint, by id.
var tiles: Dictionary[String, TileBlueprint] = {}


## Every tile blueprint file in `directory`, read and checked.
static func load_tiles(directory: String = DIR) -> TileContent:
	var content: TileContent = TileContent.new()
	content.read(directory)
	return content


## The tile blueprints, read once per session (ContentCatalog); blueprints that don't load are an
## error, reported once (#940).
static func cached() -> TileContent:
	return ContentCatalog.kept(DIR, _checked)


static func _checked() -> TileContent:
	var content: TileContent = load_tiles()
	if not content.problem.is_empty():
		push_error("the tile blueprints didn't load: " + content.problem)
	return content


func add(file_id: String, text: String) -> String:
	var tile: TileBlueprint = TileBlueprint.parse(file_id, text)
	if tile.problem.is_empty():
		tiles[tile.id] = tile
	return tile.problem
