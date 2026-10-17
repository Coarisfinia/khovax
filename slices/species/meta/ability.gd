class_name Ability
extends RefCounted
## Something a species brings (#222), read from content data (the species slice's data/abilities/,
## #72, #412): a special
## attack the player triggers (#221), a passive that helps the player while the companion is
## active (e.g. stronger warding, #223), or a passive that helps the companion itself. Each species
## names one of each; what they do comes with the systems that use them. A special attack is one
## species' own (owner, #228): no two species share one. A special has a power and a cooldown
## (SpecialAttackFeature, #410); a passive has neither.

const SPECIAL: String = "special"
const PLAYER_PASSIVE: String = "player_passive"
const SELF_PASSIVE: String = "self_passive"
const KINDS: Array[String] = [SPECIAL, PLAYER_PASSIVE, SELF_PASSIVE]
## An ability file's fields, as its schema (slices/species/data/abilities.schema.json) allows them.
const FIELDS: Array[String] = [
	"id",
	"kind",
	"name",
	"description",
	"power",
	"cooldown_seconds",
]

var id: String = ""
var kind: String = ""
## What the player reads: its name and what it does.
var name: String = ""
var description: String = ""
## A special's: how much of its species' strength one strike deals, in thousandths (Fixed), and the
## seconds before it can fire again; 0 for a passive.
var power: int = 0
var cooldown_seconds: int = 0
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
	ability.power = Content.amount(data.get("power"))
	ability.cooldown_seconds = Content.amount(data.get("cooldown_seconds"))
	ability.problem = Content.unknown_field(data, FIELDS)
	if ability.problem.is_empty() and (ability.id != file_id or not Content.is_id(ability.id)):
		ability.problem = "its id must match the file name and be lowercase words with underscores"
	if ability.problem.is_empty() and not KINDS.has(ability.kind):
		ability.problem = "its kind is one of %s" % [KINDS]
	if ability.problem.is_empty() and (ability.name.is_empty() or ability.description.is_empty()):
		ability.problem = "it has a name and a description"
	if ability.problem.is_empty():
		ability.problem = ability._strike_problem(data)
	return ability


## Why its power and cooldown don't fit its kind, or "": a special has both, a passive neither.
func _strike_problem(data: Dictionary) -> String:
	if kind == SPECIAL and (power < 1 or cooldown_seconds < 1):
		return "a special has a power and a cooldown, whole numbers from 1"
	if kind != SPECIAL and (data.has("power") or data.has("cooldown_seconds")):
		return "a special has a power and a cooldown, a passive neither"
	return ""
