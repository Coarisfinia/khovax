class_name DrinkingFactory
extends RefCounted
## Builds an instance's drinking feature (#2310, #823) with what each brew does, by the code of its
## id, from the tonics' content data: who it helps, and a Mend's share. Tonics that don't load, or
## two brews sharing a code, are an error, and those brews do nothing then.


static func build(_setup: FeatureSetup) -> DrinkingFeature:
	var content: TonicContent = TonicContent.cached()
	if not content.problem.is_empty():
		push_error("the tonics don't load: " + content.problem)
	var by_code: Dictionary = {}
	var doses: Dictionary[int, TonicDose] = {}
	for brew: TonicBrew in content.brews.values():
		var code: int = DrinkingFeature.code_of(brew.id)
		if not CommandCodes.file(by_code, code, brew.id):
			push_error("brew %s shares its code with another" % brew.id)
			continue
		doses[code] = _dose_of(brew)
	return DrinkingFeature.new(doses)


## What drinking `brew` does: who it helps and what it mends.
static func _dose_of(brew: TonicBrew) -> TonicDose:
	return TonicDose.new(brew.target == "player", _mend_of(brew))


## The share of its target's full HP `brew` heals at once: a Mend's potency, unless it waits
## (Slow-release, #2312); 0 for every other brew.
static func _mend_of(brew: TonicBrew) -> int:
	if brew.effect != TonicBrew.INSTANT or brew.delay_seconds > 0:
		return 0
	return brew.potency
