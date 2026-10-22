class_name GearRequests
extends RefCounted
## Tells the world what's in the player's gear slots (#818). The gear is kept in their profile,
## outside the simulation, so a change the simulation needs to know rides to it as a request from
## the profile's outbox (#771), posted in the same change to the profile as the gear's, so a save
## never has one without the other. Only the trap slot's spikes count in the simulation yet
## (SpikesFeature, OutboxEntry.TRAP), which keeps them in the player's world store.


## Posts the request for what's now in the slot `slot` of `gear` to `outbox`, if the simulation
## needs to know it; returns whether it posted one.
static func post_change(gear: GearSlots, outbox: Outbox, slot: String) -> bool:
	if slot != GearItem.TRAP:
		return false
	var _posted: OutboxEntry = outbox.post(OutboxEntry.TRAP, _trap_of(gear))
	return true


## Posts the request for the trap of `gear` to `outbox` when the world's, `stored` (the player's
## entry of SpikesFeature in their world store) once the outbox's waiting requests are applied,
## isn't it: for a world new to it, or one that missed a change; returns whether it posted one.
static func catch_up(gear: GearSlots, outbox: Outbox, stored: Dictionary) -> bool:
	var trap: int = SpikesFeature.trap_of(stored)
	for request: OutboxEntry in outbox.entries:
		if request.kind == OutboxEntry.TRAP:
			trap = request.data
	if trap == _trap_of(gear):
		return false
	var _posted: OutboxEntry = outbox.post(OutboxEntry.TRAP, _trap_of(gear))
	return true


## The code of the gear in the trap slot of `gear` (SpikesFeature.code_of), or CommandCodes.NONE.
static func _trap_of(gear: GearSlots) -> int:
	var trap_id: String = gear.equipped.get(GearItem.TRAP, "")
	return SpikesFeature.code_of(trap_id)
