extends RefCounted
## Planted for #1865 (check first, #1747): each line gets around the resolver in a way the check
## must catch. Removed with the fix.


func planted(icon: String) -> Array:
	return [
		load("uid://b1865planted"),
		load("res://assets/game-icons/" + icon + ".svg"),
	]


func _init() -> void:
	planted(name_of_icon())


func name_of_icon() -> String:
	return get_class()
