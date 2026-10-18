class_name PlayerRevived
extends RefCounted
## Event: an ally revived a knocked-down player this tick (#479). The health rule gives them back
## part of their HP.

var entity_id: int


func _init(revived_id: int) -> void:
	entity_id = revived_id
