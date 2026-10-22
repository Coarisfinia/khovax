class_name BlueprintSource
extends InstanceSource
## The instance blueprints (InstanceBlueprints) as what the World loads its instances from (#396).


func exists(instance_name: String) -> bool:
	return InstanceBlueprints.exists(instance_name)


## Whether everything an instance of this name loads from is read (InstanceContent, #816); what
## isn't is asked of the background fill (ContentFill), so it's read soon, and asking again finds
## it.
func cached(instance_name: String) -> bool:
	return ContentFill.have(InstanceContent.of(instance_name))


## The factions' territory as content data has it (Territory, #637), naming only instances that
## exist; factions that don't load are an error, and hold nothing then.
func starting_flags() -> Array[String]:
	var content: FactionContent = FactionContent.cached()
	if not content.problem.is_empty():
		push_error("the factions don't load: " + content.problem)
		return []
	var flags: Array[String] = Territory.starting_flags(content)
	for faction: Faction in content.factions.values():
		for instance_name: String in faction.territory:
			if not exists(instance_name):
				push_error("%s's territory %s doesn't exist" % [faction.id, instance_name])
				flags.erase(Territory.flag(instance_name, faction.id))
	return flags


func variant(instance_name: String, flags: Array[String]) -> String:
	return InstanceBlueprints.variant(instance_name, flags)


func create(
	instance_name: String,
	seed_value: int,
	players: int,
	variant_name: String,
) -> GameState:
	return InstanceBlueprints.create(instance_name, seed_value, players, variant_name)


func region_of(instance_name: String, seed_value: int, variant_name: String) -> Region:
	return InstanceBlueprints.region_of(instance_name, seed_value, variant_name)
