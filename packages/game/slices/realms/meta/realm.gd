class_name Realm
extends RefCounted
## A realm (#865): an assortment of instances, each of which builds itself from its region pieces.
## Its file draws the instances as a picture of where they lie relative to each other
## (RealmDocument), and instances drawn side by side are joined: an exit leads to the instance
## drawn beside its own on the exit's side. Code names no realm and no instance: both are ids read
## from the files.

## The realm's id, its file's name.
var id: String = ""
## Each instance's id (its blueprint's), by the tile it's drawn on, in reading order.
var instances: Dictionary[Vector2i, String] = {}
## The instance the players start in, if this realm is where the world starts, or "".
var start: String = ""
## Its codex entry (#959): a short text about it and where its name comes from.
var codex_entry: String = ""
## What its name means, hand-written (#959), e.g. "high land, heart land".
var codex_gloss: String = ""
## How its instances look by day and at night (#1247), each a whole 0xRRGGBB: the sun's light and
## the ambient light. Every realm keeps the world's one clock (DayClock); only this look is its
## own, so a realm whose day and night look alike hides the hour from the player.
var day_light: int = 0
var day_ambience: int = 0
var night_light: int = 0
var night_ambience: int = 0
## Why the realm's file can't be read, or "".
var problem: String = ""


## Whether the realm draws the instance `instance_id`.
func has(instance_id: String) -> bool:
	return instances.values().has(instance_id)


## The instance drawn beside `instance_id` on side `side` (an index into Hex.DIRECTIONS), or "".
func beside(instance_id: String, side: int) -> String:
	if not has(instance_id):
		return ""
	var tile: Vector2i = instances.find_key(instance_id)
	return instances.get(tile + Hex.DIRECTIONS[side], "")
