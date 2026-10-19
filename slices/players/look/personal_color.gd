class_name PersonalColor
extends RefCounted
## Every player's personal color (#233): their circle shows it. By default it comes from the seed
## of the world they play in (owner), so it stays the same for that world: the seed picks one hue,
## and the slots sit a quarter of the color wheel apart from it, so up to four players' colors stay
## easy to tell apart. The player can choose another in the menu's Character tab (#391), kept in
## their profile. It's a view's, never the simulation's, so it never enters the state hash.

const SATURATION: float = 0.65
const VALUE: float = 0.95
## A large odd number that spreads neighbouring seeds' hues around the wheel.
const SPREAD: int = 2_654_435_761
const HUES: int = 360
## How far apart the slots' hues sit: a quarter of the wheel, for up to four players.
const SLOT_STEP: int = 90
const OPAQUE: int = 0xff


## The default personal color of the player in `slot`, in the world built from `world_seed`.
static func of(world_seed: int, slot: int) -> Color:
	# Each factor brought onto the wheel first, so a large seed can't overflow the product.
	var base: int = posmod(posmod(world_seed, HUES) * posmod(SPREAD, HUES), HUES)
	var hue: int = posmod(base + slot * SLOT_STEP, HUES)
	return Color.from_hsv(float(hue) / HUES, SATURATION, VALUE)


## The personal color of the player in `slot` as this machine shows it: this machine's player's
## choice from their profile (#391), else the default of `driver`'s world. Other players show their
## defaults until co-op hands their choices over.
static func shown(driver: Session, slot: int) -> Color:
	if driver == null or driver.world == null:
		return of(0, slot)
	var local: int = driver.input.slot if driver.input != null else 0
	var holder: ProfileHolder = driver.holder
	var chosen: int = holder.personal_color() if holder != null else Profile.AUTO_COLOR
	if slot == local and chosen != Profile.AUTO_COLOR:
		return of_number(chosen)
	return of(driver.world.world_seed, slot)


## `color` as the profile keeps it: 0xRRGGBB.
static func number_of(color: Color) -> int:
	return color.to_rgba32() >> 8


## The color the profile keeps as `number`, 0xRRGGBB.
static func of_number(number: int) -> Color:
	return Color.hex((number << 8) | OPAQUE)
