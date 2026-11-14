class_name WildSpot
extends RefCounted
## What a region piece's legend says about a named wild monster's spot (#133), beyond where it is:
## the species it names, whether its monster starts wounded (#389), the event its monster emits when
## it faints (#541, EventEmitted; "" for none), the quest target it is (#625): a content id a
## quest's step names to ask for this one monster, "" for none, and the tile kind it stands on
## (#452), and whether it's a boss (#2410, BossSpecialFeature). The legend says `a wild monster,
## always <species id>`, with clauses after it, each once: `, wounded`, `, emitting <event name>`,
## `, the quest target <id>`, `, a boss` and, last, `, on <tile kind's meaning>`, e.g. `a wild
## monster, always ombulumo, wounded, on sand` or `a wild monster,
## always ombulumo, the quest target old_toad` (WildSpotPlacements).

## How a named wild monster's legend meaning begins, and the clauses that may follow its species.
const NAMED: String = "a wild monster, always "
const WOUNDED: String = "wounded"
const EMITTING: String = "emitting "
const TARGETED: String = "the quest target "
const BOSS: String = "a boss"
const ON: String = "on "
## `, escaping at <percent>%` (#2411, EscapeFeature): once its HP, or a seal around it, is down to
## that share, from 1% to 99%, it escapes instead of fainting or being dominated.
const ESCAPING: String = "escaping at "
const PERCENT: String = "%"
const WHOLE: int = 100

var species: String = ""
var wounded: bool = false
var emits: String = ""
var target: String = ""
var boss: bool = false
## The meaning of the tile kind it stands on (`sand`), or "" for ground.
var stands_on: String = ""
## The share of the way left where it escapes (`, escaping at`), in thousandths (Fixed), or 0 when
## it never does.
var escapes_at: int = 0


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
		elif clause == BOSS and not spot.boss:
			spot.boss = true
		elif (clause.begins_with(EMITTING)
				and spot.emits.is_empty()
				and Ids.is_id(emitted)):
			spot.emits = emitted
		elif (clause.begins_with(TARGETED)
				and spot.target.is_empty()
				and Ids.is_id(targeted)):
			spot.target = targeted
		elif clause.begins_with(ESCAPING) and spot.escapes_at == 0:
			spot.escapes_at = _share_of(clause.trim_prefix(ESCAPING))
			if spot.escapes_at == 0:
				return null
		else:
			return null
	return spot if Ids.is_id(spot.species) else null


## The share a `percent` like `25%` gives, in thousandths, or 0 when it isn't a whole percent from 1
## to 99.
static func _share_of(percent: String) -> int:
	var number: String = percent.trim_suffix(PERCENT)
	if (not percent.ends_with(PERCENT)
			or not number.is_valid_int()
			or number != str(number.to_int())):
		return 0
	var share: int = number.to_int()
	return Fixed.ratio(share, WHOLE) if share > 0 and share < WHOLE else 0
