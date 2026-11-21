# Bare rock

- **Author:** the khovax contributors (built in this repository)
- **Source:** derived from the mana gems (`resourcepacks/default/models/mana-gems/mana_gems.glb`,
  #1218): `resourcepacks/default/models/bare-rock/build/bare_rock.py` reads that model, breaks its
  crystals off to short stubs with the shared model library's derive step
  (`src/game-models/lib/derive.py`), and exports `bare_rock.glb` (#2493)
- **License:** The Unlicense, the repository's own license, see `LICENSE.md` next to this file.
- **Used for:** the decoration on bare rock tiles, the gems' rock once their crystals are harvested.
