class_name LaunchOptions
extends RefCounted
## Options given on the command line after `--` (#237), read the same way by the game and by the
## e2e runner, so a world can be started deterministically by hand, e.g.
## `godot --path . -- --instance=glade --seed=42`:
## - `--seed=<n>`: a fresh world starts from this seed (0 or more) instead of rolling one.
## - `--instance=<blueprint>`: the session starts in this instance blueprint, on its start.
## - `--invincible`: the player takes no damage. Reserved: nothing hurts players yet (#220, #221).
## A world started with a seed or an instance is a test world: it never resumes or overwrites the
## player's saved one. The game reads them in every build (LaunchMode).

const SEED: String = "--seed="
const INSTANCE: String = "--instance="
const INVINCIBLE: String = "--invincible"

## The seed to start from, or GameDriver.ROLLED_SEED to roll one.
var seed_value: int = GameDriver.ROLLED_SEED
## The instance blueprint to start in, or "" for the main scene's own.
var instance: String = ""
var invincible: bool = false
## Why the options can't be used, or "" when they can.
var problem: String = ""


## The options in `args` (the user arguments, after `--`); `problem` says what's wrong. Arguments
## that don't start with `--` are a script's own (tools/load_test.gd's `ticks=2000`), not options.
static func parse(args: PackedStringArray) -> LaunchOptions:
	var options: LaunchOptions = LaunchOptions.new()
	for arg: String in args:
		var value: String = arg.get_slice("=", 1)
		if not arg.begins_with("--"):
			continue
		if arg.begins_with(SEED) and value.is_valid_int() and value.to_int() >= 0:
			options.seed_value = value.to_int()
		elif arg.begins_with(INSTANCE) and InstanceBlueprints.NAMES.has(value):
			options.instance = value
		elif arg == INVINCIBLE:
			options.invincible = true
		elif arg.begins_with(INSTANCE):
			options.problem = "no instance blueprint %s; there are %s" % [
				value,
				", ".join(InstanceBlueprints.NAMES),
			]
		else:
			options.problem = "not an option, or not a seed of 0 or more: " + arg
		if not options.problem.is_empty():
			return options
	return options


## Whether these options start a test world rather than the player's own.
func is_test_world() -> bool:
	return seed_value != GameDriver.ROLLED_SEED or not instance.is_empty()


## Sets the options given up for the main scene, before it loads: its driver starts from the seed,
## in the instance, and a test world keeps no save. Options not given change nothing.
func apply() -> void:
	if seed_value != GameDriver.ROLLED_SEED:
		GameDriver.fixed_seed = seed_value
	if not instance.is_empty():
		GameDriver.start_instance = instance
	if is_test_world():
		WorldKeeper.default_path = ""
