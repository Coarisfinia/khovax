class_name InstanceSource
extends RefCounted
## What the World loads its instances from, by name (#396): handed to it, so the core never names
## the blueprints, which put the slices' features together. BlueprintSource is the game's; this one
## knows no instance.


## Whether an instance of this name can be loaded.
func exists(_instance_name: String) -> bool:
	return false


## A new instance of the named one for `seed_value`, with `players` players in slots 0 and up, or
## null when it can't load.
func create(_instance_name: String, _seed_value: int, _players: int) -> GameState:
	return null


## The named instance's region for `seed_value`, without loading the instance; its `problem` says
## what's wrong.
func region_of(instance_name: String, _seed_value: int) -> Region:
	var unknown: Region = Region.new()
	unknown.problem = "unknown instance " + instance_name
	return unknown
