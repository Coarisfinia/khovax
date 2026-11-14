class_name WildBabies
extends RefCounted
## Which wild monsters start as babies (owner's ground rule, #1697): young of their line, level 1
## and unevolved, living beside the grown ones. The spots whose species was rolled from the
## blueprint's list form bundles the way packs gather (PackFeature): in order, each spot not in a
## bundle yet leads one and gathers the nearest such spots within BUNDLE_REACH of it, the earlier of
## the equally near first, up to BUNDLE_SIZE with itself. Only a monster whose species has an
## earlier form, a baby species of its own (owner, on #1722), can be a baby. Which bundles that have
## one hold babies is counted, not rolled (#2239): each adds CHANCE to a count from 0, and one whose
## CHANCE makes the count a whole holds babies, so at 600 thousandths the second, fourth and fifth
## of every five do, and an instance with a single such bundle has none. In such a bundle the last
## half of those that can be, at least one, are babies, each of the first form of its own species'
## line. A bundle without one doesn't count. A spot whose region names its species keeps its grown
## monster, so a boss or a quest's monster never starts as a baby.

## The share of bundles that hold babies, in thousandths; its number is in Tuning.
const CHANCE: int = Tuning.WILD_BABY_CHANCE
## A bundle gathers like a pack: as many and as far.
const BUNDLE_SIZE: int = Tuning.PACK_SIZE
const BUNDLE_REACH: int = Tuning.PACK_REACH


## The spots among `rolled`, in bundle order, that start as babies: only those `young` holds, the
## spots whose species has an earlier form.
static func chosen(rolled: Array[Vector2i], young: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var babies: Array[Vector2i] = []
	var count: int = 0
	for bundle: Array in bundles(rolled):
		var can: Array[Vector2i] = []
		for spot: Vector2i in bundle:
			if young.has(spot):
				can.append(spot)
		if can.is_empty():
			continue
		count += CHANCE
		if count < Fixed.ONE:
			continue
		count -= Fixed.ONE
		var many: int = maxi(Fixed.div_floor(can.size(), 2), 1)
		babies.append_array(can.slice(can.size() - many))
	return babies


## The bundles `spots` form, each led by its first spot.
static func bundles(spots: Array[Vector2i]) -> Array[Array]:
	var found: Array[Array] = []
	var bundled: Dictionary[Vector2i, bool] = {}
	for leader: Vector2i in spots:
		if bundled.has(leader):
			continue
		bundled[leader] = true
		var near: Array[Vector2i] = []
		for i: int in spots.size():
			var distance: int = Hex.distance(spots[i], leader)
			if not bundled.has(spots[i]) and distance <= BUNDLE_REACH:
				near.append(Vector2i(distance, i))
		near.sort()
		var bundle: Array[Vector2i] = [leader]
		for gathered: Vector2i in near.slice(0, BUNDLE_SIZE - 1):
			bundle.append(spots[gathered.y])
			bundled[spots[gathered.y]] = true
		found.append(bundle)
	return found
