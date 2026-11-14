class_name TonicDose
extends RefCounted
## What drinking one brew does (#2310, #2311), as the simulation reads it: who it helps, how much it
## mends at once, or which effect over time it gives (TonicEffectsFeature). The tonics' content data
## gives it (DrinkingFactory); Shared's reach and Slow-release's wait are #2312.

## Whether it helps the player themselves (a draught) rather than their out companion (a tonic).
var for_player: bool = false
## The share of its target's full HP it heals at once, in thousandths (Fixed): a Mend's potency,
## 0 for a brew that mends nothing now.
var mend: int = 0
## The effect over time it gives (TonicEffectsFeature.KINDS), "" for none, with its strength in
## thousandths and how long it lasts.
var effect: String = ""
var strength: int = 0
var ticks: int = 0


func _init(helps_player: bool = false, mend_share: int = 0) -> void:
	for_player = helps_player
	mend = mend_share
