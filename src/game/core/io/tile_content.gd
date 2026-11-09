class_name TileContent
extends Content
## The tile blueprints (#116), which the core's TileKinds needs: one JSONC file per tile kind,
## checked against its schema in core/data/schemas/ in CI. They're the resource packs' (#1901),
## which list each kind's file by its id, but the core never names a slice: game/ hands it the
## packs' list once at start (`read_from`), from an autoload, so the tests and tools get it too, and
## before any background read (ContentFill) asks for it.

## The tile blueprints' key in the content cache (ContentCatalog).
const KEY: String = "tiles"

## The tile blueprints' files (each res:// path by its kind's id), handed in at start, and whether
## they were: a copy, read-only from then on, so a background read never races the hand-in.
static var _files: Dictionary[String, String] = {}
static var _handed: bool = false

## Every tile blueprint, by id.
var tiles: Dictionary[String, TileBlueprint] = {}


## Hands in the tile blueprints' files, each res:// path by its kind's id: the resource packs' list
## (ResourcePacks.tiles), handed in by game/ before anything reads a tile.
static func read_from(files: Dictionary[String, String]) -> void:
	_files = files.duplicate()
	_handed = true


## Every tile blueprint the handed-in list names, read and checked; with none handed in, a problem.
static func load_tiles() -> TileContent:
	if not _handed:
		var content: TileContent = TileContent.new()
		content.problem = "no resource pack's tile blueprints were handed in (read_from)"
		return content
	return load_files(_files)


## Every tile blueprint in `files` (each res:// path by its kind's id), read and checked: a file
## that's missing or broken is the problem.
static func load_files(files: Dictionary[String, String]) -> TileContent:
	var content: TileContent = TileContent.new()
	content.read_files(files)
	return content


## The tile blueprints, read once per session (ContentCatalog); blueprints that don't load are an
## error, reported once (#940).
static func cached() -> TileContent:
	return ContentCatalog.kept(KEY, _checked)


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
