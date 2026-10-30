extends RefCounted
## Planted for #1865 (check first, #1747): each line gets around the resolver in a way the check
## must catch. Removed with the fix.


func planted(icon: String) -> Array:
	return [
		load("uid://b1865planted"),
		load("../assets/game-icons/planted.svg"),
		load("res://assets/game-icons/" + icon + ".svg"),
	]
