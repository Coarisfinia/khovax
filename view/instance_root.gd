class_name InstanceRoot
extends Node3D
## Holds every view of the local player's instance and places them at that instance's place in the
## world (#189, seamless world #155): the simulation keeps each instance in its own coordinates, and
## this one shift turns them into world space. Walking out through an exit moves this node by as
## much as the views' own coordinates move back, so the ground, the figures and the player stay put
## on screen and the camera, which follows the player in world space, never jumps.

@export var driver: GameDriver


func _process(_delta: float) -> void:
	show_state()


## Moves to the local instance's place. Called every frame; tests call it after stepping.
func show_state() -> void:
	position = shift_of(driver)


## Where tile (0, 0) of `game`'s local instance lies in the world; zero without a world.
static func shift_of(game: GameDriver) -> Vector3:
	if game == null or game.world == null:
		return Vector3.ZERO
	return HexLayout.to_world(game.world.offset(game.local_instance_name()))
