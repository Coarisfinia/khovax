class_name TonicDrinking
extends RefCounted
## Drinking a tonic or a draught (#2310) from the player's profile: it spends one of the brew and
## posts the request that drinks it to the profile's outbox (#818, OutboxEntry.DRINK) in one change,
## which the simulation carries out (DrinkingFeature). Like a revive item (ReviveTie.offered), a
## drink is refused before anything is spent when it would do nothing: none left, a drink already on
## its way, the player still waiting, no target that can use it, or a Mend for a target at full HP.


## Drinks one of the brew `brew_id` from `profile` for the player in `slot` of `state`; returns why
## it can't, or "", and changes nothing when it can't.
static func drink(profile: Profile, state: GameState, slot: int, brew_id: String) -> String:
	var refusal: String = problem(profile, state, slot, brew_id)
	if not refusal.is_empty():
		return refusal
	var _spent: String = profile.spend(brew_id)
	var _posted: OutboxEntry = profile.outbox.post(
		OutboxEntry.DRINK,
		DrinkingFeature.code_of(brew_id),
	)
	return ""


## Why the player in `slot` of `state` can't drink the brew `brew_id` from `profile` now, or "".
static func problem(profile: Profile, state: GameState, slot: int, brew_id: String) -> String:
	var brew: TonicBrew = TonicContent.cached().brews.get(brew_id)
	if brew == null:
		return "no tonic brews %s" % brew_id
	if profile.materials.get(brew_id, 0) <= 0:
		return "no %s left" % brew_id
	for request: OutboxEntry in profile.outbox.entries:
		if request.kind == OutboxEntry.DRINK:
			return "a drink is already on its way"
	var drinking: DrinkingFeature = state.feature(DrinkingFeature.ID) as DrinkingFeature
	if drinking == null or not drinking.enabled:
		return "nothing is drunk here"
	var dose: TonicDose = drinking.doses.get(DrinkingFeature.code_of(brew_id))
	if dose == null:
		return "%s does nothing here" % brew_id
	return drinking.problem(state, slot, dose)
