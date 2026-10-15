class_name TileBlueprint
extends RefCounted
## A kind of tile a region is made of (#116), read from content data (data/tiles/, #72): its ground
## color and decoration for the view, and its traits for the rules. A region's legend places it by
## its id. Its number is permanent (TileKinds); the rules see only its id, number and traits.

## A tile blueprint file's fields, as its schema (data/schemas/tiles.schema.json) allows them.
const FIELDS: Array[String] = ["id", "number", "color", "model", "traits"]
const TRAITS: Array[String] = ["walkable"]
## The largest number a kind may have, so a typo can't make the kind list huge.
const MAX_NUMBER: int = 255

var id: String = ""
## The kind's permanent number in Region.terrain, never reused or changed once shipped; -1 when
## the file doesn't give a valid one.
var number: int = -1
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
	blueprint.number = _number(data.get("number"))
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
	if number < 0 or number > MAX_NUMBER:
		return "its number is a whole number from 0 to %d" % MAX_NUMBER
	if not walks is bool:
		return "its traits say whether it's walkable"
	color = Color.html(html)
	return ""


## A JSON number that is a whole kind number from 0 to MAX_NUMBER, or -1 for anything else.
static func _number(value: Variant) -> int:
	if not (value is int or value is float):
		return -1
	var given: float = value
	if given != floorf(given) or given < 0.0 or given > MAX_NUMBER:
		return -1
	var whole: int = type_convert(value, TYPE_INT)
	return whole
