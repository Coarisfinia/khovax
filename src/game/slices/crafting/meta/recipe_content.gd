class_name RecipeContent
extends Content
## The crafting recipes' content data (#1349), which the crafting slice owns (#412): one JSONC file
## per recipe in its data/recipes/, named after the material it makes, checked against
## recipes.schema.json beside them in CI. What it makes and needs are materials (MaterialContent).

const DIR: String = "res://slices/crafting/data/recipes/"
## Its schema, which says the fields a recipe file may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/crafting/data/recipes.schema.json"

## Every recipe, by the id of the material it makes.
var recipes: Dictionary[String, Recipe] = {}


## Every recipe file in `directory`, read and checked.
static func load_recipes(directory: String = DIR) -> RecipeContent:
	var content: RecipeContent = RecipeContent.new()
	content.read(directory)
	return content


## The recipes, read once per session (ContentCatalog).
static func cached() -> RecipeContent:
	return ContentCatalog.kept(DIR, load_recipes)


func add(file_id: String, text: String) -> String:
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		return Content.NOT_AN_OBJECT
	var data: Dictionary = parsed
	var recipe: Recipe = Recipe.new()
	recipe.id = Content.text_of(data.get("id"))
	var why: String = Content.unknown_field(data, SchemaFields.at(SCHEMA))
	if why.is_empty():
		why = Content.id_problem(recipe.id, file_id)
	if why.is_empty():
		why = recipe.read_needs(data.get("needs"))
	if why.is_empty():
		why = _materials_problem(recipe)
	if why.is_empty():
		recipes[recipe.id] = recipe
	return why


## Why `recipe` makes or needs something that's no material (MaterialContent), or "".
static func _materials_problem(recipe: Recipe) -> String:
	var known: Array[String] = MaterialContent.cached().ids
	for material: String in [recipe.id] + recipe.needs.keys():
		if not known.has(material):
			return "it makes or needs %s, which is no material" % material
	return ""
