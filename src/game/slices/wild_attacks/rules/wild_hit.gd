class_name WildHit
extends RefCounted
## How a wild monster's hit lands on a companion or a player (#2458): less the guards of the
## passives working for them and of the Ward they drank, raised as WildMonsterStruck, and off their
## HP. Both its auto attack (WildAttackFeature) and a boss's special (BossSpecialFeature, #2410)
## land this way, each with the passives' guards it was built with, so neither needs the other.


## Lands the hit `struck` on the companion (`on_companion`) or the player it names: less their
## guards (`guarded`), raised, and off their HP (HealthFeature.hurt, #455); a hit that fells them
## ends the effect they drank (#2343). `guards` is each passive's guard (Ability.guard), in
## thousandths, by its id.
static func land(
		state: GameState,
		struck: WildMonsterStruck,
		on_companion: bool,
		guards: Dictionary[String, int],
) -> void:
	struck.damage = guarded(state, struck.target_id, on_companion, struck.damage, guards)
	state.events.append(struck)
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	if health.hurt(state, struck.target_id, struck.damage):
		_end_drunk(state, struck.target_id)


## `damage` on the companion or player `target_id`, less the `guards` of the passives working for
## them now (#616): a companion's own, or the player's companion's while it's out, its web's
## included (#1472), and of the Ward they drank (#2311). All of them together take off less than a
## whole hit, and a hit that deals anything deals at least 1 (#702).
static func guarded(
		state: GameState,
		target_id: int,
		on_companion: bool,
		damage: int,
		guards: Dictionary[String, int],
) -> int:
	if damage == 0:
		return damage
	var guard: int = TonicEffectReads.strength_of(state, target_id, TonicEffectsFeature.WARD)
	if guards.is_empty() and guard == 0:
		return damage
	for passive: String in passives(state, target_id, on_companion):
		guard += guards.get(passive, 0)
	guard = mini(guard, Fixed.ONE - 1)
	return maxi(Fixed.scale(damage, Fixed.ONE - guard), 1)


## The passives working now (CompanionPassives) for the companion or player `target_id`: a
## companion's own, or the player's companion's while it's out; none without companions.
static func passives(state: GameState, target_id: int, on_companion: bool) -> Array[String]:
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var found: Array[String] = []
	if companions == null:
		return found
	if on_companion:
		return CompanionPassives.of_companion(state, companions, target_id)
	return CompanionPassives.of_player(state, companions, state.entity(target_id).slot)


## Ends the effect `target_id`, whom a hit just felled, drank (#2343), where the instance has them.
static func _end_drunk(state: GameState, target_id: int) -> void:
	var effects: TonicEffectsFeature = state.feature(TonicEffectsFeature.ID) as TonicEffectsFeature
	if effects != null:
		effects.end(state, target_id)
