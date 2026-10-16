class_name Species
extends RefCounted
## What a monster is, captured or not (a `species`, #45), read from content data (#72): its types,
## base stats, wild archetype and its three abilities (#222). Everything here is integers and ids,
## ready for the simulation.

const ARCHETYPES: Array[String] = ["charger", "burrower", "flyer", "swarm", "pusher"]

var id: String = ""
## One or two types (#68); dual types are the norm later in the game.
var types: Array[String] = []
var hp: int = 0
var strength: int = 0
## Higher is faster (#222).
var speed: int = 0
## How it behaves as a wild monster against rings: one of ARCHETYPES (#222).
var archetype: String = ""
## Its abilities' ids (data/abilities/): its special attack and its two passives (#222).
var special: String = ""
var player_passive: String = ""
var self_passive: String = ""


## Reads its speed, archetype and abilities from a species file's `data`; returns why it can't, or
## "". Whether the abilities exist is checked against the ability data (Content).
func read_kit(data: Dictionary) -> String:
	speed = Content.amount(data.get("speed"))
	archetype = Content.text_of(data.get("archetype"))
	special = Content.text_of(data.get("special"))
	player_passive = Content.text_of(data.get("player_passive"))
	self_passive = Content.text_of(data.get("self_passive"))
	if speed < 1:
		return "speed is a whole number from 1 to %d" % Fixed.MAX_AMOUNT
	if not ARCHETYPES.has(archetype):
		return "its archetype is one of %s" % [ARCHETYPES]
	for ability: String in [special, player_passive, self_passive]:
		if not Content.is_id(ability):
			return "it names a special and two passives by their ids"
	return ""
