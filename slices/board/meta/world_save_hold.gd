class_name WorldSaveHold
extends Node
## Something another slice says the world mustn't be saved through (#913), like an open dialog:
## WorldKeeper asks each of its holds before saving, so the board never names what holds it.


## Whether `world` mustn't be saved now.
func holds(_world: World) -> bool:
	return false
