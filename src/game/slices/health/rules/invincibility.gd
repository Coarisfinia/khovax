class_name Invincibility
extends RefCounted
## Making a player invincible from a session's start (#1142, the `--invincible` launch option):
## their world store keeps HealthFeature's INVINCIBLE entry, so it holds in every instance, and
## HealthFeature.is_invincible reads it there. Apart from HealthFeature, which keeps the HP.


## Makes the player in `slot` of `world` invincible: no hit hurts them, so they're never knocked
## down or sent to the spawn, while wild monsters still pick them as a target, unlike a shielded
## one.
static func make(world: World, slot: int) -> void:
	world.set_entry(slot, HealthFeature.ID, { HealthFeature.INVINCIBLE: 1 })
