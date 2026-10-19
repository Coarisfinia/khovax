class_name EventEmitted
extends RefCounted
## Event: something named happened in an instance this tick (#541), raised by whichever rule saw it
## happen, next to that rule's own event. It is how anything in an instance changes the world:
## after every instance has stepped, the world sets the flag World.EVENT_FLAG + `event_name`
## (EVENT_EMITTED_<name>), once however often it's raised, and the flags choose blueprints'
## variants (#529). The first use: a wild monster a region names an event for raises it when it
## faints (WildMonsterFeature), e.g. the corrupted glade's corrupting monster, which purifies it.

## The event's name, an identifier: letters, digits and `_`.
var event_name: String


func _init(named: String) -> void:
	event_name = named
