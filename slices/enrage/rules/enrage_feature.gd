class_name EnrageFeature
extends Feature
## Enrage (#220): fleeing is boring, so a ring that breaks always enrages the wild monsters that
## were inside. Each gains a stack of rage, up to WildMonsterFeature.MOST_RAGE, which makes it
## stronger (so it pushes harder on the next ring) and heals part of its HP. Stacks add up with
## every further ring that fails. The camera stays still: the rage shows on the monsters. Speed and
## going for the player come when wild monsters move and fight (#221).
##
## It reads the tick's RingBroken events, so it runs after the domination feature, and changes the
## wild monsters only through WildMonsterFeature.enrage. A seal never feels the rage it causes: the
## ring that broke has ended, and a monster is sealed in one ring at a time, so the extra strength
## first pushes on the next ring that closes around it.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "enrage"
## How much of a wild monster's full HP each enraging heals (thousandths). A placeholder to tune.
const HEAL: int = 250


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [WildMonsterFeature.ID, DominationFeature.ID]
	return needed


func step(state: GameState, _commands: Array[Command]) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for event: RefCounted in state.events:
		var broken: RingBroken = event as RingBroken
		if broken == null:
			continue
		for monster_id: int in broken.monster_ids:
			wild.enrage(state, monster_id, HEAL)
