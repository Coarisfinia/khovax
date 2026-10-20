class_name BlueprintContent
extends RefCounted
## The instance blueprints' content data (#823), which the blueprints slice owns (#412): one JSONC
## file per blueprint directly in its data/ (its own kind, #442), checked against
## blueprints.schema.json beside them in CI. Everything else reads the blueprints through
## InstanceBlueprints.

const DIR: String = "res://slices/blueprints/data/"

## Every blueprint, by id, in file name order.
var blueprints: Dictionary[String, Blueprint] = {}
## Why the data couldn't be read, or "" when it could.
var problem: String = ""


## Every blueprint file in `directory`, read and checked.
static func load_blueprints(directory: String = DIR) -> BlueprintContent:
	var content: BlueprintContent = BlueprintContent.new()
	var texts: Dictionary[String, String] = Content.texts_in(directory)
	for file_id: String in texts:
		var blueprint: Blueprint = Blueprint.parse(file_id, texts[file_id])
		if not blueprint.problem.is_empty():
			content.problem = file_id + ".jsonc: " + blueprint.problem
			return content
		content.blueprints[blueprint.id] = blueprint
	return content
