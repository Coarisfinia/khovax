class_name EnrageFeature
extends Feature
## Enrage (#220): fleeing is boring, so a ring that breaks always enrages the wild monsters that
## were inside. Each gains a stack of rage, up to WildMonsterFeature.MOST_RAGE, which makes it
## stronger (so it pushes harder on the next ring) and heals part of its HP. Stacks add up with
## every further ring that fails. The camera stays still: the rage shows on the monsters.
##
## Enraged, a wild monster goes for the players (#961): it's faster (WildPace.paced), and
## free, it chases the nearest player (not one a dialog holds, whom HealthFeature shields, #981),
## the lowest id of the equally near, a step at a time at its pace (WildMonsterFeature.chase); one
## a ring encircles or seals stays where it stands, as every monster in a ring does. Next to a
## player, it strikes them first (WildAttackFeature).
##
## It reads the tick's RingBroken events, so it runs after the domination feature, and changes the
## wild monsters only through WildMonsterFeature.enrage and chase. A seal never feels the rage it
## causes: the ring that broke has ended, and a monster is sealed in one ring at a time, so the
## extra strength first pushes on the next ring that closes around it.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "enrage"
## What each enraging heals, in thousandths of full HP. A placeholder to tune (#960).
const HEAL: int = 250


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [HealthFeature.ID, DominationFeature.ID]
	return needed


## The wild monsters it enrages, which an instance without wild monster spots lacks (#884): no ring
## breaks there.
func after() -> Array[String]:
	var earlier: Array[String] = [WildMonsterFeature.ID]
	return earlier


func step(state: GameState, _commands: Array[Command]) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild == null:
		return
	for event: RefCounted in state.events:
		var broken: RingBroken = event as RingBroken
		if broken == null:
			continue
		for monster_id: int in broken.monster_ids:
			wild.enrage(state, monster_id, HEAL)
	_chase(state, wild)


## Every enraged wild monster in no ring steps toward the nearest player, on its tick to step, in id
## order.
func _chase(state: GameState, wild: WildMonsterFeature) -> void:
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	for monster_id: int in wild.monsters:
		if wild.rage_of(monster_id) == 0:
			continue
		if domination.is_encircled(monster_id) or domination.is_sealed(monster_id):
			continue
		var from: Vector2i = state.entity(monster_id).tile
		var nearest: Entity = null
		for entity: Entity in state.entities:
			if entity.slot == Entity.NO_SLOT or health.is_shielded(entity.id):
				continue
			var gap: int = Hex.distance(entity.tile, from)
			if nearest == null or gap < Hex.distance(nearest.tile, from):
				nearest = entity
		if nearest != null:
			wild.chase(state, monster_id, nearest.tile)
