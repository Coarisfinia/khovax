class_name WildSpot
extends RefCounted
## What a region piece's legend says about a named wild monster's spot (#133), beyond where it is:
## the species it names, whether its monster starts wounded (#389), the event its monster emits when
## it faints (#541, EventEmitted; "" for none), the quest target it is (#625): a content id a
## quest's step names to ask for this one monster, "" for none, and the tile kind it stands on
## (#452). The legend says `a wild monster, always <species id>`, with clauses after it, each once:
## `, wounded`, `, emitting <event name>`, `, the quest target <id>` and, last, `, on <tile kind's
## meaning>`, e.g. `a wild monster, always ombulumo, wounded, on sand` or `a wild monster,
## always ombulumo, the quest target old_toad` (WildSpotPlacements).

## How a named wild monster's legend meaning begins, and the clauses that may follow its species.
const NAMED: String = "a wild monster, always "
const WOUNDED: String = "wounded"
const EMITTING: String = "emitting "
const TARGETED: String = "the quest target "
const ON: String = "on "

var species: String = ""
var wounded: bool = false
var emits: String = ""
var target: String = ""
## The meaning of the tile kind it stands on (`sand`), or "" for ground.
var stands_on: String = ""


## The named wild monster a legend `meaning` places, or null when it places none.
static func read(meaning: String) -> WildSpot:
	if not meaning.begins_with(NAMED):
		return null
	var clauses: PackedStringArray = meaning.trim_prefix(NAMED).split(", ")
	var spot: WildSpot = WildSpot.new()
	spot.species = clauses[0]
	for i: int in range(1, clauses.size()):
		var clause: String = clauses[i]
		var emitted: String = clause.trim_prefix(EMITTING)
		var targeted: String = clause.trim_prefix(TARGETED)
		if clause.begins_with(ON):
			spot.stands_on = ", ".join(clauses.slice(i)).trim_prefix(ON)
			break
		if clause == WOUNDED and not spot.wounded:
			spot.wounded = true
		elif (clause.begins_with(EMITTING)
				and spot.emits.is_empty()
				and Ids.is_id(emitted)):
			spot.emits = emitted
		elif (clause.begins_with(TARGETED)
				and spot.target.is_empty()
				and Ids.is_id(targeted)):
			spot.target = targeted
		else:
			return null
	return spot if Ids.is_id(spot.species) else null
