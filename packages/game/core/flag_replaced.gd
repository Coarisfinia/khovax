class_name FlagReplaced
extends RefCounted
## Event: a rule replaces a kind of world flag this tick (#638), like who holds an instance
## (Territory): after every instance has stepped, the World clears every flag that begins with
## `kind` but `flag`, and sets `flag`, in the same tick, so the world never holds two of the kind.

## What every flag of the kind begins with; `flag` begins with it too.
var kind: String
## The flag that replaces them.
var flag: String


func _init(flag_kind: String, replacing: String) -> void:
	kind = flag_kind
	flag = replacing
