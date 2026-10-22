class_name ProfileCompanion
extends Node
## What another slice keeps in the profile's file (#855), like the player's quests: ProfileSave
## hands each of the holder's companions the save it reads, to bring their keys up to date and take
## them over, and asks them what to write beside the profile, so the profile never names what the
## other slices keep there. Like WorldCompanion for the world's file (#827).


## Brings this part's keys in the save `data`, in save format `format`, up to ProfileSave.FORMAT,
## one step at a time, as ProfileSave does its own.
func migrate(_data: Dictionary, _format: int) -> void:
	return


## Takes over this part from the current-format save `data` once the profile's own parts were
## sound; returns why it can't, or "", and keeps what it had when it can't.
func read(_data: Dictionary) -> String:
	return ""


## Starts this part afresh: there's no save yet.
func started() -> void:
	return


## What to write beside the profile in its file (ProfileSave.to_text), by key.
func beside() -> Dictionary:
	return {}
