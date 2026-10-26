class_name HostSettings
extends RefCounted
## The world's settings, which its host chooses (#1309): the player in slot HOST, whose world it
## is, and who can change them on the fly. They're kept in the host's world store (#724), in
## HostSettingsFeature's entry, so they're saved with the world, hashed, and every instance reads
## the same; they change only through the host's request (OutboxEntry.HOST_SETTING), which a
## replay plays back and every co-op machine applies on the same tick. The default balancing is
## Tuning's.
##
## The difficulty (#1315) is a factor on the wild monsters, in thousandths: Standard leaves Tuning's
## numbers as they are, Easy makes the wild monsters weaker by it and Hard stronger. It scales their
## strength (what their hits deal and how hard they push on a ring), their HP (as the damage they
## take, divided by it, so a wound in progress keeps its share whatever the difficulty), their pace
## (their steps and strikes come that much more often) and the ring's power against them (divided by
## it).

## The slot of the host, the player whose world it is.
const HOST: int = 0
## HostSettingsFeature's id (#784), the key of its entry in the host's world store: saved and
## hashed, so never changed once it shipped.
const FEATURE_ID: String = "host_settings"
## The difficulty's key in that entry, and the difficulties, as factors in thousandths (owner,
## #1315).
const DIFFICULTY: String = "difficulty"
const EASY: int = 700
const STANDARD: int = Fixed.ONE
const HARD: int = 1300
const DIFFICULTIES: Array[int] = [EASY, STANDARD, HARD]
## Each setting's choices, by its key: a request for any other is refused.
const CHOICES: Dictionary[String, Array] = { DIFFICULTY: DIFFICULTIES }
## Each setting's code in a request's data (`request_data`), by its key; never changed once
## shipped. The data is the code times CODE_SPAN plus the choice.
const CODES: Dictionary[String, int] = { DIFFICULTY: 1 }
const CODE_SPAN: int = 1_000_000


## The difficulty the host chose for the world `state` is in, or STANDARD.
static func difficulty(state: GameState) -> int:
	return chosen(state.stored(HOST, FEATURE_ID), DIFFICULTY)


## The choice of `setting` in the host's entry `entry`, or the setting's default.
static func chosen(entry: Dictionary, setting: String) -> int:
	var value: Variant = entry.get(setting)
	if value is int and CHOICES[setting].has(value):
		return value
	return default_of(setting)


## The choice `setting` has while the host chose none.
static func default_of(_setting: String) -> int:
	return STANDARD


## The data of a request that sets `setting` to `value`.
static func request_data(setting: String, value: int) -> int:
	return CODES[setting] * CODE_SPAN + value


## The setting a request's `data` sets, or "" for none there is.
static func setting_of(data: int) -> String:
	var code: int = Fixed.div_floor(data, CODE_SPAN)
	for setting: String in CODES:
		if CODES[setting] == code:
			return setting
	return ""


## The choice a request's `data` sets its setting to.
static func value_of(data: int) -> int:
	return data - Fixed.div_floor(data, CODE_SPAN) * CODE_SPAN


## A wild monster's `strength` at the difficulty of `state`.
static func enemy_strength(state: GameState, strength: int) -> int:
	return Fixed.scale(strength, difficulty(state))


## The `damage` a hit deals a wild monster at the difficulty of `state`: divided by it, as if its
## HP were scaled, and at least 1 while the hit deals any.
static func enemy_damage(state: GameState, damage: int) -> int:
	if damage <= 0:
		return damage
	return maxi(Fixed.mul_div(damage, Fixed.ONE, difficulty(state)), 1)


## `ticks` between a wild monster's steps or strikes at the difficulty of `state`: divided by it,
## never below one tick.
static func enemy_ticks(state: GameState, ticks: int) -> int:
	return maxi(Fixed.mul_div(ticks, Fixed.ONE, difficulty(state)), 1)


## A ring's `power` against the wild monsters at the difficulty of `state`: divided by it.
static func ring_power(state: GameState, power: int) -> int:
	return Fixed.mul_div(power, Fixed.ONE, difficulty(state))
