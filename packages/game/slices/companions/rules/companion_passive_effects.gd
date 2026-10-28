class_name CompanionPassiveEffects
extends RefCounted
## What a companion's passives do to its own fighting (#1500), while their monster is out
## (CompanionPassives), for CompanionAttackFeature: one that hastens it when hurt shortens its wait
## between strikes by its share times the share of its HP it has lost (Kazri-tazri), and one that
## heals it at rest gives it its share of its full HP back at the start of each second it rests,
## waiting for no strike (Lombu-bombu). It reads the HP from the health feature, which the
## companions' attacks declare; kept apart from them so the features that only call their static
## helpers (the specials) don't read it.


## The resting companion `companion_id` gets the share of its full HP its passives heal at rest
## (`rest_heals`, by passive id) back, at least 1 HP, at the start of each second.
static func rest(
	state: GameState,
	companions: CompanionFeature,
	companion_id: int,
	rest_heals: Dictionary[String, int],
) -> void:
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	if health == null or rest_heals.is_empty() or state.tick % Simulation.TICKS_PER_SECOND != 0:
		return
	var heal: int = _share(state, companions, companion_id, rest_heals)
	if heal > 0:
		# At least 1 HP, so a small share of a low HP still heals.
		var amount: int = maxi(Fixed.scale(health.max_hp_of(state, companion_id), heal), 1)
		health.heal(state, companion_id, amount)


## The wait `wait` of the companion `companion_id`, shortened by its passives' haste when hurt
## (`hastes`, by passive id) times the share of its HP it has lost; never below one tick.
static func hastened(
	state: GameState,
	companions: CompanionFeature,
	companion_id: int,
	wait: int,
	hastes: Dictionary[String, int],
) -> int:
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	if health == null or hastes.is_empty():
		return wait
	var haste: int = _share(state, companions, companion_id, hastes)
	var full: int = health.max_hp_of(state, companion_id)
	var lost: int = clampi(full - health.hp_of(state, companion_id), 0, full)
	# Multiplied out first and divided once, so only the whole result rounds down.
	var whole: int = Fixed.ONE * full
	return maxi(Fixed.div_floor(wait * (whole - haste * lost), whole), 1)


## The shares `by_passive` gives the passives working for the companion `companion_id` in `state`
## now (CompanionPassives: its species' own and its web's), together: less than a whole.
static func _share(
	state: GameState,
	companions: CompanionFeature,
	companion_id: int,
	by_passive: Dictionary[String, int],
) -> int:
	var total: int = 0
	for passive: String in CompanionPassives.of_companion(state, companions, companion_id):
		total += by_passive.get(passive, 0)
	return mini(total, Fixed.ONE - 1)
