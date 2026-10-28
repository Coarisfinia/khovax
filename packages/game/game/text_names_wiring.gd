extends Node
## Hands the text tags (#733) the reader of their names once at start (#1612): `texts` comes before
## the content slices, so it can't read the names itself, and game/ wires them. An autoload, so a
## run without the main scene (the tests, the tools) gets the names too.


func _init() -> void:
	TextNames.wire()
