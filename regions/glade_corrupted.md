# Glade, corrupted

The corrupted glade (#541): the variant the flag glade_corrupted chooses for the glade, a placeholder until corrupted instances get their own look. A bare clearing of felled stumps and rock, a disc of radius 5 like the glade's start piece (#712), with the ways out where that piece has them (#689): north to the forest and southeast to the outpost, each three tiles wide, so the web of instances lies the same around it. In its middle the wild monster holding the corruption, with room to walk a ring around it, and southwest of it where players 1 to 4 start, since the glade is where the world starts and a player out of HP is sent back to (#727). When it faints it emits glade_purified, whose world flag turns the glade back into itself the next time nobody is in it.

## Tiles

```
     🟫🚪🚪🚪🟫🟫
    🟫🪵🟫🟫🟫🪵🟫
   🟫🟫🟫⬛🟫🟫🟫🟫
  🪵🟫🟫🟫🟫🟫🟫🪵🟫
 🟫🟫⬛🟫🟫🟫🟫🟫🟫🟫
🟫🪵🟫🟫🟫🦅🟫🟫🟫🪵🟫
 🟫🟫🟫🔴🟢🟫🟫⬛🟫🟫
  🟫🪵🔵🟡🟫🟫🟫🟫🟫
   🟫🟫⬛🟫🟫🪵🟫🌀
    🟫🪵🟫🟫🟫🟫🌀
     🟫🟫🟫🪵🟫🌀
```

## Legend

- `🟫`: ground
- `⬛`: rock
- `🪵`: stump
- `🦅`: a wild monster, always tikazzir, emitting glade_purified
- `🔴`: where player 1 starts
- `🔵`: where player 2 starts
- `🟢`: where player 3 starts
- `🟡`: where player 4 starts
- `🚪`: exit to the northwest
- `🌀`: exit to the southeast
