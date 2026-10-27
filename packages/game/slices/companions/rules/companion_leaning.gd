class_name CompanionLeaning
extends RefCounted
## How a carried monster's stats lean (#1358): what the stat nodes it took on its development web
## add up to (DevelopmentLeaning, read in its player's profile), each stat's shift in thousandths of
## its species' own (Fixed.ONE is the whole stat), up or down. A monster's stats rise through these,
## never by its level alone. Each shift is kept between LEAST and MOST, so a companion keeps at
## least some of every stat, and a whole leaning fits in one value of a carry request (`code`).

## How far a leaning shifts a stat down at most, and up at most, in thousandths. Its numbers are in
## Tuning.
const LEAST: int = Tuning.COMPANION_LEAST_LEANING
const MOST: int = Tuning.COMPANION_MOST_LEANING
## The stats a leaning shifts, in the order its data and its code hold them.
const STATS: Array[String] = ["hp", "strength", "speed"]
## How many bits one stat's shift takes in a leaning's code: enough for MOST - LEAST.
const SHIFT_BITS: int = 11

var hp: int = 0
var strength: int = 0
var speed: int = 0


## A leaning shifting HP by `hp_shift`, strength by `strength_shift` and speed by `speed_shift`,
## each
## kept between LEAST and MOST.
static func of(hp_shift: int, strength_shift: int, speed_shift: int) -> CompanionLeaning:
	var leaning: CompanionLeaning = CompanionLeaning.new()
	leaning.hp = clampi(hp_shift, LEAST, MOST)
	leaning.strength = clampi(strength_shift, LEAST, MOST)
	leaning.speed = clampi(speed_shift, LEAST, MOST)
	return leaning


## Whether it shifts no stat.
func is_none() -> bool:
	return hp == 0 and strength == 0 and speed == 0


func same_as(other: CompanionLeaning) -> bool:
	return to_data() == other.to_data()


## As data: each stat's shift, in STATS' order.
func to_data() -> Array[int]:
	return [hp, strength, speed]


## The leaning `to_data` gave, or null when `data` isn't a shift for each stat, each from LEAST to
## MOST.
static func of_data(data: Variant) -> CompanionLeaning:
	var listed: Array = data if data is Array else []
	if listed.size() != STATS.size():
		return null
	var shifts: Array[int] = []
	for item: Variant in listed:
		var shift: int = item if item is int else LEAST - 1
		if shift < LEAST or shift > MOST:
			return null
		shifts.append(shift)
	return of(shifts[0], shifts[1], shifts[2])


## The leaning as one whole number for a carry request (CarryRequest.VALUE_BITS): each stat's shift
## above LEAST, in SHIFT_BITS bits each, in STATS' order from the lowest bits.
func code() -> int:
	var packed: int = 0
	var shifts: Array[int] = to_data()
	for place: int in range(shifts.size() - 1, -1, -1):
		packed = (packed << SHIFT_BITS) + shifts[place] - LEAST
	return packed


## The leaning `code` gave for `packed`, each shift kept between LEAST and MOST.
static func of_code(packed: int) -> CompanionLeaning:
	var shifts: Array[int] = []
	for place: int in STATS.size():
		shifts.append(((packed >> (place * SHIFT_BITS)) & ((1 << SHIFT_BITS) - 1)) + LEAST)
	return of(shifts[0], shifts[1], shifts[2])
