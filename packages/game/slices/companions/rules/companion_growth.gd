class_name CompanionGrowth
extends RefCounted
## What a companion's level does in the world (#1255): every level above 1 raises its HP, its
## strength and its speed by GROWTH_PER_LEVEL of its species'. Its speed is how often it strikes,
## so its wait between two strikes shrinks by the same share. Its level comes from its player's
## profile, with its party (`level_of`). Everything rounds down through Fixed, so it
## composes with what scales a hit later (the type chart, the host's difficulty on the wild monster
## it strikes, HostSettings).

## How much each level above 1 adds, in thousandths. Its number is in Tuning.
const GROWTH_PER_LEVEL: int = Tuning.COMPANION_GROWTH_PER_LEVEL


## The level of the companion `companion_id` of `companions` in `state`, from its player's party
## (CompanionParty.level_of): 1 for none.
static func level_of(state: GameState, companions: CompanionFeature, companion_id: int) -> int:
	if not companions.owners.has(companion_id):
		return 1
	var short_id: String = companions.short_id_of(companion_id)
	return CompanionParty.level_of(state, companions.owners[companion_id], short_id)


## The share of its species' stats a companion of `level` has, in thousandths: Fixed.ONE at level 1.
static func share(level: int) -> int:
	return Fixed.ONE + (maxi(level, 1) - 1) * GROWTH_PER_LEVEL


## A stat (HP, strength) of `value` for its species, at `level`.
static func stat(value: int, level: int) -> int:
	return Fixed.scale(value, share(level))


## The wait `wait` between two strikes at level 1, at `level`: shorter by its speed, never below
## one tick.
static func ticks(wait: int, level: int) -> int:
	return maxi(Fixed.mul_div(wait, Fixed.ONE, share(level)), 1)
