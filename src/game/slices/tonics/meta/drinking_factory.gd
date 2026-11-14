class_name DrinkingFactory
extends RefCounted
## Builds an instance's drinking feature (#2310, #823) with what each brew does, by the code of its
## id, from the tonics' content data: who it helps, a Mend's share, or the effect over time it gives
## (#2311). Tonics that don't load are an error, and so is a brew whose code another brew filed
## first: that one keeps the code, and the later one is left out, so drinking it is refused.


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


## What drinking `brew` does: who it helps, and what it mends or which effect over time it gives,
## at its potency for its seconds. A Slow-release brew does nothing yet: its wait is #2312.
static func _dose_of(brew: TonicBrew) -> TonicDose:
	var dose: TonicDose = TonicDose.new(brew.target == "player")
	if brew.delay_seconds > 0:
		return dose
	if brew.effect == TonicBrew.INSTANT:
		dose.mend = brew.potency
	elif TonicEffectsFeature.KINDS.has(brew.effect):
		dose.effect = brew.effect
		dose.strength = brew.potency
		dose.ticks = brew.seconds * Simulation.TICKS_PER_SECOND
	else:
		push_error("brew %s has an effect no rule knows: %s" % [brew.id, brew.effect])
	return dose
