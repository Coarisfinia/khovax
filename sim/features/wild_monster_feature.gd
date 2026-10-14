class_name WildMonsterFeature
extends Feature
## Wild monsters (#19): when the run begins, one stands on every spot the map marks for it, as an
## entity no player controls. For now each is a stand-in ball that just stands there; walkers
## can't step onto its tile (MovementFeature), and a later rule catches it (#20). Like every
## feature, switched off it keeps its state: the monsters stay where they are, and only its own
## rules (catching, later) stop.

## Every wild monster's entity id, in id order.
var monsters: Array[int] = []


func id() -> int:
	return Features.WILD_MONSTERS


func start(state: GameState) -> void:
	for spot: Vector2i in state.map.wild_monsters:
		# Can't be refused: an entity without a slot is always added.
		var monster: Entity = state.add_entity(Entity.NO_SLOT, spot)
		monsters.append(monster.id)


func entity_removed(_state: GameState, removed_id: int) -> void:
	monsters.erase(removed_id)


## Whether the entity with this id is a wild monster.
func is_wild_monster(entity_id: int) -> bool:
	return monsters.has(entity_id)


func hash_values() -> Array[int]:
	var values: Array[int] = [monsters.size()]
	values.append_array(monsters)
	return values
