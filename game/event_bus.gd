class_name EventBus
extends Node
## The run's events, out of the simulation to whoever listens (#184): after each tick, the driver's
## events are queued and, once a frame, handed to the subscribers of their topic, publish/subscribe.
## The simulation doesn't know who listens, and no subscriber holds up a tick. A topic is the
## event's class name (`&"WildMonsterCaught"`). Events only flow out: a subscriber never changes the
## run,
## since anything that matters inside it is a rule in the simulation (#26). Views keep the driver's
## `ticked` signal, since their effects play in step with the ticks.

@export var driver: GameDriver

## The events not yet handed out, in the order the ticks raised them.
var queued: Array[RefCounted] = []
## Each topic's subscribers, in the order they subscribed.
var _subscribers: Dictionary[StringName, Array] = {}


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	flush()


## Hands every event on `topic` to `subscriber`, which takes the event.
func subscribe(topic: StringName, subscriber: Callable) -> void:
	if not _subscribers.has(topic):
		_subscribers[topic] = []
	_subscribers[topic].append(subscriber)


## Hands every queued event to its topic's subscribers, in order. Called once a frame; tests call it
## to deliver at once.
func flush() -> void:
	var events: Array[RefCounted] = queued
	queued = []
	for event: RefCounted in events:
		for subscriber: Callable in _subscribers.get(topic_of(event), []):
			subscriber.call(event)


## The topic an event is published on: its class name.
static func topic_of(event: RefCounted) -> StringName:
	var script: Script = event.get_script()
	return script.get_global_name() if script != null else &""


func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	queued.append_array(events)
