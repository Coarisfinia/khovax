class_name BlueprintSource
extends InstanceSource
## The instance blueprints (InstanceBlueprints) as what the World loads its instances from (#396).


func exists(instance_name: String) -> bool:
	return InstanceBlueprints.exists(instance_name)


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
