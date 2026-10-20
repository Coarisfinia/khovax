class_name GearContent
extends RefCounted
## The gear's content data (#690), which the gear slice owns (#412): one JSONC file per piece
## directly in its data/ (its own kind, so no folder repeats the slice's name, #442), checked
## against gear.schema.json beside them in CI. Everything else reads the gear through this.

const DIR: String = "res://slices/gear/data/"

## Every piece of gear, by id.
var items: Dictionary[String, GearItem] = {}
## Why the data couldn't be read, or "" when it could.
var problem: String = ""


## Every gear file in `directory`, read and checked.
static func load_gear(directory: String = DIR) -> GearContent:
	var content: GearContent = GearContent.new()
	var texts: Dictionary[String, String] = Content.texts_in(directory)
	for file_id: String in texts:
		var item: GearItem = GearItem.parse(file_id, texts[file_id])
		if not item.problem.is_empty():
			content.problem = file_id + ".jsonc: " + item.problem
			return content
		content.items[item.id] = item
	return content


## The item `item_id` in words, as the player reads it (#773): a piece of gear by its name, its text
## tags showing the names they stand for (#752), anything else (a material) by its id in words, as
## the Character tab shows them.
func name_of(item_id: String) -> String:
	var item: GearItem = items.get(item_id)
	return TextTags.shown(item.name) if item != null else item_id.capitalize()
