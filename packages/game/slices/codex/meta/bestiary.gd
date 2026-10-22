class_name Bestiary
extends RefCounted
## What this machine's player has learned about each species (#1173), which their bestiary page
## shows: nothing until they've seen one; its types, abilities and habitat once they've met one in
## a fight; its lore once they've dominated one. Kept in their profile's file (BestiaryKeeper), per
## player, never in the world's state: it's what the player knows, not what the world is.

## How much the player knows about a species, each level all the ones below it too: they've seen
## one, fought one (it struck them or their companion, or their companion struck it), and
## dominated one.
const SEEN: int = 1
const MET: int = 2
const KNOWN: int = 3

## How much the player knows about each species they've seen, by species id.
var levels: Dictionary[String, int] = {}
## The instances each species they've seen was seen in (its habitat as they know it), by species
## id, each blueprint name once, in the order found.
var habitats: Dictionary[String, Array] = {}


## How much the player knows about `species`: 0 before they've seen one.
func level_of(species: String) -> int:
	return levels.get(species, 0)


## Where the player has come across `species`, by blueprint name.
func habitat_of(species: String) -> Array[String]:
	var stored: Array = habitats.get(species, [])
	var found: Array[String] = []
	found.assign(stored)
	return found


## Whether learning `species` at `level` in the instance `where` (a blueprint name, or "") would
## teach the player anything new.
func teaches(species: String, level: int, where: String) -> bool:
	var new_place: bool = not where.is_empty() and not habitat_of(species).has(where)
	return level > level_of(species) or new_place


## Learns `species` at `level`, never forgetting a higher one, in the instance `where` (a blueprint
## name, or "" when it's not known).
func learn(species: String, level: int, where: String) -> void:
	levels[species] = maxi(level, level_of(species))
	if not habitats.has(species):
		habitats[species] = []
	if not where.is_empty() and not habitats[species].has(where):
		habitats[species].append(where)
