class_name TonicDrinks
extends RefCounted
## What the tonic flows (#2310, #2312, #2343) share about drinking a brew from a profile.


## Why drinking `brew` from `profile` for player 0 in `state`, which `what` names, wasn't refused,
## or spent or posted something; "" when it was refused and changed nothing.
static func refused(profile: Profile, state: GameState, brew: String, what: String) -> String:
	var held: Dictionary[String, int] = {}
	held.assign(profile.materials)
	var refusal: String = TonicDrinking.drink(profile, state, 0, brew)
	if refusal.is_empty() or profile.materials != held or not profile.outbox.entries.is_empty():
		return "%s wasn't refused before anything was spent: %s" % [what, refusal]
	return ""
