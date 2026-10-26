class_name DevelopmentLeaning
extends RefCounted
## What taking a stat node of a development web does (#677, #1358): a leaning, which shifts some of
## a species' stats, each in thousandths of the species' own (Fixed.ONE is the whole stat), up or
## down. A companion's stats rise through these, never by its level alone (#1358).

## How far one node shifts a stat at most, either way: half of it.
const MOST_SHIFT: int = 500
## The stats a leaning can shift, as its data names them.
const STATS: Array[String] = ["hp", "strength", "speed"]

var hp: int = 0
var strength: int = 0
var speed: int = 0


## Reads a node's `leaning` object `raw` into `leaning`; returns why it can't, or "".
static func read(raw: Variant, leaning: DevelopmentLeaning) -> String:
	var data: Dictionary = raw if raw is Dictionary else {}
	if data.is_empty():
		return "its leaning shifts one stat or more"
	var unknown: String = Content.unknown_field(data, STATS)
	if not unknown.is_empty():
		return "its leaning's " + unknown
	for stat: String in data:
		var shift: int = JsonNumbers.whole(data[stat], -MOST_SHIFT, MOST_SHIFT, 0)
		if shift == 0:
			return "its leaning shifts %s by whole thousandths from -%d to %d, not 0" % [
				stat,
				MOST_SHIFT,
				MOST_SHIFT,
			]
		leaning.set(stat, shift)
	return ""
