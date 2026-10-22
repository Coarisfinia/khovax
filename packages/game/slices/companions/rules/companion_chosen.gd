class_name CompanionChosen
extends RefCounted
## Event: a player chose another of their carried monsters as their companion this tick (#55), or
## had one chosen for them when theirs fainted (#597). Whoever raises it has already made it their
## companion in their party (CompanionParty.choose); the world carries that into every instance once
## this one stepped, and the companion feature then sends the old one off and lets the new one join
## them.

var slot: int
## Its place in the player's carried order, from 0 (CompanionParty.carried).
var place: int


func _init(player_slot: int, carried_place: int) -> void:
	slot = player_slot
	place = carried_place
