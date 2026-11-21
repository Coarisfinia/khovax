# Copper ore rubble

- **Author:** the khovax contributors (built in this repository); textures by Poly Haven (CC0)
- **Source:** derived from the ore outcrop (`resourcepacks/default/models/ore-outcrop/ore_outcrop.glb`,
  #1929): `resourcepacks/default/models/copper-ore-rubble/build/copper_ore_rubble.py` reads that
  model's shape, breaks it into chunks that slump into a lower heap with the shared model library's
  derive step (`src/game-models/lib/derive.py`), paints it from the props' shared texture set
  (`src/game-models/textures/`: Poly Haven's "Rock Boulder Dry",
  https://polyhaven.com/a/rock_boulder_dry, CC0, reduced to a few flat tones), and exports
  `copper_ore_rubble.glb` (#2572)
- **License:** The Unlicense, the repository's own license, see `LICENSE.md` next to this file; its
  textures are CC0 1.0 (`src/game-models/textures/LICENSE.md`).
- **Used for:** the decoration on copper ore rubble tiles, the copper ore once its copper is harvested.
