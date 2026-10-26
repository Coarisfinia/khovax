class_name Standings
extends RefCounted
## The player's standing with each faction (#483, named in #482): how the faction sees them, from
## LOWEST to HIGHEST, each step but neutral (0) a rank the faction names itself (Faction.rank_name).
## Neutral with every faction until something moves it. Part of the profile, saved by ProfileSave.
## Gaining rank with a faction costs half that gain with each of its enemies (#1310, `align`).

const LOWEST: int = -5
const HIGHEST: int = 5

## The standing with each faction the player isn't neutral with, by faction id.
var by_faction: Dictionary[String, int] = {}
## The factions the player has lost half a rank with and not yet a whole one (#1310): a gain costs
## half of it with each enemy, and the half left over waits here until a second half makes a whole
## rank lost. Sorted, each once.
var half_lost: Array[String] = []


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


## Moves the standing with `faction` by `by`, as `change` does, and when that gains rank, loses half
## the rank gained with each of its enemies (#1310), counting halves in `half_lost`: two halves
## lost with a faction make one rank. Losing rank costs nothing with its enemies. A faction allied
## until the postgame (#1324) the player has joined (a rank above neutral) keeps them at its first
## rank at least; nothing marks the postgame yet (#1333), so that holds for now.
func align(faction: Faction, by: int) -> void:
	var before: int = of(faction.id)
	var lowest: int = 1 if faction.allied_until_postgame and before >= 1 else LOWEST
	var _moved: String = change(faction.id, maxi(by, lowest - before))
	var gained: int = of(faction.id) - before
	if gained <= 0:
		return
	for enemy: String in faction.enemies:
		_lose_halves(enemy, gained)


## Loses `halves` half ranks with `faction` (#1310), the half left over kept in `half_lost`.
func _lose_halves(faction: String, halves: int) -> void:
	var total: int = halves + (1 if half_lost.has(faction) else 0)
	half_lost.erase(faction)
	if total % 2 == 1:
		half_lost.append(faction)
		half_lost.sort()
	var _lost: String = change(faction, -Fixed.div_floor(total, 2))
