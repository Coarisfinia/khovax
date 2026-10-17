class_name TileBlueprint
extends RefCounted
## A kind of tile a region is made of (#116), read from content data (the tiles slice's data/,
## #72, #412): its ground
## color and decoration for the view, and its traits for the rules. A region's legend places it by
## its id. Its number is permanent (TileKinds); the rules see only its id, number and traits.

## A tile blueprint file's fields, as its schema (slices/tiles/data/tiles.schema.json) allows them.
const FIELDS: Array[String] = [
	"id",
	"number",
	"color",
	"symbol",
	"model",
	"scale",
	"reach",
	"clearance",
	"traits",
]
const TRAITS: Array[String] = ["walkable", "hides"]
## The largest number a kind may have, so a typo can't make the kind list huge.
const MAX_NUMBER: int = 255
## The largest clearance (hundredths of a tile's radius) and reach (rings) a blueprint may give, so
## a typo can't make one tile overshadow the region.
const MAX_HEIGHT: int = RegionFormat.MAX_HEIGHT
const MAX_REACH: int = 3
## The largest a model may be scaled up, so a typo can't cover the region in one decoration.
const MAX_SCALE: float = 4.0

var id: String = ""
## The kind's permanent number in Region.terrain, never reused or changed once shipped; -1 when
## the file doesn't give a valid one.
var number: int = -1
## The tile's ground color.
var color: Color = Color.BLACK
## What tells the kind apart without its color (#68): one printable ASCII character, so every font
## has it, unique among the kinds (the content flow checks), drawn on the Survey.
var symbol: String = ""
## The decoration drawn on every tile of this kind, a res:// path, or "" for none.
var model: String = ""
## How much larger than the pack made it the model is drawn, for a model too small to read.
var scale: float = 1.0
## How many rings around its tile its decoration's crown covers, and how much height the crown
## leaves free beneath it, in hundredths of a tile's radius: every tile under the crown must fit
## (#232). How tall a tile is gets measured from its objects' models (TileLooks.height_of).
var reach: int = 0
var clearance: int = 0
## Whether walkers can stand on it.
var walkable: bool = false
## Whether a wild monster standing on it hides there until a player comes next to it (#202).
var hides: bool = false
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
	var hiding: Variant = traits.get("hides", false)
	blueprint.id = Content.text_of(data.get("id"))
	blueprint.model = Content.text_of(data.get("model"))
	blueprint.symbol = Content.text_of(data.get("symbol"))
	blueprint.number = _number(data.get("number"))
	blueprint.reach = _whole(data.get("reach", 0), MAX_REACH)
	blueprint.clearance = _whole(data.get("clearance", 0), MAX_HEIGHT)
	blueprint.walkable = walks is bool and walks
	blueprint.hides = hiding is bool and hiding
	blueprint.problem = Content.unknown_field(data, FIELDS) + Content.unknown_field(traits, TRAITS)
	if blueprint.problem.is_empty():
		blueprint.problem = blueprint._check(file_id, data, walks)
	if blueprint.problem.is_empty():
		blueprint.problem = blueprint._size_problem()
	if blueprint.problem.is_empty() and not hiding is bool:
		blueprint.problem = "its hides trait is true or false"
	return blueprint


## Why the read fields are wrong, or "", and the color read from `data` when they aren't.
func _check(file_id: String, data: Dictionary, walks: Variant) -> String:
	if id != file_id or not Content.is_id(id):
		return "its id must match the file name and be lowercase words with underscores"
	var html: String = Content.text_of(data.get("color"))
	if RegEx.create_from_string("^#[0-9a-f]{6}$").search(html) == null:
		return "its color is #rrggbb"
	if RegEx.create_from_string("^[!-~]$").search(symbol) == null:
		return "its symbol is one printable ASCII character"
	if number < 0 or number > MAX_NUMBER:
		return "its number is a whole number from 0 to %d" % MAX_NUMBER
	if not walks is bool:
		return "its traits say whether it's walkable"
	var given_scale: Variant = data.get("scale", 1.0)
	var drawn: float = 0.0
	if given_scale is int or given_scale is float:
		drawn = given_scale
	if drawn <= 0.0 or drawn > MAX_SCALE:
		return "its scale is a number above 0, at most %s" % MAX_SCALE
	scale = drawn
	color = Color.html(html)
	return ""


## Why the reach or clearance read isn't a whole number in its range (each is -1 then), or ""
## (#232).
func _size_problem() -> String:
	if reach < 0 or clearance < 0:
		return "its reach (up to %d) and clearance (up to %d) are whole numbers" % [
			MAX_REACH,
			MAX_HEIGHT,
		]
	return ""


## A JSON number that is a whole kind number from 0 to MAX_NUMBER, or -1 for anything else.
static func _number(value: Variant) -> int:
	return _whole(value, MAX_NUMBER)


## A JSON number that is a whole number from 0 to `most`, or -1 for anything else.
static func _whole(value: Variant, most: int) -> int:
	if not (value is int or value is float):
		return -1
	var given: float = value
	if given != floorf(given) or given < 0.0 or given > most:
		return -1
	var whole: int = type_convert(value, TYPE_INT)
	return whole
