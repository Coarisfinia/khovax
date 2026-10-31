class_name MaterialContent
extends Content
## The materials' content data (#774), which the loot slice owns (#412): one JSONC file per
## material, checked against materials.schema.json in CI. They're the resource packs' (#1953): the
## ones the packs list, so a player's pack can add or replace one; the default pack's lie in the
## slice's data/materials/. A material is an item a table gives that isn't a piece of gear
## (GearContent); every item a table names is one of the two, which the content flow checks.

## The materials' key in the content cache (ContentCatalog).
const KEY: String = "materials"
## Its schema, which says the fields a material file may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/loot/data/materials.schema.json"

## Every material's id, in file name order.
var ids: Array[String] = []
## Every material's player-facing name (#1657), by id, as its file gives it, untranslated.
var names: Dictionary[String, String] = {}


## Every material the resource packs list (ResourcePacks.materials), read and checked.
static func load_materials() -> MaterialContent:
	return load_files(ResourcePacks.materials())


## Every material in `files` (each res:// path by its id), read and checked: a file that's missing
## or broken is the problem.
static func load_files(files: Dictionary[String, String]) -> MaterialContent:
	var content: MaterialContent = MaterialContent.new()
	content.read_files(files)
	return content


## The materials, read once per session (ContentCatalog).
static func cached() -> MaterialContent:
	return ContentCatalog.kept(KEY, load_materials)


func add(file_id: String, text: String) -> String:
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		return Content.NOT_AN_OBJECT
	var data: Dictionary = parsed
	var id: String = Content.text_of(data.get("id"))
	var name: String = Content.text_of(data.get("name"))
	var why: String = Content.unknown_field(data, SchemaFields.at(SCHEMA))
	if why.is_empty():
		why = Content.id_problem(id, file_id)
	if why.is_empty() and name.strip_edges().is_empty():
		why = "it needs a name"
	if (why.is_empty()
			and data.has("model")
			and not ResourcePacks.has_model(Content.text_of(data["model"]))):
		why = "its model is no model a resource pack has (#1579, #1864)"
	if why.is_empty():
		ids.append(id)
		names[id] = name
	return why


## The material `id`'s name as the player reads it, translated (its schema marks it, so the
## translation template has it), or "Unknown material" for one the data lacks, such as one a save
## kept after its file went.
func name_of(id: String) -> String:
	if not names.has(id):
		return TranslationServer.tr("Unknown material")
	return TranslationServer.tr(names[id])
