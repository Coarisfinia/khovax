class_name SessionProfile
extends Node
## What the slices before the profile read of this machine's player's profile through the session
## (Session.holder, #1663): their personal color and the path they lean toward. The profile's
## ProfileHolder is one; slices after the profile cast to it for the rest, so the board never names
## a later slice (packages/game-checks/import_rules.py). This one has no profile: Auto and no
## leaning.


## This machine's player's chosen personal color, as 0xRRGGBB; only meaningful while
## `chose_personal_color` holds.
func personal_color() -> int:
	return 0


## Whether this machine's player chose a personal color (#391) rather than Auto.
func chose_personal_color() -> bool:
	return false


## The path this machine's player leans toward (PathLeaning.toward): their companion's eyes show it
## (#1063).
func leaning() -> String:
	return PathMark.NONE
