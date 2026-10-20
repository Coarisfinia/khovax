class_name Gain
extends RefCounted
## What the player just obtained in the world (#37): monsters dominated and materials and gear found
## (#694). What it means to their quests is counted apart (QuestTie, #817).
## Loot is obtained once it's the player's (#686): loot landing in their missed-loot chest (#242)
## isn't obtained yet, and taking it out is, like taking it from their own chest (#293), so only
## taking it out hands a Gain.
## It's handed to the profile the moment it happens, not at the session's end, and saved at once
## (ProfileKeeper), so a crash mid-session never loses a domination (owner, #73).

var dominated_species: Array[String] = []
## The short id of each dominated monster (#700), in the same order. A monster this lacks one for
## gets a stand-in (ShortId.stand_in).
var dominated_short_ids: Array[String] = []
var materials: Dictionary[String, int] = {}
## Gear found (#694), by id: how many of each.
var gear: Dictionary[String, int] = {}


## Whether it holds nothing at all.
func is_empty() -> bool:
	return dominated_species.is_empty() and materials.is_empty() and gear.is_empty()
