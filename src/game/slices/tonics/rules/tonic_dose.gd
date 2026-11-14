class_name TonicDose
extends RefCounted
## What drinking one brew does (#2310, #2311), as the simulation reads it: who it helps, how much it
## mends at once, or which effect over time it gives (TonicEffectsFeature). The tonics' content data
## gives it (DrinkingFactory), and how long it waits before it starts and how far it reaches
## (#2312).

## Whether it helps the player themselves (a draught) rather than their out companion (a tonic).
var for_player: bool = false
## The share of its target's full HP it heals at once (or once its wait has passed), in
## thousandths (Fixed): a Mend's potency, 0 for a brew that mends nothing.
var mend: int = 0
## The effect over time it gives (TonicEffectsFeature.KINDS), "" for none, with its strength in
## thousandths and how long it lasts.
var effect: String = ""
var strength: int = 0
var ticks: int = 0
## The ticks a Slow-release brew waits before its Mend lands or its effect starts, 0 for none.
var waits: int = 0
## How far, in tiles, a Shared brew reaches from its drinker's own target to the same target of
## every other player, 0 for no other.
var reach: int = 0


func _init(helps_player: bool = false, mend_share: int = 0) -> void:
	for_player = helps_player
	mend = mend_share
