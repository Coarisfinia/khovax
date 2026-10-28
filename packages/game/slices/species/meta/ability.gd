class_name Ability
extends RefCounted
## Something a species brings (#222), read from content data (the species slice's data/abilities/,
## #72, #412): a special attack the player triggers (#221), a passive that helps the player while
## the companion is active (e.g. stronger warding, #223), or a passive that helps the companion
## itself. Each species names one of each; what they do comes with the systems that use them. A
## special attack is one species' own (owner, #228): no two species share one. A special has a power
## and a cooldown (SpecialAttackFeature, #410) and a strike type (TypeEffectivenessFeature, #626),
## and may be held for some seconds (#1163); a passive has none of them. A passive works only while
## its monster is out (#616, CompanionFeature): a passive may guard (`guard`), one that helps its
## monster itself may hasten it when hurt (`hurt_haste`) or heal it at rest (`rest_heal`, #1500),
## and a player passive may hush its player's steps (`hush`, #1563).

const SPECIAL: String = "special"
const PLAYER_PASSIVE: String = "player_passive"
const SELF_PASSIVE: String = "self_passive"
const KINDS: Array[String] = [SPECIAL, PLAYER_PASSIVE, SELF_PASSIVE]
## Its schema, which says the fields an ability file may have (SchemaFields, #825).
const SCHEMA: String = "res://slices/species/data/abilities.schema.json"

var id: String = ""
var kind: String = ""
## What the player reads: its name and what it does. Both may hold text tags (#733), so whatever
## shows one shows it through TextTags.shown (#752).
var name: String = ""
var description: String = ""
## A special's: how much of its species' strength one strike deals, in thousandths (Fixed), and the
## seconds before it can fire again; 0 for a passive.
var power: int = 0
var cooldown_seconds: int = 0
## A special's: the seconds it is held once it fires, an attack that lasts (#1163), which binds its
## target for as long (#1167, SpecialAttackFeature); 0 for one that strikes and is over, and for a
## passive.
var channel_seconds: int = 0
## A special's type, from the chart, whatever fits it (owner on #626); "" for a passive.
var strike_type: String = ""
## A passive's: the share of every hit it takes off, in thousandths (#616, WildAttackFeature): a
## self passive's off its own monster, a player passive's off its player, while its monster is out;
## 0 for none, and for a special.
var guard: int = 0
## A self passive's: how much shorter its monster's wait between strikes is at its last HP, in
## thousandths, less as it has more HP left (#1500, CompanionAttackFeature); 0 for none.
var hurt_haste: int = 0
## A self passive's: the share of its monster's full HP it gets back each second it rests, waiting
## for no strike, in thousandths (#1500, CompanionAttackFeature); 0 for none.
var rest_heal: int = 0
## A player passive's: the share of its player's steps next to a sleeping light sleeper that don't
## wake it, in thousandths (#1563, SleepFeature), while its monster is out; 0 for none, and for a
## special or a self passive.
var hush: int = 0
## Its path mark (#471): PathMark.NONE, HARMONY, SUPREMACY or BOTH.
var path: String = PathMark.NONE
## Why the ability couldn't be read, or "" when it could.
var problem: String = ""


## An ability read from an ability file's text, named `file_id`; its `problem` says what's wrong.
static func parse(file_id: String, text: String) -> Ability:
	var ability: Ability = Ability.new()
	var parsed: Variant = Content.object_of(text)
	if parsed == null:
		ability.problem = Content.NOT_AN_OBJECT
		return ability
	var data: Dictionary = parsed
	ability.id = Content.text_of(data.get("id"))
	ability.kind = Content.text_of(data.get("kind"))
	ability.name = Content.text_of(data.get("name"))
	ability.description = Content.text_of(data.get("description"))
	ability.power = Content.amount(data.get("power"))
	ability.cooldown_seconds = Content.amount(data.get("cooldown_seconds"))
	ability.channel_seconds = Content.amount(data.get("channel_seconds"))
	ability.strike_type = Content.text_of(data.get("strike_type"))
	ability.guard = Content.amount(data.get("guard"))
	ability.hurt_haste = Content.amount(data.get("hurt_haste"))
	ability.rest_heal = Content.amount(data.get("rest_heal"))
	ability.hush = Content.amount(data.get("hush"))
	ability.path = PathMark.read(data)
	ability.problem = Content.unknown_field(data, SchemaFields.at(SCHEMA))
	if ability.problem.is_empty():
		ability.problem = Content.id_problem(ability.id, file_id)
	if ability.problem.is_empty() and not KINDS.has(ability.kind):
		ability.problem = "its kind is one of %s" % [KINDS]
	if ability.problem.is_empty() and (ability.name.is_empty() or ability.description.is_empty()):
		ability.problem = "it has a name and a description"
	if ability.problem.is_empty() and ability.path.is_empty():
		ability.problem = PathMark.PROBLEM
	if ability.problem.is_empty():
		ability.problem = ability._strike_problem(data)
	return ability


## Why its power, cooldown, strike type, hold, guard, haste, heal and hush don't fit its kind, or
## "": a special has the first three and may be held, a passive has none and may guard, taking off
## less than a whole hit, a self passive may hasten or heal its monster by less than a whole, and a
## player passive may hush, sparing less than every step.
func _strike_problem(data: Dictionary) -> String:
	if kind == SPECIAL and (power < 1 or cooldown_seconds < 1):
		return "a special has a power and a cooldown, whole numbers from 1"
	if kind == SPECIAL and TypeChart.family_of(strike_type) < 0:
		return "a special has a strike type on the chart"
	if kind == SPECIAL and data.has("channel_seconds") and channel_seconds < 1:
		return "a special's hold is a whole number of seconds from 1"
	for field: String in ["power", "cooldown_seconds", "strike_type", "channel_seconds"]:
		if kind != SPECIAL and data.has(field):
			return "a special has a power, a cooldown and a strike type, a passive none"
	if data.has("guard") and (kind == SPECIAL or guard < 1 or guard >= Fixed.ONE):
		return "a passive's guard is whole thousandths from 1 to 999, a special has none"
	for field: String in ["hurt_haste", "rest_heal"]:
		var share: int = Content.amount(data.get(field))
		if data.has(field) and (kind != SELF_PASSIVE or share < 1 or share >= Fixed.ONE):
			return "a self passive's %s is thousandths from 1 to 999, others have none" % field
	if data.has("hush") and (kind != PLAYER_PASSIVE or hush < 1 or hush >= Fixed.ONE):
		return "a player passive's hush is whole thousandths from 1 to 999, no other ability's"
	return ""
