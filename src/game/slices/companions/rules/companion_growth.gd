class_name CompanionGrowth
extends RefCounted
## What a companion's leaning does in the world (#1358): the stat nodes its player took for it on
## its development web raise or lower its HP, its strength and its speed by their shares of its
## species' (CompanionLeaning). Its speed is how often it strikes, so its wait between two strikes
## shrinks as its speed rises. The special nodes it took make its special's power stronger by
## their share (#1453, SpecialAttackFeature). Its leaning comes from its player's profile, with its
## party (`leaning_of`). Everything rounds down through Fixed, so it composes with what scales a hit
## later (the type chart, the host's difficulty on the wild monster it strikes, HostSettings).


## The leaning of the companion `companion_id` of `companions` in `state`, from its player's party
## (CompanionParty.leaning_of): none for one without a player.
static func leaning_of(
	state: GameState,
	companions: CompanionFeature,
	companion_id: int,
) -> CompanionLeaning:
	if not companions.owners.has(companion_id):
		return CompanionLeaning.new()
	var short_id: String = companions.short_id_of(companion_id)
	return CompanionParty.leaning_of(state, companions.owners[companion_id], short_id)


## The share of its species' stat a companion has whose leaning shifts it by `shift`, in
## thousandths: Fixed.ONE for none.
static func share(shift: int) -> int:
	return Fixed.ONE + shift


## A stat (HP, strength) of `value` for its species, shifted by `shift`; at least 1, and at most
## Fixed.MAX_AMOUNT: a leaning raises a species' stat beyond its own, and what scales it next (a
## special's
## power, a hit) refuses an amount beyond that.
static func stat(value: int, shift: int) -> int:
	return clampi(Fixed.scale(value, share(shift)), 1, Fixed.MAX_AMOUNT)


## The wait `wait` between two strikes, for a companion whose speed is shifted by `shift`: shorter
## as its speed rises, longer as it falls, never below one tick.
static func ticks(wait: int, shift: int) -> int:
	return maxi(Fixed.mul_div(wait, Fixed.ONE, share(shift)), 1)
