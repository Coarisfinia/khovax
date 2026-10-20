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
## `scaled`. Switched off, every strike deals its plain damage (at least 1). Either way a strike
## that lands deals at least 1 (owner, #702): `scaled` is the last step of every strike's damage.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "type_effectiveness"
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


func id() -> String:
	return ID


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
	var chart: TypeEffectivenessFeature = _chart_on(state)
	if chart == null:
		return maxi(damage, 1)
	var strike_type: String = chart._strike_type(attacker_species, special)
	return maxi(Fixed.scale(damage, chart.factor(strike_type, defender_species)), 1)


## Whether a strike by a monster of `attacker_species`, its special or its auto attack, is strong
## against each type on the chart of one of `defender_species` (weak otherwise), in `state`'s
## instance, for the hit's look (#701): none while the instance has type effectiveness off.
static func strong_against(
	state: GameState,
	attacker_species: String,
	special: bool,
	defender_species: String,
) -> Array[bool]:
	var chart: TypeEffectivenessFeature = _chart_on(state)
	if chart == null:
		var none: Array[bool] = []
		return none
	return chart.strong_types(chart._strike_type(attacker_species, special), defender_species)


## Whether a strike of `strike_type` is strong against each of `defender_species`' types on the
## chart, in their order; weak otherwise. A strike off the chart is neither against any.
func strong_types(strike_type: String, defender_species: String) -> Array[bool]:
	var strong: Array[bool] = []
	var family: int = TypeChart.family_of(strike_type)
	if family < 0:
		return strong
	for defender_type: String in types.get(defender_species, PackedStringArray()):
		var against: int = TypeChart.family_of(defender_type)
		if against >= 0:
			strong.append(STRONG[family][against])
	return strong


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


## The type chart in `state`'s instance while it's on there; null otherwise.
static func _chart_on(state: GameState) -> TypeEffectivenessFeature:
	var chart: TypeEffectivenessFeature = (
		state.feature(ID) as TypeEffectivenessFeature
	)
	return chart if chart != null and chart.enabled else null


## The type of the special or the auto attack of `attacker_species`; "" when it has none.
func _strike_type(attacker_species: String, special: bool) -> String:
	var strike_types: Dictionary[String, String] = special_types if special else auto_types
	return strike_types.get(attacker_species, "")
