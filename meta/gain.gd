class_name Gain
extends RefCounted
## What the player just obtained in the world (#37): monsters caught, materials found and chests
## opened, the facts quests count too (#184). It's handed to the profile the moment it happens, not
## at the session's end, and saved at once (ProfileKeeper), so a crash mid-session never loses a
## catch (owner, #73).

var caught_species: Array[String] = []
var materials: Dictionary[String, int] = {}
## Treasure chests this player got loot from, which only quests count.
var chests_opened: int = 0
