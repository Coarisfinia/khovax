class_name Standings
extends RefCounted
## The player's standing with each faction (#483, named in #482): how the faction sees them, from
## LOWEST to HIGHEST, each step but neutral (0) a rank the faction names itself (Faction.rank_name).
## Neutral with every faction until something moves it. Part of the profile, saved by ProfileSave.

const LOWEST: int = -5
const HIGHEST: int = 5

## The standing with each faction the player isn't neutral with, by faction id.
var by_faction: Dictionary[String, int] = {}


## The standing with `faction`: neutral (0) when nothing has moved it.
func of(faction: String) -> int:
	return by_faction.get(faction, 0)


## Moves the standing with `faction` by `by`, held between LOWEST and HIGHEST, so going past an end
## stays at it and the way back is never longer than the scale. Returns why it can't (the faction's
## id isn't one), or "", and changes nothing when it can't.
func change(faction: String, by: int) -> String:
	if not Content.is_id(faction):
		return "faction %s has no valid id" % faction
	# Clamped first too, so no change is large enough to overflow.
	var step: int = clampi(by, LOWEST - HIGHEST, HIGHEST - LOWEST)
	var standing: int = clampi(of(faction) + step, LOWEST, HIGHEST)
	if standing == 0:
		var _neutral: bool = by_faction.erase(faction)
	else:
		by_faction[faction] = standing
	return ""
