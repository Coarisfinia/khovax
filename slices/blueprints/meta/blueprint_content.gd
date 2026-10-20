class_name BlueprintContent
extends Content
## The instance blueprints' content data (#823), which the blueprints slice owns (#412): one JSONC
## file per blueprint directly in its data/ (its own kind, #442), checked against
## blueprints.schema.json beside them in CI, with the rule sets they name (RuleSetContent, #941)
## read first. Everything else reads the blueprints through InstanceBlueprints.

const DIR: String = "res://slices/blueprints/data/"

## Every blueprint, by id, in file name order.
var blueprints: Dictionary[String, Blueprint] = {}
## The rule sets the blueprints name, by id.
var rule_sets: Dictionary[String, RuleSet] = {}


## Every blueprint file in `directory`, read and checked against the rule sets in its rule_sets/.
static func load_blueprints(directory: String = DIR) -> BlueprintContent:
	var content: BlueprintContent = BlueprintContent.new()
	var sets: RuleSetContent = RuleSetContent.load_rule_sets(directory.path_join("rule_sets") + "/")
	if not sets.problem.is_empty():
		content.problem = "rule_sets/" + sets.problem
		return content
	content.rule_sets = sets.rule_sets
	content.read(directory)
	return content


## The blueprints, read once per session (ContentCatalog); blueprints that don't load are an error,
## and there are none then.
static func cached() -> BlueprintContent:
	return ContentCatalog.kept(DIR, _checked)


static func _checked() -> BlueprintContent:
	var content: BlueprintContent = load_blueprints()
	if not content.problem.is_empty():
		push_error("the instance blueprints don't load: " + content.problem)
		content.blueprints.clear()
	return content


func add(file_id: String, text: String) -> String:
	var blueprint: Blueprint = Blueprint.parse(file_id, text, rule_sets)
	if blueprint.problem.is_empty():
		blueprints[blueprint.id] = blueprint
	return blueprint.problem
