class_name RingSeal
extends RefCounted
## DominationFeature's data for one player's ring while it seals (#219): its wall segments, the
## damage each has taken, the wild monsters inside and the segment each one pushes on, and how far
## the seal has come. Everything is fixed when the ring closes; only the damage and the ticks
## change.

## The ring's wall segments: the trail tiles next to the tiles it encloses, sorted.
var walls: Array[Vector2i] = []
## The damage each segment has taken, in thousandths, in the order of `walls`.
var damage: Array[int] = []
## The damage a segment takes before it fails, in thousandths.
var integrity: int = 0
## The wild monsters inside, in id order, and the index in `walls` of the segment each one pushes
## on: the nearest, as a ring holds its wild monsters where they stand.
var monsters: Array[int] = []
var targets: Array[int] = []
## Ticks the seal has held, and how many it must hold.
var ticks: int = 0
## How many ticks each player has stood on the wall while it seals, by entity id (#86, #227).
var braced: Dictionary[int, int] = {}
## Which of its wall segments each player has stood on while it seals, by entity id, each list
## sorted (#260): how many segments they reinforced.
var braced_walls: Dictionary[int, Array] = {}
var seal_ticks: int = 0


## How far the seal has come, in thousandths: ONE when it holds.
func progress() -> int:
	return Fixed.ratio(ticks, seal_ticks)


## The index of the first wall segment whose damage has reached its integrity, or -1 while every
## one holds.
func failed_segment() -> int:
	for segment: int in walls.size():
		if damage[segment] >= integrity:
			return segment
	return -1


## Drops a wild monster that left the instance: it pushes no more.
func drop(monster_id: int) -> void:
	var index: int = monsters.find(monster_id)
	if index >= 0:
		monsters.remove_at(index)
		targets.remove_at(index)


## The seal as save data: only what can't be worked out again from the instance (the walls, kept
## to check the rebuilt ones against). DominationFeature.load_values rebuilds the rest. Copies, as
## the seal goes on changing its own lists after a snapshot (a recording's starting world) is taken.
func to_data() -> Dictionary:
	return {
		"walls": DataReader.flat(walls),
		"damage": damage.duplicate(),
		"monsters": monsters.duplicate(),
		"ticks": ticks,
		"braced": DataReader.flat_pairs(braced),
		"braced_walls": braced_walls_flat(),
	}


## The braced wall segments as [entity id, q, r, ...], in id order, then in each list's order.
func braced_walls_flat() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(braced_walls.keys())
	ids.sort()
	var flat: Array[int] = []
	for each: int in ids:
		for wall: Vector2i in braced_walls[each]:
			flat.append_array([each, wall.x, wall.y])
	return flat


## Notes that the player `entity_id` stands on wall segment `wall` this tick.
func brace(entity_id: int, wall: Vector2i) -> void:
	braced[entity_id] = braced.get(entity_id, 0) + 1
	var walls_stood_on: Array = braced_walls.get(entity_id, [])
	if not walls_stood_on.has(wall):
		walls_stood_on.append(wall)
		walls_stood_on.sort()
	braced_walls[entity_id] = walls_stood_on


## Every value of the seal, for the state hash, in a fixed order.
func hash_values() -> Array[int]:
	var values: Array[int] = [integrity, ticks, seal_ticks, walls.size()]
	for i: int in walls.size():
		values.append_array([walls[i].x, walls[i].y, damage[i]])
	values.append(monsters.size())
	for i: int in monsters.size():
		values.append_array([monsters[i], targets[i]])
	values.append(braced.size())
	values.append_array(DataReader.flat_pairs(braced))
	var walls_flat: Array[int] = braced_walls_flat()
	values.append(walls_flat.size())
	values.append_array(walls_flat)
	return values
