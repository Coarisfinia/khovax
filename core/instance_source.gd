class_name InstanceSource
extends RefCounted
## What the World loads its instances from, by name (#396): handed to it, so the core never names
## the blueprints, which put the slices' features together. BlueprintSource is the game's; this one
## knows no instance.


## Whether an instance of this name can be loaded.
func exists(_instance_name: String) -> bool:
	return false


## Whether everything the named instance loads from is already read (#816), so loading it reads no
## files. Always, until the content cache is filled in the background (part 3 of #816): until then,
## each reader reads its files the first time it's asked.
func cached(_instance_name: String) -> bool:
	return true


## The flags a fresh world starts with (#637), before it loads any instance: e.g. who holds which
## instance.
func starting_flags() -> Array[String]:
	return []


## The variant of the named instance that the world's `flags` (sorted) choose (#529), or "" for
## its plain one.
func variant(_instance_name: String, _flags: Array[String]) -> String:
	return ""


## A new instance of the named one's `variant` for `seed_value`, with `players` players in slots 0
## and up, or null when it can't load.
func create(
	_instance_name: String,
	_seed_value: int,
	_players: int,
	_variant: String,
) -> GameState:
	return null


## The region of the named instance's `variant` for `seed_value`, without loading the instance;
## its `problem` says what's wrong.
func region_of(instance_name: String, _seed_value: int, _variant: String) -> Region:
	var unknown: Region = Region.new()
	unknown.problem = "unknown instance " + instance_name
	return unknown
