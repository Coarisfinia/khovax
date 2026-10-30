extends RefCounted
## Planted for #1865 (check first, #1747): each line gets around the resolver in a way the check
## must catch. Removed with the fix.

var found: Array = []


func _init() -> void:
	planted(get_class())


func planted(icon: String) -> void:
	found = [
		load("uid://b1865planted"),
		load("res://assets/game-icons/" + icon + ".svg"),
	]
