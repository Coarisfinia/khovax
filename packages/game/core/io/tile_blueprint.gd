class_name TileBlueprint
extends RefCounted
## A kind of tile a region is made of (#116), read from content data (core/data/tiles/, #72,
## #506): its ground color and decoration for the view, and its traits for the rules. A region's
## legend places it by its id, named after its file (#802); the rules see only its id and traits
## (TileKinds).

## Its schema, which says the fields a tile blueprint file and its traits may have (SchemaFields,
## #825).
const SCHEMA: String = "res://core/data/schemas/tiles.schema.json"
## What can harvest a tile (#696): bare hands, the only way so far (gear, #697, and a species'
## skill, #698, come later).
const HANDS: String = "hands"
const TAKES: Array[String] = [HANDS]
## The largest clearance (hundredths of a tile's radius) and reach (rings) a blueprint may give, so
## a typo can't make one tile overshadow the region.
const MAX_HEIGHT: int = PieceLooks.MAX_HEIGHT
const MAX_REACH: int = 3
## A model's scale as the pack made it, in hundredths (#588: whole numbers, like the clearance).
const FULL_SCALE: int = 100
## The largest a model may be scaled up, so a typo can't cover the region in one decoration.
const MAX_SCALE: int = 4 * FULL_SCALE

var id: String = ""
## The tile's ground color as a whole number, 0xRRGGBB, read from its #rrggbb text (#515: no
## float-backed Color in the core); the look turns it into a Color (TileLooks.color_of).
var color: int = 0
## What tells the kind apart without its color (#68): one printable ASCII character, so every font
## has it, unique among the kinds (the content flow checks), drawn on the Survey.
var symbol: String = ""
## The decoration drawn on every tile of this kind, a model id in the resource packs (#1864), or
## "" for none.
var model: String = ""
## How much larger than the pack made it the model is drawn, in hundredths (150 is 1.5 times),
## for a model too small to read; the look turns it into a factor where it draws.
var scale: int = FULL_SCALE
## How many rings around its tile its decoration's crown covers, and how much height the crown
## leaves free beneath it, in hundredths of a tile's radius: every tile under the crown must fit
## (#232). How tall a tile is gets measured from its objects' models (TileLooks.height_of).
var reach: int = 0
var clearance: int = 0
## Whether walkers can stand on it.
var walkable: bool = false
## Whether a wild monster standing on it hides there until a player comes next to it (#202).
var hides: bool = false
## Whether it's grass a grazing wild monster eats, and water a drinking one drinks from (#1203).
var grazable: bool = false
var drinkable: bool = false
## What harvesting it drops, as a tile table's id (#696), or "" when it can't be harvested; the kind
## it turns into then, and what can harvest it (TAKES).
var harvest_yields: String = ""
var harvest_becomes: String = ""
var harvest_takes: String = ""
## Why the blueprint couldn't be read, or "" when it could.
var problem: String = ""


## A blueprint read from a tile blueprint file's text, named `file_id`; its `problem` says what's
## wrong.
static func parse(file_id: String, text: String) -> TileBlueprint:
	var blueprint: TileBlueprint = TileBlueprint.new()
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		blueprint.problem = Content.NOT_AN_OBJECT
		return blueprint
	var data: Dictionary = parsed
	var raw_traits: Variant = data.get("traits")
	var traits: Dictionary = raw_traits if raw_traits is Dictionary else {}
	var walks: Variant = traits.get("walkable")
	var hiding: Variant = traits.get("hides", false)
	var grass: Variant = traits.get("grazable", false)
	var water: Variant = traits.get("drinkable", false)
	blueprint.id = Content.text_of(data.get("id"))
	blueprint.model = Content.text_of(data.get("model"))
	blueprint.symbol = Content.text_of(data.get("symbol"))
	blueprint.reach = _whole(data.get("reach", 0), MAX_REACH)
	blueprint.clearance = _whole(data.get("clearance", 0), MAX_HEIGHT)
	blueprint.walkable = walks is bool and walks
	blueprint.hides = hiding is bool and hiding
	blueprint.grazable = grass is bool and grass
	blueprint.drinkable = water is bool and water
	blueprint.problem = (
		Content.unknown_field(data, SchemaFields.at(SCHEMA))
		+ Content.unknown_field(traits, SchemaFields.at(SCHEMA, "/properties/traits"))
	)
	if blueprint.problem.is_empty():
		blueprint.problem = blueprint._check(file_id, data, walks)
	if blueprint.problem.is_empty():
		blueprint.problem = blueprint._size_problem()
	if blueprint.problem.is_empty() and not hiding is bool:
		blueprint.problem = "its hides trait is true or false"
	if blueprint.problem.is_empty() and not (grass is bool and water is bool):
		blueprint.problem = "its grazable and drinkable traits are true or false"
	if blueprint.problem.is_empty() and data.has("harvest"):
		blueprint.problem = blueprint._read_harvest(data.get("harvest"))
	return blueprint


## Reads what harvesting it gives and leaves (#696) from its `harvest` field; returns what's wrong,
## or "".
func _read_harvest(raw: Variant) -> String:
	var harvest: Dictionary = raw if raw is Dictionary else {}
	var unknown: String = Content.unknown_field(
		harvest,
		SchemaFields.at(SCHEMA, "/properties/harvest"),
	)
	if not unknown.is_empty():
		return unknown
	harvest_yields = Content.text_of(harvest.get("yields"))
	harvest_becomes = Content.text_of(harvest.get("becomes"))
	harvest_takes = Content.text_of(harvest.get("takes"))
	var ids: bool = Content.is_id(harvest_yields) and Content.is_id(harvest_becomes)
	if not ids or harvest_becomes == id or not TAKES.has(harvest_takes):
		return "its harvest names a table it yields, another kind it becomes and one of %s" % [
			TAKES,
		]
	return ""


## Why the read fields are wrong, or "", and the color read from `data` when they aren't.
func _check(file_id: String, data: Dictionary, walks: Variant) -> String:
	var wrong_id: String = Content.id_problem(id, file_id)
	if not wrong_id.is_empty():
		return wrong_id
	var html: String = Content.text_of(data.get("color"))
	if RegEx.create_from_string("^#[0-9a-f]{6}$").search(html) == null:
		return "its color is #rrggbb"
	if RegEx.create_from_string("^[!-~]$").search(symbol) == null:
		return "its symbol is one printable ASCII character"
	if not walks is bool:
		return "its traits say whether it's walkable"
	scale = _whole(data.get("scale", FULL_SCALE), MAX_SCALE)
	if scale < 1:
		return "its scale is a whole number of hundredths from 1 to %d" % MAX_SCALE
	color = html.substr(1).hex_to_int()
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


## A JSON number that is a whole number from 0 to `most`, or -1 for anything else.
static func _whole(value: Variant, most: int) -> int:
	return JsonNumbers.whole(value, 0, most, -1)
