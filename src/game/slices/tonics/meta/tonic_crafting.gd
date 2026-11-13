class_name TonicCrafting
extends RefCounted
## Crafting a tonic's brew (#2090, at the base, #695): it spends the brew's exact cost from the
## player's profile, which then counts one more of it like a material. Like Crafting, it happens in
## the profile, outside the simulation, so it changes no replay, and nothing in it is rolled: the
## same choices always make the same brew. No brew wears out (#2039): drinking it uses it up
## (#2091).


## Makes one of the brew `brew_id` in `profile`, spending its cost; returns why it can't, or "", and
## changes nothing when it can't.
static func craft(profile: Profile, brew_id: String) -> String:
	var refusal: String = craft_problem(profile, brew_id)
	if not refusal.is_empty():
		return refusal
	var brew: TonicBrew = TonicContent.cached().brews[brew_id]
	for material: String in brew.cost:
		var _spent: String = profile.spend(material, brew.cost[material])
	profile.materials[brew_id] = profile.materials.get(brew_id, 0) + 1
	return ""


## Why `profile` can't make one of the brew `brew_id` now, or "": a tonic allows it, the player
## holds
## its whole cost, and the profile can hold one more.
static func craft_problem(profile: Profile, brew_id: String) -> String:
	var brew: TonicBrew = TonicContent.cached().brews.get(brew_id)
	if brew == null:
		return "no tonic brews %s" % brew_id
	for material: String in brew.cost:
		if profile.materials.get(material, 0) < brew.cost[material]:
			return "%s needs %d %s" % [brew_id, brew.cost[material], material]
	if profile.materials.get(brew_id, 0) >= Profile.MAX_NUMBER:
		return "the profile can't hold more %s" % brew_id
	return ""
