class_name HostSettingsFeature
extends Feature
## Applies the host's world settings (#1309, HostSettings): a request of the kind
## OutboxEntry.HOST_SETTING from the host's profile sets one, kept in the host's world store, so
## every instance reads it at once and it lasts with the world. Like every request, it's applied
## once (OutboxReceipts). Only the host chooses: a request of that kind from another player is
## acknowledged and changes nothing, and so is one for a setting or a choice there is none of.
## First in the step order, so every rule this tick plays by the setting the host chose this tick.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = HostSettings.FEATURE_ID


func id() -> String:
	return ID


## Sets what the host asks for, in slot order, acknowledging every request of the kind.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		var asking: bool = command != null and command.request_kind == OutboxEntry.HOST_SETTING
		if not asking or state.player(slot) == null:
			continue
		if not OutboxReceipts.take(state, slot, id(), command) or slot != HostSettings.HOST:
			continue
		var setting: String = HostSettings.setting_of(command.request_data)
		var value: int = HostSettings.value_of(command.request_data)
		if not setting.is_empty() and HostSettings.CHOICES[setting].has(value):
			state.store(slot, id())[setting] = value
