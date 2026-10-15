class_name TileBlueprint
extends RefCounted
## A kind of tile a region is made of (#116), read from content data (data/tiles/, #72): its ground
## color and decoration for the view, and its traits for the rules. A region's legend places it by
## its id; TileKinds numbers the kinds for the simulation.

## A tile blueprint file's fields, as its schema (data/schemas/tiles.schema.json) allows them.
const FIELDS: Array[String] = ["id", "color", "model", "traits"]
const TRAITS: Array[String] = ["walkable"]

var id: String = ""
## The tile's ground color.
var color: Color = Color.BLACK
## The decoration drawn on every tile of this kind, a res:// path, or "" for none.
var model: String = ""
## Whether walkers can stand on it.
var walkable: bool = false
## Why the blueprint couldn't be read, or "" when it could.
var problem: String = ""


## A blueprint read from a tile blueprint file's text, named `file_id`; its `problem` says what's
## wrong.
static func parse(file_id: String, text: String) -> TileBlueprint:
	var blueprint: TileBlueprint = TileBlueprint.new()
	var json: JSON = JSON.new()
	if json.parse(Jsonc.strip(text)) != OK or not json.data is Dictionary:
		blueprint.problem = "not a JSON object"
		return blueprint
	var data: Dictionary = json.data
	var raw_traits: Variant = data.get("traits")
	var traits: Dictionary = raw_traits if raw_traits is Dictionary else {}
	var walks: Variant = traits.get("walkable")
	blueprint.id = Content.text_of(data.get("id"))
	blueprint.model = Content.text_of(data.get("model"))
	blueprint.walkable = walks is bool and walks
	blueprint.problem = Content.unknown_field(data, FIELDS) + Content.unknown_field(traits, TRAITS)
	if blueprint.problem.is_empty():
		blueprint.problem = blueprint._check(file_id, data, walks)
	return blueprint


## Why the read fields are wrong, or "", and the color read from `data` when they aren't.
func _check(file_id: String, data: Dictionary, walks: Variant) -> String:
	if id != file_id or not Content.is_id(id):
		return "its id must match the file name and be lowercase words with underscores"
	var html: String = Content.text_of(data.get("color"))
	if RegEx.create_from_string("^#[0-9a-f]{6}$").search(html) == null:
		return "its color is #rrggbb"
	if not walks is bool:
		return "its traits say whether it's walkable"
	if data.has("model") and not ResourceLoader.exists(model):
		return "its model %s doesn't exist" % model
	color = Color.html(html)
	return ""
