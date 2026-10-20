class_name RuleSet
extends RefCounted
## A rule set's content data (#941), read from the blueprints slice's data/rule_sets/: a named list
## of rules that blueprints name (Blueprint.rules), so the rules most instances share are written
## once.

## Its schema, which says the fields a rule set file may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/blueprints/data/rule_sets.schema.json"

var id: String = ""
## The ids of the rules it holds (FeatureFactories), in the order written; they step in
## FeatureFactories' order.
var features: Array[String] = []
## Why the rule set couldn't be read, or "" when it could.
var problem: String = ""


## A rule set read from a rule set file's text, named `file_id`; its `problem` says what's wrong.
static func parse(file_id: String, text: String) -> RuleSet:
	var rule_set: RuleSet = RuleSet.new()
	var json: JSON = JSON.new()
	if json.parse(Jsonc.strip(text)) != OK or not json.data is Dictionary:
		rule_set.problem = "not a JSON object"
		return rule_set
	var data: Dictionary = json.data
	rule_set.id = Content.text_of(data.get("id"))
	rule_set.problem = Content.unknown_field(data, SchemaFields.at(SCHEMA))
	if rule_set.problem.is_empty() and (rule_set.id != file_id or not Content.is_id(rule_set.id)):
		rule_set.problem = "its id must match the file name and be lowercase words with underscores"
	var listed: bool = read_rules(data.get("features"), rule_set.features)
	if rule_set.problem.is_empty() and (not listed or rule_set.features.is_empty()):
		rule_set.problem = "its features must be one or more rules' feature ids, each once"
	return rule_set


## Whether `raw` lists rules' feature ids, each once and none already in `into`, none of which a
## region brings (RegionFeatures); appends them to `into`.
static func read_rules(raw: Variant, into: Array[String]) -> bool:
	if not raw is Array:
		return false
	var entries: Array = raw
	for entry: Variant in entries:
		var feature_id: String = Content.text_of(entry)
		var from_region: bool = RegionFeatures.implies(feature_id)
		if not FeatureFactories.has(feature_id) or from_region or into.has(feature_id):
			return false
		into.append(feature_id)
	return true
