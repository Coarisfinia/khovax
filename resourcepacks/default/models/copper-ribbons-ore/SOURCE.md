# Copper ore

- **Author:** the project (shape generated with Meshy AI, paid plan, Private licence); textures by
  Poly Haven (CC0)
- **Source:** its shape ("folded copper ribbons in stone") generated without a texture with Meshy
  AI by the owner (#2012, #1949), turned into `src/game-models/sources/copper_ribbons_ore.glb` by
  `src/game-models/import_source.py`; `src/game-models/copper_ribbons_ore.py` removes the one
  ribbon that left the stone as two strands (the owner's fix), textures the stone from the props'
  shared texture set (`src/game-models/textures/`: Poly Haven's "Rock Boulder Dry",
  https://polyhaven.com/a/rock_boulder_dry, CC0, reduced to a few flat tones), gives the ribbons a
  flat copper tint, and exports `copper_ribbons_ore.glb`
- **License:** Unlicense, the repository's own license, see `LICENSE.md` next to this file; its
  textures are CC0 1.0 (`src/game-models/textures/LICENSE.md`).
- **Used for:** the copper material's model (#1949).
