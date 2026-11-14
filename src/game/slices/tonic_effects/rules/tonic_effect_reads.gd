class_name TonicEffectReads
extends RefCounted
## What the tonics' effects over time (#2311, TonicEffectsFeature) do to the rules that read them,
## for those rules: a Ward's guard, a Quicken's share off the wait and a Fortify's scaled strikes.
## Kept apart from the feature, so a rule that reads them reads only the effects, not what the
## feature itself reads.


## The strength, in thousandths, of the effect `kind` on `target_id` in `state` now; 0 when it has
## another, none, one that hasn't started, or the instance has no tonic effects working.
static func strength_of(state: GameState, target_id: int, kind: String) -> int:
	var effects: TonicEffectsFeature = state.feature(TonicEffectsFeature.ID) as TonicEffectsFeature
	if effects == null or not effects.enabled:
		return 0
	var effect: TonicEffect = effects.effect_of(target_id)
	if effect == null or effect.waits > 0 or effect.kind != kind:
		return 0
	return effect.strength


## The damage `damage` of a strike by the companion `companion_id`, scaled once by its Fortify.
static func fortified(state: GameState, companion_id: int, damage: int) -> int:
	var fortify: int = strength_of(state, companion_id, TonicEffectsFeature.FORTIFY)
	return damage if fortify == 0 else Fixed.scale(damage, Fixed.ONE + fortify)
