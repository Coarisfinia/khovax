class_name GearSlots
extends RefCounted
## The player's gear (#690): what they own, and what's in each of their gear slots (owner, #223):
## the ward slot (warding gear and totems), the trap slot (spikes) and the throw slot (berries).
## Chests give basic gear (#694); gear has no effect yet. Part of the profile, saved by
## ProfileSave; which slot a piece goes into is content's (GearItem), checked by whoever offers it,
## so a save keeps a piece whose data changed since.

## The slots, in the order they're shown. Saved by name: never rename one.
const SLOTS: Array[String] = ["ward", "trap", "throw"]

## The gear the player owns, by id: how many of each.
var owned: Dictionary[String, int] = {}
## The gear in each slot, by slot: its id. An empty slot isn't here.
var equipped: Dictionary[String, String] = {}


## Puts the gear `gear_id` into `slot`, or empties it when `gear_id` is "". Returns why it can't
## (no such slot, or no piece of it owned that isn't in another slot already), or "", and changes
## nothing when it can't.
func equip(slot: String, gear_id: String) -> String:
	if not SLOTS.has(slot):
		return "no gear slot %s" % slot
	if gear_id.is_empty():
		var _emptied: bool = equipped.erase(slot)
		return ""
	var in_use: int = 0
	for other: String in equipped:
		if other != slot and equipped[other] == gear_id:
			in_use += 1
	if owned.get(gear_id, 0) <= in_use:
		return "no %s left to put into the %s slot" % [gear_id, slot]
	equipped[slot] = gear_id
	return ""
