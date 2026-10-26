class_name DevelopmentOffer
extends RefCounted
## The development choice a dominated monster offers at a level-up (#678; at every one, the owner's
## pick on #1358): up to SIZE nodes drawn from the open part of its web (DevelopmentWeb), by the
## monster's own seed, so the same monster with the same nodes taken always offers the same. Its
## seed is its short id (ShortId.code), drawn from its instance's seeded stream when it was
## generated (#700), so it needs nothing new saved. Each choice draws from its own stream, numbered
## by the nodes already taken, since every choice takes one. An option offered before and not
## taken (skipped) can come back, but SKIPPED_WEIGHT times as likely as one never offered.

## How many options a choice offers, or every open node when fewer are open.
const SIZE: int = 3
## How likely a skipped option is drawn, in thousandths of one never offered: 90 % less.
const SKIPPED_WEIGHT: int = 100
## The stream a monster's first choice draws from; each later one draws from the next.
const STREAM: int = 678_000


## The options the monster with the short id `short_id` offers, with `taken` nodes of `web` taken
## and `skipped` ones offered before and not taken, in the order they were drawn.
static func of(
		web: DevelopmentWeb,
		short_id: String,
		taken: Array[String],
		skipped: Array[String],
) -> Array[String]:
	var rng: Rng = Rng.new(ShortId.code(short_id), STREAM + taken.size())
	var left: Array[String] = web.open_nodes(taken)
	var weights: Array[int] = []
	for node: String in left:
		weights.append(SKIPPED_WEIGHT if skipped.has(node) else Fixed.ONE)
	var offered: Array[String] = []
	while offered.size() < SIZE and not left.is_empty():
		var pick: int = _weighted(rng, weights)
		offered.append(left.pop_at(pick))
		weights.remove_at(pick)
	return offered


## The place of one of `weights` drawn from `rng`, each as likely as its weight.
static func _weighted(rng: Rng, weights: Array[int]) -> int:
	var total: int = 0
	for weight: int in weights:
		total += weight
	var roll: int = rng.below(total)
	for place: int in weights.size():
		roll -= weights[place]
		if roll < 0:
			return place
	return weights.size() - 1
