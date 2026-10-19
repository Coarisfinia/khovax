# Glade, corrupted

The corrupted glade (#541): the variant the flag glade_corrupted chooses for the glade, a placeholder until corrupted instances get their own look. A bare clearing of felled stumps and rock, a disc of radius 5 like the glade's start piece (#712), with the ways out where that piece has them (#689): north to the forest and southeast to the outpost, each three tiles wide, so the web of instances lies the same around it. In its middle the wild monster holding the corruption, with room to walk a ring around it. When it faints it emits glade_purified, whose world flag turns the glade back into itself the next time nobody is in it.

## Tiles

```
     🟫🚪🚪🚪🟫🟫
    🟫🪵🟫🟫🟫🪵🟫
   🟫🟫🟫⬛🟫🟫🟫🟫
  🪵🟫🟫🟫🟫🟫🟫🪵🟫
 🟫🟫⬛🟫🟫🟫🟫🟫🟫🟫
🟫🪵🟫🟫🟫🦅🟫🟫🟫🪵🟫
 🟫🟫🟫🟫🟫🟫🟫⬛🟫🟫
  🟫🪵🟫🟫🟫🟫🟫🟫🟫
   🟫🟫⬛🟫🟫🪵🟫🌀
    🟫🪵🟫🟫🟫🟫🌀
     🟫🟫🟫🪵🟫🌀
```

## Legend

- `🟫`: ground
- `⬛`: rock
- `🪵`: stump
- `🦅`: a wild monster, always storm_finch, emitting glade_purified
- `🚪`: exit to the northwest, to forest
- `🌀`: exit to the southeast, to outpost
