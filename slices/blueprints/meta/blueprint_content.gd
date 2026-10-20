class_name BlueprintContent
extends Content
## The instance blueprints' content data (#823), which the blueprints slice owns (#412): one JSONC
## file per blueprint directly in its data/ (its own kind, #442), checked against
## blueprints.schema.json beside them in CI. Everything else reads the blueprints through
## InstanceBlueprints.

const DIR: String = "res://slices/blueprints/data/"

## Every blueprint, by id, in file name order.
var blueprints: Dictionary[String, Blueprint] = {}


## Every blueprint file in `directory`, read and checked.
static func load_blueprints(directory: String = DIR) -> BlueprintContent:
	var content: BlueprintContent = BlueprintContent.new()
	content.read(directory)
	return content


func add(file_id: String, text: String) -> String:
	var blueprint: Blueprint = Blueprint.parse(file_id, text)
	if blueprint.problem.is_empty():
		blueprints[blueprint.id] = blueprint
	return blueprint.problem
