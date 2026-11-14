class_name DrinkOffer
extends Node
## What LocalInput asks before a tonic or a draught is drunk (#2313): which ones a player may pick.
## The drink's tie (DrinkTie) answers from this machine's player's profile; the controls only name
## this, so they never reach the tonics or the profile, which come after them (#851).


## The ids of the tonics and draughts the player in `slot` in `state` may pick to drink now, in the
## order to pick them: none while the player holds none.
func offered(_state: GameState, _slot: int) -> PackedStringArray:
	return PackedStringArray()
