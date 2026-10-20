class_name RuleSetContent
extends Content
## The rule sets' content data (#941), which the blueprints slice owns (#412): one JSONC file per
## rule set in its data/rule_sets/, checked against its schema in data/ in CI. BlueprintContent
## reads them before the blueprints that name them.

const DIR: String = "res://slices/blueprints/data/rule_sets/"

## Every rule set, by id.
var rule_sets: Dictionary[String, RuleSet] = {}


## Every rule set file in `directory`, read and checked.
static func load_rule_sets(directory: String = DIR) -> RuleSetContent:
	var content: RuleSetContent = RuleSetContent.new()
	content.read(directory)
	return content


## The rule sets, read once per session (ContentCatalog).
static func cached() -> RuleSetContent:
	return ContentCatalog.kept(DIR, load_rule_sets)


func add(file_id: String, text: String) -> String:
	var rule_set: RuleSet = RuleSet.parse(file_id, text)
	if rule_set.problem.is_empty():
		rule_sets[rule_set.id] = rule_set
	return rule_set.problem
