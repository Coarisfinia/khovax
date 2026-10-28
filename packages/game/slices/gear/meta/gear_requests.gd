class_name GearRequests
extends RefCounted
## Tells the world what's in the player's gear slots (#818). The gear is kept in their profile,
## outside the simulation, so a change the simulation needs to know rides to it as a request from
## the profile's outbox (#771), posted in the same change to the profile as the gear's, so a save
## never has one without the other. The simulation needs to know the trap slot's spikes
## (SpikesFeature, OutboxEntry.TRAP), which it keeps in the player's world store, and whether the
## ward slot's gear keeps the passives on (#617, CompanionPassives, OutboxEntry.PASSIVES_KEPT).


## Posts the request for what's now in the slot `slot` of `gear` to `outbox`, if the simulation
## needs to know it; returns whether it posted one.
static func post_change(gear: GearSlots, outbox: Outbox, slot: String) -> bool:
	if slot == GearItem.TRAP:
		var _trap: OutboxEntry = outbox.post(OutboxEntry.TRAP, _trap_of(gear))
		return true
	if slot == GearItem.WARD:
		var _kept: OutboxEntry = outbox.post(OutboxEntry.PASSIVES_KEPT, _kept_of(gear))
		return true
	return false


## Posts the requests for the gear `gear` to `outbox` that the world's `store` (the player's world
## store) once the outbox's waiting requests are applied isn't: for a world new to it, or one that
## missed a change; returns whether it posted any.
static func catch_up(gear: GearSlots, outbox: Outbox, store: PlayerStore) -> bool:
	var trap: int = SpikesFeature.trap_of(store.stored(SpikesFeature.ID))
	var kept: int = 1 if CompanionPassives.kept(store.stored(CompanionFeature.ID)) else 0
	for request: OutboxEntry in outbox.entries:
		if request.kind == OutboxEntry.TRAP:
			trap = request.data
		elif request.kind == OutboxEntry.PASSIVES_KEPT:
			kept = request.data
	var posted: bool = false
	if trap != _trap_of(gear):
		var _trap: OutboxEntry = outbox.post(OutboxEntry.TRAP, _trap_of(gear))
		posted = true
	if kept != _kept_of(gear):
		var _kept: OutboxEntry = outbox.post(OutboxEntry.PASSIVES_KEPT, _kept_of(gear))
		posted = true
	return posted


## The code of the gear in the trap slot of `gear` (SpikesFeature.code_of), or CommandCodes.NONE.
static func _trap_of(gear: GearSlots) -> int:
	var trap_id: String = gear.equipped.get(GearItem.TRAP, "")
	return SpikesFeature.code_of(trap_id)


## 1 when the gear in the ward slot of `gear` keeps the passives on (GearItem.keeps_passives), 0
## when it doesn't or the slot is empty.
static func _kept_of(gear: GearSlots) -> int:
	var ward: GearItem = GearContent.cached().items.get(gear.equipped.get(GearItem.WARD, ""))
	return 1 if ward != null and ward.keeps_passives else 0
