class_name EventBus
extends Node
## The world's events, out of the simulation to whoever listens (#184): after each tick, the
## driver's events are queued and, once a frame, handed to the subscribers of their topic,
## publish/subscribe. The simulation doesn't know who listens, and no subscriber holds up a tick. A
## topic is the event's class, subscribed to by the class itself (`WildMonsterDominated`), so a
## renamed event class fails where it's subscribed to instead of going quiet (#829). Events only
## flow out: a subscriber never changes the world, since anything that matters inside it is a rule
## in the simulation (#26). Each event is known by the instance that raised it (#769) until it's
## handed out. Views keep the driver's `ticked` signal, since their effects play in step with the
## ticks.

@export var driver: Session

## The events not yet handed out, in the order the ticks raised them.
var queued: Array[RefCounted] = []
## The instance each queued event was raised in, by blueprint name; the world's own have none.
var _instances: Dictionary[RefCounted, String] = {}
## Each topic's subscribers, in the order they subscribed.
var _subscribers: Dictionary[StringName, Array] = {}
## Whether a flush is under way.
var _flushing: bool = false


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_on_ticked)


func _process(_delta: float) -> void:
	flush()


## Hands every event of `event_class` (a `class_name` script, named by the class itself) to
## `subscriber`, which takes the event. A script without a class name has no topic and is refused.
func subscribe(event_class: Script, subscriber: Callable) -> void:
	var topic: StringName = event_class.get_global_name()
	if topic.is_empty():
		push_error("an event bus topic needs a class_name: %s" % [event_class.resource_path])
		return
	if not _subscribers.has(topic):
		_subscribers[topic] = []
	_subscribers[topic].append(subscriber)


## Hands every queued event to its topic's subscribers, oldest first, until none is left: events a
## subscriber raises meanwhile queue behind. A flush asked for during one is part of it. Each event
## goes to the subscribers its topic had when it came up, and a freed subscriber is skipped. Called
## once a frame; tests call it to deliver at once.
func flush() -> void:
	if _flushing:
		return
	_flushing = true
	while not queued.is_empty():
		var event: RefCounted = queued.pop_front()
		var subscribed: Array = _subscribers.get(topic_of(event), [])
		for subscriber: Callable in subscribed.duplicate():
			if subscriber.is_valid():
				subscriber.call(event)
		var _handed: bool = _instances.erase(event)
	_flushing = false


## The blueprint name of the instance a queued event, or the one being handed out, was raised in,
## or "" for the world's own events (InstanceEntered, WorldChanged), which no instance raised.
func instance_of(event: RefCounted) -> String:
	return _instances.get(event, "")


## The topic an event is published on: its class name.
static func topic_of(event: RefCounted) -> StringName:
	var script: Script = event.get_script()
	return script.get_global_name() if script != null else &""


## Queues a tick's events, each known by the instance whose events it is: a stepped instance keeps
## them until its next tick.
func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	queued.append_array(events)
	if driver.world == null:
		return
	for instance_name: String in driver.world.sorted_names():
		for event: RefCounted in driver.world.instances[instance_name].events:
			if events.has(event):
				_instances[event] = instance_name
