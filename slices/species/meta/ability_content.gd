class_name AbilityContent
extends Content
## The abilities' content data (#222), which the species slice owns (#412): one JSONC file per
## ability in its data/abilities/, checked against its schema in data/ in CI. Everything else reads
## them through this.

const DIR: String = "res://slices/species/data/abilities/"

## Every ability, by id.
var abilities: Dictionary[String, Ability] = {}


## Every ability file in `directory`, read and checked.
static func load_abilities(directory: String = DIR) -> AbilityContent:
	var content: AbilityContent = AbilityContent.new()
	content.read(directory)
	return content


func add(file_id: String, text: String) -> String:
	var ability: Ability = Ability.parse(file_id, text)
	if ability.problem.is_empty():
		abilities[ability.id] = ability
	return ability.problem
