class_name TypeEffectivenessFeature
extends Feature
## Type effectiveness (#626, the chart decided on #68): a strike's damage follows the type chart.
## A strike has its own type, whatever fits it, apart from its monster's (owner on #626): each
## species' auto attack and special name theirs in its data. Against each of the struck monster's
## types, the strike's family is strong or weak (STRONG; a family is weak against itself):
## strong is ×1.5 from a Lesser strike and ×2 from a Greater one, weak is ×0.5 against a Greater
## type and ×0.75 against a Lesser one, and a dual-typed monster's two multiply, with no cap.
## It doesn't step: the features whose strikes land on a monster (a companion's auto attack and
## special on a wild monster, a wild monster's strike on a companion) scale their damage through
## `scaled`. Switched off, every strike deals its plain damage. Either way a strike that lands
## deals at least 1 (owner, #702): `scaled` is the last step of every strike's damage.

const STRONG_FROM_LESSER: int = 1500
const STRONG_FROM_GREATER: int = 2000
const WEAK_AGAINST_LESSER: int = 750
const WEAK_AGAINST_GREATER: int = 500
## Whether a strike of each family (row) is strong against each family (column), in
## TypeChart.FAMILIES' order; weak otherwise.
const STRONG: Array[Array] = [
	[false, true, true, false, false],
	[false, false, true, false, true],
	[false, false, false, true, true],
	[true, true, false, false, false],
	[true, false, false, true, false],
]

## Each species' types, its auto attack's type and its special's type, by species id, from the
## content data (the species slice reads them).
var types: Dictionary[String, PackedStringArray] = {}
var auto_types: Dictionary[String, String] = {}
var special_types: Dictionary[String, String] = {}


func _init(
	species_types: Dictionary[String, PackedStringArray] = {},
	auto_strike_types: Dictionary[String, String] = {},
	special_strike_types: Dictionary[String, String] = {},
) -> void:
	types = species_types
	auto_types = auto_strike_types
	special_types = special_strike_types


func id() -> int:
	return Features.TYPE_EFFECTIVENESS


## The damage of a strike of `damage` by a monster of `attacker_species`, its special or its auto
## attack, on one of `defender_species`, in `state`'s instance: after the chart while the instance
## has type effectiveness on, the plain damage otherwise. Rounds down (Fixed), but never below 1.
static func scaled(
	state: GameState,
	damage: int,
	attacker_species: String,
	special: bool,
	defender_species: String,
) -> int:
	var chart: TypeEffectivenessFeature = (
		state.feature(Features.TYPE_EFFECTIVENESS) as TypeEffectivenessFeature
	)
	if chart == null or not chart.enabled:
		return maxi(damage, 1)
	var strike_types: Dictionary[String, String] = (
		chart.special_types if special else chart.auto_types
	)
	var strike_type: String = strike_types.get(attacker_species, "")
	return maxi(Fixed.scale(damage, chart.factor(strike_type, defender_species)), 1)


## How hard a strike of `strike_type` hits a monster of `defender_species`, in thousandths (Fixed):
## each of its types multiplies in. A strike or a type off the chart counts as ×1.
func factor(strike_type: String, defender_species: String) -> int:
	var total: int = Fixed.ONE
	var family: int = TypeChart.family_of(strike_type)
	if family < 0:
		return total
	var greater_strike: bool = _is_greater(strike_type, family)
	var defender_types: PackedStringArray = types.get(defender_species, PackedStringArray())
	for defender_type: String in defender_types:
		var against: int = TypeChart.family_of(defender_type)
		if against < 0:
			continue
		var each: int = WEAK_AGAINST_LESSER
		if STRONG[family][against]:
			each = STRONG_FROM_GREATER if greater_strike else STRONG_FROM_LESSER
		elif _is_greater(defender_type, against):
			each = WEAK_AGAINST_GREATER
		total = Fixed.scale(total, each)
	return total


## Whether `type`, of the family `family`, is its Greater type rather than its Lesser one.
static func _is_greater(type: String, family: int) -> bool:
	return TypeChart.FAMILIES[family][1] == type
