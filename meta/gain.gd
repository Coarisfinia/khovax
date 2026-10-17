class_name Gain
extends RefCounted
## What the player just obtained in the world (#37): monsters dominated, materials found, chests
## opened and places reached, the facts quests count too (#184, #339). It's handed to the profile
## the moment it happens, not at the session's end, and saved at once (ProfileKeeper), so a crash
## mid-session never loses a domination (owner, #73).

var dominated_species: Array[String] = []
var materials: Dictionary[String, int] = {}
## Treasure chests this player got loot from, which only quests count.
var chests_opened: int = 0
## The places this player stepped into (#339), by id, which only quests count.
var places_reached: Array[String] = []
