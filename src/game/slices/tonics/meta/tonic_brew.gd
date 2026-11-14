class_name TonicBrew
extends RefCounted
## One brew a tonic allows (#2090, the potion design on #2049): its target, its one primary and at
## most one trait, its exact cost and its values, as the simulation will apply them (#2091). The
## profile counts each one like a material, by its id.

## Where a brew's fields are in the tonic's schema (SchemaFields, #825).
const FIELDS: String = "/properties/brews/items"
## The effects that change strikes: players don't strike, so these are the companion's only.
const COMPANION_ONLY: Array[String] = ["quicken", "fortify"]
## The effect that heals at once, so it has no duration to make last.
const INSTANT: String = "mend"
## The longest wait or duration, in seconds, and the farthest reach, in tiles, the schema allows.
const MOST_SECONDS: int = 3600
const MOST_TILES: int = 10

## Its id: its target's prefix, its primary, then its trait unless it's none.
var id: String = ""
## Its name as the player reads it, untranslated.
var name: String = ""
## Who it helps (Tonic.TARGETS).
var target: String = ""
## Its primary ingredient's material id, which sets its effect.
var primary: String = ""
## Its effect, as its tonic gives its primary.
var effect: String = ""
## Its trait (Tonic.TRAITS), "none" for the base values.
var trait_id: String = ""
## The materials crafting it spends, by id: how many of each.
var cost: Dictionary[String, int] = {}
## Its effect's strength, in thousandths.
var potency: int = 0
## How long its effect lasts, how long after drinking it starts, and how far it reaches.
var seconds: int = 0
var delay_seconds: int = 0
var reach_tiles: int = 0


## Reads the brew `raw` of `tonic` into this; returns why it can't, or "": its fields, its cost and
## its choices keep to the design's rules.
func read(raw: Variant, tonic: Tonic) -> String:
	var data: Dictionary = raw if raw is Dictionary else {}
	var why: String = Content.unknown_field(data, SchemaFields.at(Tonic.SCHEMA, FIELDS))
	if why.is_empty():
		why = _read_fields(data, tonic)
	if why.is_empty():
		why = _read_cost(data.get("cost"), tonic)
	if why.is_empty():
		why = _rules_problem()
	return why


## Reads the brew's choices and values from `data`; returns why it can't, or "".
func _read_fields(data: Dictionary, tonic: Tonic) -> String:
	id = Content.text_of(data.get("id"))
	name = Content.text_of(data.get("name"))
	target = Content.text_of(data.get("target"))
	primary = Content.text_of(data.get("primary"))
	trait_id = Content.text_of(data.get("trait"))
	if not tonic.targets.has(target) or not tonic.primaries.has(primary):
		return "brew %s needs one of its tonic's targets and one of its primaries" % id
	if not tonic.traits.has(trait_id):
		return "brew %s needs one of its tonic's traits" % id
	effect = tonic.primaries[primary]
	var expected: String = tonic.targets[target] + "_" + primary
	if trait_id != "none":
		expected += "_" + trait_id
	if id != expected:
		return "brew %s must be named %s, by its target, primary and trait" % [id, expected]
	if name.strip_edges().is_empty():
		return "brew %s needs a name" % id
	potency = JsonNumbers.whole(data.get("potency"), 1, Fixed.ONE - 1, 0)
	seconds = JsonNumbers.whole(data.get("seconds"), 0, MOST_SECONDS, -1)
	delay_seconds = JsonNumbers.whole(data.get("delay_seconds", 0), 0, MOST_SECONDS, -1)
	reach_tiles = JsonNumbers.whole(data.get("reach_tiles", 0), 0, MOST_TILES, -1)
	if potency == 0 or seconds < 0 or delay_seconds < 0 or reach_tiles < 0:
		return "brew %s needs a potency from 1 to 999 and whole seconds and tiles" % id
	return ""


## Reads the brew's cost `raw`; returns why it can't, or "": its tonic's carrier and the brew's
## primary, each at least once, and the catalyst exactly when it's Shared; nothing else.
func _read_cost(raw: Variant, tonic: Tonic) -> String:
	var given: Dictionary = raw if raw is Dictionary else {}
	var allowed: Array[String] = [tonic.carrier, primary]
	if trait_id == "shared":
		allowed.append(tonic.catalyst)
	for material: Variant in given:
		var count: int = JsonNumbers.whole(given[material], 1, Fixed.ONE, 0)
		if not allowed.has(str(material)) or count == 0:
			return "brew %s's cost takes only %s, each a whole count from 1" % [id, allowed]
		cost[str(material)] = count
	if cost.size() != allowed.size():
		return "brew %s's cost needs %s" % [id, allowed]
	return ""


## Why the brew's choices break the design's rules (#2049, section 5), or "".
func _rules_problem() -> String:
	if target == "player" and COMPANION_ONLY.has(effect):
		return "brew %s: players don't strike, so %s is for companions" % [id, effect]
	if effect == INSTANT and (trait_id == "lasting" or seconds != 0):
		return "brew %s: %s is instant, with nothing to make last" % [id, effect]
	if effect != INSTANT and seconds == 0:
		return "brew %s needs its effect's seconds" % id
	if (trait_id == "slow_release") != (delay_seconds > 0):
		return "brew %s: only Slow-release waits before it starts" % id
	if (trait_id == "shared") != (reach_tiles > 0):
		return "brew %s: only Shared reaches other players" % id
	return ""
