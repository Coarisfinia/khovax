class_name CompanionFactory
extends RefCounted
## Builds an instance's companion feature (#338, #823) with every species' reach, from its stats,
## and its two passives (#616), and whom every passive helps, for the passives the webs grant
## (#1472).


static func build(_setup: FeatureSetup) -> CompanionFeature:
	var content: SpeciesContent = SpeciesContent.cached()
	var reaches: Dictionary[String, int] = {}
	var player_passives: Dictionary[String, String] = {}
	var self_passives: Dictionary[String, String] = {}
	for species_id: String in content.species:
		var stats: Species = content.species[species_id]
		reaches[species_id] = CompanionFeature.reach_of(stats.hp, stats.strength, stats.speed)
		player_passives[species_id] = stats.player_passive
		self_passives[species_id] = stats.self_passive
	var helps_player: Dictionary[String, bool] = {}
	for ability: Ability in AbilityContent.cached().abilities.values():
		if ability.kind != Ability.SPECIAL:
			helps_player[ability.id] = ability.kind == Ability.PLAYER_PASSIVE
	return CompanionFeature.new(reaches, player_passives, self_passives, helps_player)
