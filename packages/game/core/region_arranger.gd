class_name RegionArranger
extends RefCounted
## Arranges a blueprint's region pieces into one region (#57). The first piece is laid down as it
## is, holding the players' starts. Every other piece is placed once, in an order the seed
## shuffles, a piece that ends a way (one connector) after those that lead on: turned and attached
## so one of its connectors meets an open connector of the region so far, without overlapping it,
## the seed picking among all the fits. Connectors left open at the end are plain edge. Then the
## seed turns the whole region, unless the blueprint keeps its orientation (#120).

## The region's own random stream (#32), apart from the features' streams, which are their ids.
const STREAM: int = 0x5245_4749


## The region arranged from `pieces` for `seed_value`, or one whose `problem` says why a piece
## fits nowhere.
static func arrange(pieces: Array[Region], seed_value: int, turning: bool) -> Region:
	var rng: Rng = Rng.new(seed_value, STREAM)
	var region: Region = pieces[0].turned(0)
	var order: Array[int] = []
	order.assign(range(1, pieces.size()))
	_shuffle(order, rng)
	for index: int in _ends_last(order, pieces):
		var fits: Array[Vector3i] = _fits(region, pieces[index])
		if fits.is_empty():
			region.problem = "region piece %d fits nowhere" % index
			return region
		var fit: Vector3i = fits[rng.below(fits.size())]
		_attach(region, pieces[index], fit)
	if turning:
		region = region.turned(rng.below(Hex.DIRECTIONS.size()))
	region.connectors.clear()
	return region


## `order`, the shuffled indexes into `pieces`, with every piece that ends a way (one connector,
## like a dungeon's end, #1591) moved behind the pieces that lead on, each kind keeping its shuffled
## order. Placed earlier, an end could close the last open connector and leave the rest nowhere to
## fit; placed last, it caps the way. Without ends the order stays as it is.
static func _ends_last(order: Array[int], pieces: Array[Region]) -> Array[int]:
	var leading: Array[int] = []
	var ends: Array[int] = []
	for index: int in order:
		if pieces[index].connectors.size() == 1:
			ends.append(index)
		else:
			leading.append(index)
	leading.append_array(ends)
	return leading


## Every way `piece` fits onto an open connector of `region`, in a fixed order: (open connector's
## index, the piece's connector's index, turns).
static func _fits(region: Region, piece: Region) -> Array[Vector3i]:
	var fits: Array[Vector3i] = []
	for turns: int in Hex.DIRECTIONS.size():
		var turned: Region = piece.turned(turns)
		for open: int in region.connectors.size():
			for own: int in turned.connectors.size():
				var facing: bool = _faces(region.connectors[open], turned.connectors[own])
				var offset: Vector2i = _offset(region.connectors[open], turned.connectors[own])
				if facing and region.fits(turned, offset):
					fits.append(Vector3i(open, own, turns))
	return fits


## Places `piece` the way `fit` says and closes the two connectors that met.
static func _attach(region: Region, piece: Region, fit: Vector3i) -> void:
	var turned: Region = piece.turned(fit.z)
	var open: Vector3i = region.connectors[fit.x]
	var own: Vector3i = turned.connectors[fit.y]
	turned.connectors.remove_at(fit.y)
	region.connectors.remove_at(fit.x)
	region.place(turned, _offset(open, own))


## Whether two connectors open towards each other.
static func _faces(open: Vector3i, own: Vector3i) -> bool:
	return own.z == posmod(open.z + 3, Hex.DIRECTIONS.size())


## How far to move a piece so its connector `own` lands next to `open`, on the side it opens to.
static func _offset(open: Vector3i, own: Vector3i) -> Vector2i:
	var target: Vector2i = Vector2i(open.x, open.y) + Hex.DIRECTIONS[open.z]
	return target - Vector2i(own.x, own.y)


## Shuffles `values` in place from `rng` (Fisher–Yates), the same way for the same stream.
static func _shuffle(values: Array[int], rng: Rng) -> void:
	for i: int in range(values.size() - 1, 0, -1):
		var j: int = rng.below(i + 1)
		var swapped: int = values[i]
		values[i] = values[j]
		values[j] = swapped
