class_name MaterialContent
extends Content
## The materials' content data (#774), which the loot slice owns (#412): one JSONC file per
## material in its data/materials/, checked against materials.schema.json beside them in CI. A
## material is an item a table gives that isn't a piece of gear (GearContent); every item a table
## names is one of the two, which the content flow checks.

const DIR: String = "res://slices/loot/data/materials/"
## Its schema, which says the fields a material file may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/loot/data/materials.schema.json"

## Every material's id, in file name order.
var ids: Array[String] = []


## Every material file in `directory`, read and checked.
static func load_materials(directory: String = DIR) -> MaterialContent:
	var content: MaterialContent = MaterialContent.new()
	content.read(directory)
	return content


## The materials, read once per session (ContentCatalog).
static func cached() -> MaterialContent:
	return ContentCatalog.kept(DIR, load_materials)


func add(file_id: String, text: String) -> String:
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		return Content.NOT_AN_OBJECT
	var data: Dictionary = parsed
	var id: String = Content.text_of(data.get("id"))
	var why: String = Content.unknown_field(data, SchemaFields.at(SCHEMA))
	if why.is_empty():
		why = Content.id_problem(id, file_id)
	if why.is_empty():
		ids.append(id)
	return why
