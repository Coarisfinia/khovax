class_name CommandSchedule
extends RefCounted
## Lockstep's command book (#38): every player slot's command for every coming tick. A tick runs
## only once each slot's command for it is known, so every machine steps the same ticks with the
## same commands. Commands go `delay` ticks ahead, so a network has time to deliver them; locally
## the delay is 0 and everything is known at once. A command once put is final, as it would be once
## sent to the other players.

var players: int = 1
var delay: int = 0
## The commands known so far, by tick: one entry per slot, null while unknown.
var _ticks: Dictionary[int, Array] = {}


## A schedule for `player_count` slots and `input_delay` ticks of delay. The first `input_delay`
## ticks come before any command could arrive, so every slot stands still in them.
func _init(player_count: int, input_delay: int) -> void:
	players = player_count
	delay = input_delay
	var idle: Command = Command.new()
	for tick: int in range(1, input_delay + 1):
		for slot: int in players:
			put(tick, slot, idle)


## Puts `slot`'s command for `tick`. Ignored when that command is already known (it's final) or
## the slot doesn't exist.
func put(tick: int, slot: int, command: Command) -> void:
	if slot < 0 or slot >= players or has(tick, slot):
		return
	if not _ticks.has(tick):
		var unknown: Array = []
		for _slot: int in players:
			unknown.append(null)
		_ticks[tick] = unknown
	_ticks[tick][slot] = command


func has(tick: int, slot: int) -> bool:
	if slot < 0 or slot >= players:
		return false
	return _ticks.has(tick) and _ticks[tick][slot] != null


## Whether every slot's command for `tick` is known, so the tick can run.
func is_complete(tick: int) -> bool:
	for slot: int in players:
		if not has(tick, slot):
			return false
	return true


## Every slot's command for `tick`, indexed by slot, and forgets them. Only for a complete tick.
func take(tick: int) -> Array[Command]:
	var commands: Array[Command] = []
	commands.assign(_ticks[tick])
	var _forgot: bool = _ticks.erase(tick)
	return commands
