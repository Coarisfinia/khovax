class_name Ability
extends RefCounted
## Something a species brings (#222), read from content data (data/abilities/, #72): a special
## attack the player triggers (#221), a passive that helps the player while the companion is
## active (e.g. stronger warding, #223), or a passive that helps the companion itself. Each species
## names one of each; what they do comes with the systems that use them. A special attack is one
## species' own (owner, #228): no two species share one.

const SPECIAL: String = "special"
const PLAYER_PASSIVE: String = "player_passive"
const SELF_PASSIVE: String = "self_passive"
const KINDS: Array[String] = [SPECIAL, PLAYER_PASSIVE, SELF_PASSIVE]
## An ability file's fields, as its schema (data/schemas/abilities.schema.json) allows them.
const FIELDS: Array[String] = ["id", "kind", "name", "description"]

var id: String = ""
var kind: String = ""
## What the player reads: its name and what it does.
var name: String = ""
var description: String = ""
## Why the ability couldn't be read, or "" when it could.
var problem: String = ""


## An ability read from an ability file's text, named `file_id`; its `problem` says what's wrong.
static func parse(file_id: String, text: String) -> Ability:
	var ability: Ability = Ability.new()
	var json: JSON = JSON.new()
	if json.parse(Jsonc.strip(text)) != OK or not json.data is Dictionary:
		ability.problem = "not a JSON object"
		return ability
	var data: Dictionary = json.data
	ability.id = Content.text_of(data.get("id"))
	ability.kind = Content.text_of(data.get("kind"))
	ability.name = Content.text_of(data.get("name"))
	ability.description = Content.text_of(data.get("description"))
	ability.problem = Content.unknown_field(data, FIELDS)
	if ability.problem.is_empty() and (ability.id != file_id or not Content.is_id(ability.id)):
		ability.problem = "its id must match the file name and be lowercase words with underscores"
	if ability.problem.is_empty() and not KINDS.has(ability.kind):
		ability.problem = "its kind is one of %s" % [KINDS]
	if ability.problem.is_empty() and (ability.name.is_empty() or ability.description.is_empty()):
		ability.problem = "it has a name and a description"
	return ability
