class_name Species
extends RefCounted
## What a monster is, captured or not (a `species`, #45), read from content data (#72): its types
## and base stats. Everything here is integers and ids, ready for the simulation.

var id: String = ""
## One or two types (#68); dual types are the norm later in the game.
var types: Array[String] = []
var hp: int = 0
var strength: int = 0
