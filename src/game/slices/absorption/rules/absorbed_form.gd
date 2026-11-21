class_name AbsorbedForm
extends RefCounted
## A snapshot of one absorbed creature's form (#2412, AbsorptionFeature): its species, its
## permanent stats (HP, strength, speed as its species and the instance give them) and its attack
## kit (strike type, special, passives), without any temporary state (rage, wounds, held or tonic
## effects). Keeps the absorbed individual's stable short id (`short_id`, or "" for an authored
## form seeded by a scene or boss rule), so each wild individual is absorbed at most once.

var short_id: String = ""
var species: String = ""
var hp: int = 0
var strength: int = 0
var speed: int = 0
var strike_type: String = ""
var special: String = ""
var passives: Array[String] = []


## An independent copy of this form snapshot, so callers never mutate a catalogue's own entry.
func copy() -> AbsorbedForm:
	var clone: AbsorbedForm = AbsorbedForm.new()
	clone.short_id = short_id
	clone.species = species
	clone.hp = hp
	clone.strength = strength
	clone.speed = speed
	clone.strike_type = strike_type
	clone.special = special
	clone.passives = passives.duplicate()
	return clone


## Every value of this snapshot, in a fixed order, for the state hash.
func hash_values() -> Array[int]:
	var values: Array[int] = [
		StateHash.name_code(short_id),
		StateHash.name_code(species),
		hp,
		strength,
		speed,
		StateHash.name_code(strike_type),
		StateHash.name_code(special),
		passives.size(),
	]
	for passive: String in passives:
		values.append(StateHash.name_code(passive))
	return values


## This snapshot as save data (#119): whole numbers, ids and lists only.
func to_data() -> Dictionary:
	return {
		"short_id": short_id,
		"species": species,
		"hp": hp,
		"strength": strength,
		"speed": speed,
		"strike_type": strike_type,
		"special": special,
		"passives": passives.duplicate(),
	}


## Reads a saved form snapshot from `entry`; reports invalid fields to `entry` and returns null.
static func from_data(entry: DataReader) -> AbsorbedForm:
	var form: AbsorbedForm = AbsorbedForm.new()
	form.short_id = entry.text("short_id")
	form.species = entry.text("species")
	form.hp = entry.whole("hp", 1, Fixed.MAX_AMOUNT)
	form.strength = entry.whole("strength", 0, Fixed.MAX_AMOUNT)
	form.speed = entry.whole("speed", 0, Fixed.MAX_AMOUNT)
	form.strike_type = entry.text("strike_type")
	form.special = entry.text("special")
	if entry.failed():
		return null
	if not form.short_id.is_empty() and not ShortId.is_valid(form.short_id):
		entry.fail("absorbed form has invalid short_id %s" % form.short_id)
		return null
	if not Ids.is_id(form.species):
		entry.fail("absorbed form has invalid species %s" % form.species)
		return null
	if not _optional_id(form.strike_type) or not _optional_id(form.special):
		entry.fail("absorbed form of %s has an invalid kit id" % form.species)
		return null
	if not _read_passives(entry, form.passives):
		return null
	return form


## Whether `value` is either empty or a valid content id.
static func _optional_id(value: String) -> bool:
	return value.is_empty() or Ids.is_id(value)


## Reads the saved passive ids under `passives` into `out`; reports bad data and returns whether
## they were all valid ids.
static func _read_passives(entry: DataReader, out: Array[String]) -> bool:
	var raw: Variant = entry.data.get("passives")
	if not raw is Array:
		entry.fail("passives isn't a list")
		return false
	var items: Array = raw
	for item: Variant in items:
		if not item is String or not Ids.is_id(str(item)):
			entry.fail("passives holds an invalid ability id")
			return false
		out.append(str(item))
	return true
