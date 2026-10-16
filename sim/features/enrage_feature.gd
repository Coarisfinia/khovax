class_name EnrageFeature
extends Feature
## Enrage (#220): fleeing is boring, so a ring that breaks always enrages the wild monsters that
## were inside. Each gains a stack of rage, up to WildMonsterFeature.MOST_RAGE, which makes it
## stronger (so it pushes harder on the next ring) and heals part of its HP. Stacks add up with
## every further ring that fails. The camera stays still: the rage shows on the monsters. Speed and
## going for the player come when wild monsters move and fight (#221).
##
## It reads the tick's RingBroken events, so it runs after the catch feature, and changes the wild
## monsters only through WildMonsterFeature.enrage.

## How much of a wild monster's full HP each enraging heals (thousandths). A placeholder to tune.
const HEAL: int = 250


func id() -> int:
	return Features.ENRAGE


func requires() -> Array[int]:
	var needed: Array[int] = [Features.WILD_MONSTERS, Features.CATCH]
	return needed


func step(state: GameState, _commands: Array[Command]) -> void:
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	for event: RefCounted in state.events:
		var broken: RingBroken = event as RingBroken
		if broken == null:
			continue
		for monster_id: int in broken.monster_ids:
			wild.enrage(monster_id, HEAL)
