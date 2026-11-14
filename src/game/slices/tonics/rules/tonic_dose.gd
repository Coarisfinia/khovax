class_name TonicDose
extends RefCounted
## What drinking one brew does (#2310), as the simulation reads it: who it helps and how much it
## mends at once. The tonics' content data gives it (DrinkingFactory); the timed effects, Shared's
## reach and Slow-release's wait are #2311 and #2312.

## Whether it helps the player themselves (a draught) rather than their out companion (a tonic).
var for_player: bool = false
## The share of its target's full HP it heals at once, in thousandths (Fixed): a Mend's potency,
## 0 for a brew that mends nothing now.
var mend: int = 0


func _init(helps_player: bool = false, mend_share: int = 0) -> void:
	for_player = helps_player
	mend = mend_share
