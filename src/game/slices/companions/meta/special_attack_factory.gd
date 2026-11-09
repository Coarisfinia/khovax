class_name SpecialAttackFactory
extends RefCounted
## Builds an instance's specials feature (#410, #823) with every species' special's power, cooldown
## and hold (#1163), from the ability data; a species whose special doesn't load has none.


static func build(_setup: FeatureSetup) -> SpecialAttackFeature:
	var powers: Dictionary[String, int] = {}
	var cooldowns: Dictionary[String, int] = {}
	var channels: Dictionary[String, int] = {}
	var specials: Dictionary[String, Ability] = SpeciesContent.cached().specials()
	for species_id: String in specials:
		powers[species_id] = specials[species_id].power
		cooldowns[species_id] = specials[species_id].cooldown_seconds * Simulation.TICKS_PER_SECOND
		if specials[species_id].channel_seconds > 0:
			channels[species_id] = (
				specials[species_id].channel_seconds * Simulation.TICKS_PER_SECOND
			)
	return SpecialAttackFeature.new(powers, cooldowns, channels)
