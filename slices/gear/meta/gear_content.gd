class_name GearContent
extends Content
## The gear's content data (#690), which the gear slice owns (#412): one JSONC file per piece
## directly in its data/ (its own kind, so no folder repeats the slice's name, #442), checked
## against gear.schema.json beside them in CI. Everything else reads the gear through this.

const DIR: String = "res://slices/gear/data/"

## Every piece of gear, by id.
var items: Dictionary[String, GearItem] = {}
## Every piece's id, by the code a command carries it by (SpikesFeature.code_of).
var _codes: Dictionary[int, String] = {}


## Every gear file in `directory`, read and checked: a piece's id must have a code a command can
## carry it by (SpikesFeature.code_of), none other's (#818).
static func load_gear(directory: String = DIR) -> GearContent:
	var content: GearContent = GearContent.new()
	content.read(directory)
	return content


## The gear, read once per session (ContentCatalog).
static func cached() -> GearContent:
	return ContentCatalog.kept(DIR, load_gear)


func add(file_id: String, text: String) -> String:
	var item: GearItem = GearItem.parse(file_id, text)
	if (item.problem.is_empty()
			and not CommandCodes.file(_codes, SpikesFeature.code_of(item.id), item.id)):
		item.problem = "its code is taken: give it another id"
	if item.problem.is_empty():
		items[item.id] = item
	return item.problem


## The item `item_id` in words, as the player reads it (#773): a piece of gear by its name, its text
## tags showing the names they stand for (#752), anything else (a material) by its id in words, as
## the Character tab shows them.
func name_of(item_id: String) -> String:
	var item: GearItem = items.get(item_id)
	return TextTags.shown(item.name) if item != null else item_id.capitalize()
