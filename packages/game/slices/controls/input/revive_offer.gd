class_name ReviveOffer
extends Node
## What LocalInput asks before a revive item is used (#656, #780): which fainted monsters of a
## player one may go to now. The revive items' tie (ReviveTie) answers from this machine's player's
## profile; the controls only name this, so they never reach the revive items or the profile, which
## come after them (#851).


## The short ids of the fainted monsters of the player in `slot` in `state` a revive item may go to
## now, in the order to pick them: none while the player holds no item.
func offered(_state: GameState, _slot: int) -> PackedStringArray:
	return PackedStringArray()
