class_name DominationShares
extends RefCounted
## Who gets which wild monster when one ring dominates several (#260, owner): each player in the
## instance who helped gets a number of them fitting their contribution, the tiles of the ring's
## wall they colored plus the segments of it they reinforced while it sealed (#227). The monsters
## are handed out one at a time, each to the player with the largest share still owed, ties going to
## whoever joined first (the lower entity id, #86): that rounds every share to the closest whole
## monster, and settles what rounding leaves over or short. Whoever gets none gets loot rolls
## instead (DominationLootFeature). A ring around one monster keeps its dominator, the lowest slot
## that colored it (#87). Integers only: shares are compared as contribution × monsters, never
## divided.


## How much each player in the instance did for `seal`'s ring, by entity id, in id order: its wall
## tiles they colored on `trail`, plus its wall segments they stood on while it sealed. Players
## who did neither are missing.
static func contributions(state: GameState, trail: Trail, seal: RingSeal) -> Dictionary[int, int]:
	var done: Dictionary[int, int] = {}
	for entity: Entity in state.entities:
		if entity.slot == Entity.NO_SLOT:
			continue
		var stood_on: Array = seal.braced_walls.get(entity.id, [])
		var amount: int = stood_on.size()
		for wall: Vector2i in seal.walls:
			amount += 1 if trail.tiles.get(wall, 0) == entity.id else 0
		if amount > 0:
			done[entity.id] = amount
	return done


## Each of `monsters` (in id order) with the entity id of the player who gets it, by monster id,
## from `done` (contributions by entity id). Empty when nobody contributed.
static func hand_out(monsters: Array[int], done: Dictionary[int, int]) -> Dictionary[int, int]:
	var given: Dictionary[int, int] = {}
	var helpers: Array[int] = []
	helpers.assign(done.keys())
	helpers.sort()
	var total: int = 0
	for helper: int in helpers:
		total += done[helper]
	if total == 0:
		return given
	var received: Dictionary[int, int] = {}
	for monster: int in monsters:
		var best: int = helpers[0]
		for helper: int in helpers:
			if _owed(helper, done, received, monsters.size(), total) > _owed(
				best, done, received, monsters.size(), total
			):
				best = helper
		given[monster] = best
		received[best] = received.get(best, 0) + 1
	return given


## What `helper` is still owed, scaled by `total` to stay whole: their share of the monsters (their
## contribution × the monsters, over the total) less the monsters they already have.
static func _owed(
	helper: int,
	done: Dictionary[int, int],
	received: Dictionary[int, int],
	count: int,
	total: int,
) -> int:
	return done[helper] * count - received.get(helper, 0) * total


## What each player in the instance did for `seal`'s ring (#86), into `dominated`: the wall tiles
## they colored, and the ticks they stood on the wall while it sealed. Read before the ring comes
## off the trail.
static func add_contributions(
	state: GameState,
	seal: RingSeal,
	dominated: WildMonsterDominated,
) -> void:
	var trail: Trail = (state.feature(Features.TRAIL) as TrailFeature).shared
	for wall: Vector2i in seal.walls:
		var colorer_id: int = trail.tiles.get(wall, 0)
		var colorer: Entity = state.entity(colorer_id)
		if colorer != null and colorer.slot != Entity.NO_SLOT:
			dominated.walls_colored[colorer.slot] = dominated.walls_colored.get(colorer.slot, 0) + 1
	# By slot, added up: a player who left and came back is a new entity in the same slot.
	for braced_id: int in seal.braced:
		var bracer: Entity = state.entity(braced_id)
		if bracer != null and bracer.slot != Entity.NO_SLOT:
			var had: int = dominated.braced_ticks.get(bracer.slot, 0)
			dominated.braced_ticks[bracer.slot] = had + seal.braced[braced_id]
