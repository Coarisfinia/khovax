class_name BlueprintSource
extends InstanceSource
## The instance blueprints (InstanceBlueprints) as what the World loads its instances from (#396).


func exists(instance_name: String) -> bool:
	return InstanceBlueprints.exists(instance_name)


func create(instance_name: String, seed_value: int, players: int) -> GameState:
	return InstanceBlueprints.create(instance_name, seed_value, players)


func region_of(instance_name: String, seed_value: int) -> Region:
	return InstanceBlueprints.region_of(instance_name, seed_value)
