class_name CharacterProfile
extends RefCounted
## What this machine's player's profile does for the menu's Character tab (#1613), handed in by the
## profile (ProfilePanelsTie), whose slice comes after the menu's; each stays unset without a
## profile, and the tab then shows none and keeps nothing.

## Keeps a personal color (0xRRGGBB), and hands it back to Auto.
var keep_color: Callable = Callable()
var keep_auto: Callable = Callable()
## Whether the player chose a color of their own rather than Auto.
var chose_color: Callable = Callable()
## Keeps a typed name, returning why it was refused, or ""; and gives the name kept.
var keep_name: Callable = Callable()
var kept_name: Callable = Callable()
## Takes the node of a monster's development web (its short id, the node).
var keep_node: Callable = Callable()
## Ascends a monster (its short id).
var keep_ascension: Callable = Callable()
