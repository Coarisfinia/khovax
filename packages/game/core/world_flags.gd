class_name WorldFlags
extends RefCounted
## The world's flags (#529) and the variants they choose, split out of World (#828). A fresh world
## starts with its source's flags (#637), and they choose each blueprint's variant
## (`InstanceSource.variant`): setting or clearing one purges every loaded instance whose variant it
## changes, once nobody is in it, so it comes back from its new variant and no player sees it
## change. Any rule can raise a named event (EventEmitted, #541), which sets the flag EVENT_FLAG +
## its name, so whatever happens in an instance can change the world: a story beat does, and the
## first time it sets its flag the world raises that it changed (WorldChanged, #499). A rule can
## also replace a kind of flag (FlagReplaced, #638), clearing the others of its kind in the same
## tick as it sets its own, like a territory changing hands. It keeps nothing: the world is handed
## in, as to WorldTravel, and keeps the flags and variants itself (`World.flags`, `World.variants`).
## Deterministic, like everything in core/.

## What the flag a named event sets begins with (#541): EVENT_EMITTED_<the event's name>.
const EVENT_FLAG: String = "EVENT_EMITTED_"


## Sets the flag `flag` in `world` (#529), or clears it when `on` is false: for story beats and the
## rules that change the world. Every loaded instance whose variant that changes is outdated: purged
## once nobody is in it, or as someone walks in or is sent to the spawn. The starting instance too
## (#727), which is loaded again at once from its new variant.
static func set_flag(world: World, flag: String, on: bool = true) -> void:
	if world.flags.has(flag) == on:
		return
	if on:
		world.flags.append(flag)
		world.flags.sort()
	else:
		world.flags.erase(flag)
	# The instances not loaded may now have other regions.
	world.lay_out_again()


## The variant of the blueprint `instance_name` the flags of `world` choose now (#529).
static func chosen_variant(world: World, instance_name: String) -> String:
	return world.source.variant(instance_name, world.flags)


## The variant of the blueprint `instance_name` as it is in `world`: the one it was loaded from
## while it's loaded, else the one the flags choose. Its region is read from it.
static func variant_of(world: World, instance_name: String) -> String:
	if world.variants.has(instance_name):
		return world.variants[instance_name]
	return chosen_variant(world, instance_name)


## Whether the loaded instance `instance_name` of `world` was loaded from another variant than the
## flags choose now.
static func outdated(world: World, instance_name: String) -> bool:
	return variant_of(world, instance_name) != chosen_variant(world, instance_name)


## Sets the flag of every event in `emitted` (#541), then carries out every flag replacement in
## `replaced` (#638), each raised this tick in `world`, in the order raised: once every instance has
## stepped, so no instance's step sees another's events change the world mid-tick; before anyone
## walks through an exit, so whoever walks into an instance one outdated finds its new variant.
static func take(world: World, emitted: Array[EventEmitted], replaced: Array[FlagReplaced]) -> void:
	_set_emitted(world, emitted)
	_replace(world, replaced)


## Sets the flag of every event in `emitted`. The first time an event sets its flag, the world
## raises that it changed (WorldChanged, #499).
static func _set_emitted(world: World, emitted: Array[EventEmitted]) -> void:
	for event: EventEmitted in emitted:
		var flag: String = EVENT_FLAG + event.event_name
		if not world.flags.has(flag):
			set_flag(world, flag)
			world.events.append(_changed_event(event.event_name, flag))


## Carries out every flag replacement in `replaced`: each clears every flag of its kind but its own,
## then sets it.
static func _replace(world: World, replaced: Array[FlagReplaced]) -> void:
	for event: FlagReplaced in replaced:
		for held: String in world.flags.duplicate():
			if held.begins_with(event.kind) and held != event.flag:
				set_flag(world, held, false)
		set_flag(world, event.flag)


## That the event `event_name` changed the world by setting `flag`.
static func _changed_event(event_name: String, flag: String) -> WorldChanged:
	return WorldChanged.new(event_name, flag)
