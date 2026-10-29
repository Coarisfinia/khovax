class_name SessionInput
extends Node
## What the slices see of this machine's player's input through the session (Session.input): whose
## slot it plays, whether the game hears it, and what it focuses. The controls' LocalInput is the
## one that turns devices into commands; the board only names this, so it never reaches the
## controls, which come after it (#851, packages/game-checks/import_rules.py).

## The player slot this machine's player controls.
@export_range(0, GameState.MAX_PLAYERS - 1) var slot: int = 0

## Whether the game hears no input, as while the menu is open over it (#362): the player stands.
var blocked: bool = false
## Whether a dialog is open on screen (#635): the player stands, as while blocked, and the d-pad,
## the stick and A choose on the dialog screen instead. Its own flag, so the menu opening and
## closing over a dialog doesn't let the player walk off.
var in_dialog: bool = false
## The wild monster the player focuses (#436), by entity id, or Command.NO_FOCUS; the special
## attack strikes it. Views read it to mark it.
var focus: int = Command.NO_FOCUS
