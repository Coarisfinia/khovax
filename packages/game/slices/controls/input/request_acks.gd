class_name RequestAcks
extends Node
## What LocalInput asks about the requests from this machine's player's profile it sends (#771):
## the code up to which the profile saw every request of a kind acknowledged (#942, #968), for the
## command that carries one. The profile's tie (ProfileTie) answers from the profile; the controls
## only name this, so they never reach the profile, which comes after them (#851).


## The code up to which every request of `kind` (OutboxEntry.KINDS) was acknowledged, or
## Command.NO_REQUEST without a profile.
func confirmed(_kind: int) -> int:
	return Command.NO_REQUEST
