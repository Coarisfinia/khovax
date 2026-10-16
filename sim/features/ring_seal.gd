class_name RingSeal
extends RefCounted
## CatchFeature's data for one player's ring while it seals (#219): its wall segments, the damage
## each has taken, the wild monsters inside and the segment each one pushes on, and how far the
## seal has come. Everything is fixed when the ring closes; only the damage and the ticks change.

## The ring's wall segments: the trail tiles next to the tiles it encloses, sorted.
var walls: Array[Vector2i] = []
## The damage each segment has taken, in thousandths, in the order of `walls`.
var damage: Array[int] = []
## The damage a segment takes before it fails, in thousandths.
var integrity: int = 0
## The wild monsters inside, in id order, and the index in `walls` of the segment each one pushes
## on: the nearest, as wild monsters don't move.
var monsters: Array[int] = []
var targets: Array[int] = []
## Ticks the seal has held, and how many it must hold.
var ticks: int = 0
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
## to check the rebuilt ones against). CatchFeature.load_values rebuilds the rest.
func to_data() -> Dictionary:
	return {
		"walls": DataReader.flat(walls),
		"damage": damage,
		"monsters": monsters,
		"ticks": ticks,
	}


## Every value of the seal, for the state hash, in a fixed order.
func hash_values() -> Array[int]:
	var values: Array[int] = [integrity, ticks, seal_ticks, walls.size()]
	for i: int in walls.size():
		values.append_array([walls[i].x, walls[i].y, damage[i]])
	values.append(monsters.size())
	for i: int in monsters.size():
		values.append_array([monsters[i], targets[i]])
	return values
