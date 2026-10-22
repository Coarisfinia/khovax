class_name HarvestFeature
extends SpeciesLootFeature
## Harvesting (#629, from #221): a wild monster a companion's special fells (#410) is gone for good,
## and instead of being dominated it drops crafting materials, a real choice between the two. Every
## player in the instance rolls their own (#74): ROLLS_PER_PLAYER rolls on the felled monster's
## species' harvest table (#687, apart from the one dominations roll on), whose blank rolls on the
## instance's table (#90), or gives nothing in an instance without one. A species without a harvest
## table drops nothing. The rolls draw from this feature's own stream, in slot order. The number of
## rolls is a placeholder to tune (#960).

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "harvest"
const ROLLS_PER_PLAYER: int = 1


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [SpecialAttackFeature.ID]
	return needed


## The wild monsters it harvests, which an instance without wild monster spots lacks (#884): none
## falls there.
func after() -> Array[String]:
	var earlier: Array[String] = [WildMonsterFeature.ID]
	return earlier


## Rolls the materials of every wild monster felled this tick, in the order they fell.
func step(state: GameState, _commands: Array[Command]) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild == null:
		return
	# Copied, as the loop adds Harvested events to the same list.
	for event: RefCounted in state.events.duplicate():
		var struck: SpecialStruck = event as SpecialStruck
		if struck == null or not struck.felled:
			continue
		var species: String = wild.species_of(struck.monster_id)
		if not tables.has(species):
			continue
		var loot: Dictionary[int, Dictionary] = {}
		for slot: int in GameState.MAX_PLAYERS:
			if state.player(slot) != null:
				loot[slot] = roll_species(species, ROLLS_PER_PLAYER)
		state.events.append(_dropped(state, struck.monster_id, species, loot))


## The materials `loot` the felled `monster_id` dropped where it lies, as the event.
static func _dropped(
	state: GameState,
	monster_id: int,
	species: String,
	loot: Dictionary[int, Dictionary],
) -> Harvested:
	return Harvested.new(monster_id, species, state.entity(monster_id).tile, loot)
