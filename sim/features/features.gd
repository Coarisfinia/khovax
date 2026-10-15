class_name Features
extends RefCounted
## Stable numbers for every feature. They go into state hashes and replays, so a number is never
## reused or changed once a feature has shipped.

const NONE: int = 0
const MOVEMENT: int = 1
const TRAIL: int = 2
const WILD_MONSTERS: int = 3
const CATCH: int = 4
const CHESTS: int = 5
