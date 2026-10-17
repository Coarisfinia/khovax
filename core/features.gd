class_name Features
extends RefCounted
## Stable numbers for every feature. They go into state hashes and replays, so a number is never
## reused or changed once a feature has shipped.

const NONE: int = 0
const MOVEMENT: int = 1
const TRAIL: int = 2
const WILD_MONSTERS: int = 3
const DOMINATION: int = 4
const CHESTS: int = 5
const FOG: int = 6
const EXITS: int = 7
const TRIGGERS: int = 8
const ENRAGE: int = 9
const HIDING: int = 10
const DOMINATION_LOOT: int = 11
const COMPANIONS: int = 12
const ENTERING: int = 13
const COMPANION_ATTACKS: int = 14
