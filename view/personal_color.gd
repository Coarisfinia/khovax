class_name PersonalColor
extends RefCounted
## Every player's personal color (#233): their circle shows it. By default it comes from the seed
## of the world they play in (owner), so it stays the same for that world: the seed picks one hue,
## and the slots sit a quarter of the color wheel apart from it, so up to four players' colors stay
## easy to tell apart. Changing it in the character menu comes with that menu (#233). It's a
## view's, never the simulation's, so it never enters the state hash.

const SATURATION: float = 0.65
const VALUE: float = 0.95
## A large odd number that spreads neighbouring seeds' hues around the wheel.
const SPREAD: int = 2_654_435_761
const HUES: int = 360
## How far apart the slots' hues sit: a quarter of the wheel, for up to four players.
const SLOT_STEP: int = 90


## The default personal color of the player in `slot`, in the world built from `world_seed`.
static func of(world_seed: int, slot: int) -> Color:
	# Each factor brought onto the wheel first, so a large seed can't overflow the product.
	var base: int = posmod(posmod(world_seed, HUES) * posmod(SPREAD, HUES), HUES)
	var hue: int = posmod(base + slot * SLOT_STEP, HUES)
	return Color.from_hsv(float(hue) / HUES, SATURATION, VALUE)
