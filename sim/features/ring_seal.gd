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


## The seal as save data.
func to_data() -> Dictionary:
	return {
		"walls": DataReader.flat(walls),
		"damage": damage,
		"integrity": integrity,
		"monsters": monsters,
		"targets": targets,
		"ticks": ticks,
		"seal_ticks": seal_ticks,
	}


## The seal `to_data` saved, or null (reported to `values`) when it doesn't hold together: every
## segment with its damage, every monster a wild monster with a segment, and the ticks in range.
static func from_data(values: DataReader, state: GameState, wild: WildMonsterFeature) -> RingSeal:
	var seal: RingSeal = RingSeal.new()
	seal.walls = values.tiles("walls", state.region)
	seal.damage = values.wholes("damage", 0, DataReader.MOST)
	seal.integrity = values.whole("integrity", 1, DataReader.MOST)
	seal.monsters = values.wholes("monsters", 1, DataReader.MOST)
	seal.targets = values.wholes("targets", 0, maxi(seal.walls.size() - 1, 0))
	seal.seal_ticks = values.whole("seal_ticks", 1, DataReader.MOST)
	seal.ticks = values.whole("ticks", 0, seal.seal_ticks)
	var whole: bool = not seal.walls.is_empty() and seal.damage.size() == seal.walls.size()
	whole = whole and seal.targets.size() == seal.monsters.size()
	for monster: int in seal.monsters:
		whole = whole and wild.is_wild_monster(monster)
	if values.failed() or not whole:
		values.fail("a sealing ring doesn't hold together")
		return null
	return seal


## Every value of the seal, for the state hash, in a fixed order.
func hash_values() -> Array[int]:
	var values: Array[int] = [integrity, ticks, seal_ticks, walls.size()]
	for i: int in walls.size():
		values.append_array([walls[i].x, walls[i].y, damage[i]])
	values.append(monsters.size())
	for i: int in monsters.size():
		values.append_array([monsters[i], targets[i]])
	return values
