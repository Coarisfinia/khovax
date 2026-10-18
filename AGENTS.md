# Agent notes for khovax

`khovax` is the permanent codename: the repository, paths and code identifiers use it. The game's
player-facing name is separate and lives only in display strings and config, so it can change without
touching git.

**The code explains itself**, with short comments next to it for the reasons a reader can't see (keep
them true in the same pull request that changes the code). **How the code works is documented next to the code,
never in this file** (owner's rule, on #395): this file holds the rules for working here, not
descriptions of classes, features or mechanics. **Decisions and their history live in the
GitHub issues**, the design included: there is no separate design document (owner, #217), so a
design decision goes into its issue. The README holds only what a human has to do by hand and how to
run things. This file holds the rules for working here and what agents have learned the hard
way; add to it when something bites.

## Working on GitHub

- **The repository is public.** Issues, pull requests, comments, commits, code and tests never
  contain personal data. Editing a slip away isn't enough, because GitHub keeps the edit history.
- **No brand names of other games or products** in issues, pull requests, comments, commits, code,
  tests or docs (owner's rule): describe the idea instead ("instanced regions", "comic-style cel
  shading with ink outlines", "monster catching"). The tools the project uses (Godot, GitHub, scoop,
  gdstyle, Codex) are dependencies, not references, and are fine.
- **The repository is `Coarisfinia/khovax`** (#329): the organization Coarisfinia owns it since the
  owner moved it there from their own account, whose old URLs redirect. What the organization stands
  for is decided later.
- **The agent works as `coarisfinia-ai-agent[bot]`** (the private GitHub App "Coarisfinia [AI Agent]",
  owned by the organization): it
  commits, pushes, opens and updates pull requests, comments and reads CI as the bot, never with the
  owner's account. Commits the owner makes by hand use the owner's GitHub noreply address, never the
  machine-global work email.
- **Tokens:** `agent-gh-token` (in `~/.local/bin`) signs a JWT with the app's private key
  (`~/.config/coarisfinia-agent/app.pem`, App ID in `app-id` next to it) and prints a 1-hour
  installation token, cached for 50 minutes. The token is scoped to this repository only and to the
  permissions the agent needs (contents, pull requests, issues, workflows, actions and merge queues:
  write; checks and commit statuses: read), so it can rerun a failed job but can't change settings. `agent-gh` is `gh` with that token.
  The key is never read, printed, committed or sent anywhere except GitHub's token endpoint.
- **Each clone**, once after cloning (its worktrees share the clone's config):

  ```sh
  git config user.name 'coarisfinia-ai-agent[bot]'
  git config user.email '343849075+coarisfinia-ai-agent[bot]@users.noreply.github.com'
  git config credential.https://github.com.helper ''
  git config --add credential.https://github.com.helper \
    '!f() { test "$1" = get || exit 0; echo username=x-access-token; echo "password=$(agent-gh-token)"; }; f'
  ```

- **Read an issue's or pull request's history before acting on it** (owner's rule, #66): newer
  events may have arrived since the alert that brought you there.
- **Pull requests and comments:** `agent-gh pr create --assignee Flixbox …`, `agent-gh pr comment …`.
- **What the bot doesn't do:** change repository settings, or merge without the owner's approval.
  After the approval it enables auto-merge, or merges itself when auto-merge stalls (below).
  Settings changes the owner asks for are made with the owner's `gh` login.
- **In Git Bash, `gh api` takes endpoints without a leading slash** (`installation/repositories`):
  the shell rewrites `/path` into a Windows file path.
- **Name other repositories' issues and pull requests only as code text** (`` `owner/repo#123` ``),
  never as a link: GitHub adds a "mentioned this" entry to the other repository for every linked
  mention from this public one.

## Pull requests

You own a pull request from the moment you open it until it is merged. "Pushed" is not "done".

**One issue, one pull request** (owner's rule). Every pull request says `Closes #n` for its issue and
is assigned to the owner (`--assignee Flixbox`).

**Every branch is a worktree next to `main/`** (owner's rule, the same layout as the owner's other
repositories). The container folder `project-khovax/` holds `main/` (the primary checkout, always on
`main`), `assets/` (the `assets` branch) and one `<issue>-<slug>/` worktree per open branch, created
with `git -C main worktree add ../<branch> -b <branch>` and removed once its pull request is merged.
Never create or switch branches inside `main/`.

**Having 5 pull requests open is the mandatory goal** (owner's rule), so the owner can go through
them fast: whenever fewer than 5 are open, building the next one comes before anything but the
owner's comments, right up to the usage budget's stop line. A pull
request in the merge queue counts as done (owner's rule): it doesn't count toward the 5. Each is
branched from `main` and independent of the others: never stack pull requests, since they're
squash-merged, which rewrites the history a stacked branch is built on. Work that needs another
open pull request waits until that one is merged. The merge queue tests each one on top of `main`
and the ones queued before it, so a pull request needs no rebase just because `main` moved; rebase
it (`git rebase origin/main`) only when it conflicts, fixing what collides (e.g. two rule changes
each bumping `RULES_VERSION`: take the next number and rehash again), and push.

**Build the next pull requests while the open ones wait for review** (owner, #217): each in its own
worktree, fully built and reviewed by Codex locally before it's pushed and opened.

**One pull request per coherent change**: one feature, one fix or one refactor, whole. Side findings,
refactors and tooling tweaks get their own issue and their own pull request later, never along for the
ride.

**Keep each pull request low in complexity: a concise unit of progress, no bloat** (owner's rule).
Prefer the simplest solution that does the job, and Godot's built-in way over a hand-built one. When
an issue turns out bigger than one such unit, build the core now and file the rest as its own
issue.

**Implementation subagents, the usage budget, the usage line in PR descriptions and the project
watcher** follow the owner's machine-wide agent notes (`~/.ai/AGENTS.md`), their single source of
truth (owner, #441); this file only adds this repository's values.

**No pull requests that only change docs.** A change to this file or the README
rides along with the next real pull request, and that pull request's description says so.

**Rules live in this file, not in an agent's memory.** When the owner states a rule for this
repository, write it here in the next real pull request.

**Every part of the game can be played with a controller** (owner's rule, on #438): whatever a
touch or a click does, a controller can do too.

**Buttons always show their item's or attack's icon, with its charges or cooldown** (owner's rule, on
#429): a button never vanishes when it's empty or cooling down; it shows 0, or a cooldown circle with
the seconds left.

**The agent decides the region legend's format** (owner's rule, on #389): how a region file marks
a tile, a place or a monster isn't the owner's call; pick a clear wording and note it in the issue.

**Track queued work as GitHub issues.** Every idea or request that isn't being built right now gets an
issue assigned to the owner. Nothing waits only in a chat. **Read the issue and all its comments
before starting work on it**: the owner decides things in comments, and the description alone can be
out of date.

**`blocking` issues come first** (owner's rule). An open issue labelled `blocking` goes before
everything else, tech debt included.

**Refactors and cleanups always come first** (owner's rule, on #384): while one is open (like the
move to slices, #375 to #381), it goes before any new feature.

**The order issues are taken in** (owner's rule), after `blocking` ones: CI/CD fixes, then bug
fixes, then performance (e.g. the web build loading in under 2 s, #265), then architecture, then
cleanup, then gameplay features (rules and mechanics), then UI, then visuals, then assets and
models.

**Never ask whether to continue** (owner's rule): work. Ask only for decisions that belong to the
owner.

**Keep going without being asked.** Once a pull request is merged, take the next issue, in the
order above. Ask only for decisions that belong to the owner (game
design, scope, security trade-offs).

**An issue that needs the owner's decision gets a bump comment with the question, and work goes
on with the next one** (owner's rule): never wait on an answer.

**Every question for the owner goes into an issue labelled `question`** (owner's rule): the owner
is usually away from the PC, so a question asked only in the chat goes unseen. One that belongs to
an existing issue is a comment there, and that issue gets the label too.

**A decision issue, once decided, is split into follow-up issues and closed** (owner's rule): one
issue per thing to build, each carrying the decisions it needs, and the decision issue links them.

**Close an issue once everything in it is built or tracked elsewhere** (owner's rule, #265):
an open issue is work still to do, never a record. Say in the closing comment where each part went.

**Stuck? File an issue and move on.** When something can't be finished without the owner, file an
issue saying what is blocked and why, and continue with the next work.

**Run long things in the background and keep working.** CI watchers and reviewer agents run in the
background; only wait in the foreground for a result the very next step needs.

### Before you push

- **Don't run tests or lint locally** (owner's rule): CI takes care of them. Lint, the script check,
  the e2e tests, the unused code and asset checks and the load test all run on every push, so push
  and let CI check, after a rebase too. Run one locally only to reproduce a CI failure.
- **Check exit codes without pipes**, or with `${PIPESTATUS[0]}`: a pipe hides the exit code.
- **Batch your changes** into one push.
- **Every pull request that changes what the player sees shows it** in its description as a
  screenshot. Headless runs have no renderer, so render it locally with a throwaway `-s` script
  that never shows a window (owner's rule: the owner works on the same PC, and off-screen
  positions get clamped onto a second monitor). Godot opens its window before any script runs,
  so the window must start as nothing: a temporary `override.cfg` in the worktree's root makes it
  one borderless pixel that never takes focus (`[display]` with `window/size/viewport_width=1`,
  `window/size/viewport_height=1`, `window/size/borderless=true`, `window/size/no_focus=true`,
  `window/size/resizable=false`), deleted right after the run and never committed (starting it
  minimized instead renders nothing). Parse-check the script headless first (`--check-only`):
  one that doesn't load leaves Godot's window showing. The script sets `root.mode = Window.MODE_MINIMIZED`, runs
  the main scene inside a `SubViewport` (`UPDATE_ALWAYS`, its own `msaa_3d`) and saves
  `get_texture().get_image()` as a PNG after enough frames for the camera to settle. Run it with
  `--audio-driver Dummy`, so the music stays silent (headless runs already are). Publish it on
  the `assets` branch (an orphan branch that is never merged), through the
  `assets/` worktree next to `main/`: `![what it shows](https://github.com/Coarisfinia/khovax/blob/assets/pr-<n>-<what>.png?raw=true)`.
  When the change has no visible part, say so instead. **Before and after pictures always go in
  that order** (owner's rule): the before first, then the after.
- **Show the flow as a replay whenever sensible** (owner's rule, #214): a pull request that
  changes how something plays shows it in its description as an animated GIF of that flow,
  rendered the same hidden, silent way (a PNG every few frames, assembled into the GIF) and
  published on the `assets` branch like a screenshot.

### After every push

- **Update the PR description** so it describes what the branch does now.
- **Keep the project watcher running in the background**: household-brain's Claude Code plugin
  `project-watcher` (#142); what each event asks for is in its `babysit-prs` skill
  ([`SKILL.md`](https://github.com/Flixbox/household-brain/blob/main/packages/watcher/skills/babysit-prs/SKILL.md)).
  Set it up as the owner's laptop-wide agent notes describe, with this repository's values:
  `REPO=Coarisfinia/khovax`, `OWNER=Flixbox` (the owner's login, whose reviews count),
  `WORKFLOW=ci.yml`, `GH=agent-gh`, `ACTIVITY_GH=gh` and `SELF='coarisfinia-ai-agent[bot]'` (it has
  no default). On a failing CI run, read the job with
  `agent-gh run view <run-id> --log-failed`, reproduce it locally, fix it, and push once.

### Review and merge

- **Every pull request gets one review**, by Codex as the laptop-wide agent notes describe: read-only, reporting findings with severity and
  evidence. Fix blockers and should-fix items before merge, in one push, and say in the PR
  description what was addressed. Four review rounds is the soft cap.
- **Every comment gets an answer.** Fix what is asked in one push, then reply saying what changed. If
  a comment needs the owner's decision, say so and leave it open.
- **Every merge goes through the merge queue** (owner's rule): never merge around it.
- **Merging:** once the owner has **approved** and the PR is well reviewed, read the PR for
  unanswered comments (an approval and a comment often arrive together), then enable auto-merge:
  `agent-gh pr merge <n> --auto --squash`. It joins the merge queue, which tests it on top of the
  pull requests queued before it and merges it once the required checks are green. Without
  the owner's approval, never enable auto-merge. **If it doesn't merge** although the PR is
  approved, CI is green and it shows as clean and mergeable (GitHub's auto-merge sometimes stalls),
  merge it yourself: `agent-gh pr merge <n> --squash` (owner, #99). The approval stays valid through
  later pushes (owner's rule), so check the comments again before enabling auto-merge after a fix.
- **Read the reviews themselves to see an approval** (`gh api repos/Coarisfinia/khovax/pulls/<n>/reviews`),
  never `reviewDecision` or the watcher's status line: under the ruleset `reviewDecision` stays
  empty, so an approved pull request shows as "awaiting approval" (`Flixbox/household-brain#197`).
  An approval often arrives together with review comments, and the watcher reports only those.

## Architecture

Game logic and control logic are strictly separated (owner's rule, #26), so that the same start
and the same commands always give the same game: for replays, lockstep co-op and tests.

```
devices -> input/ -> Command -> core/ + slices/*/rules/ -> GameState -> view/, slices/*/look/
                        ^
              game/ driver: fixed ticks
```

- **Vertical slices** (owner, #290, #371): what belongs together lives in one folder,
  `slices/<name>/`, in fixed subfolders, each only where the slice has one: `rules/` (the
  simulation, under every rule below for `core/`, checked by CI the same way), `look/` (views in
  the world, under the rules for `view/`), `ui/` (screens and menus) and `meta/` (profile, content
  and saves, under the rules for lasting data below). The split between them holds inside every slice. Shared
  slices (the trail, loot tables) come before the ones that use them. **The core never depends on
  a slice** (CI, `tools/import_rules.sh`: no script in `core/` names a class declared in `slices/`
  or names a `slices/` path in its code, even one built from parts, #526): data the core holds (a
  region's `TileTrigger`) and events it reads (`ExitTaken`, which the `World` moves a player
  through) stay in the core, and only the rules that run them move. The core is `core/` (#297):
  the tick, the state, the region, the world, the grid math and the feature list. Scripts reach
  each other by `class_name`; where a path is needed (a scene, a model, a `preload`), it is
  absolute from `res://`, never relative (`./`, `../`), which the same check refuses (#375). It
  also keeps the rules pure and the tests and tools apart (owner, #526): `core/` and every
  `rules/` never reach a `look/`, `ui/`, `view/`, `input/` or `game/` class or path, nothing
  outside `tests/` reaches the tests, and nothing outside `tools/` and `tests/` reaches the tools.
- **The simulation:** the core (`core/`: `Simulation.step(state, commands)`, `GameState`, the grid
  math `Hex`) and the features (each slice's `rules/`). Plain `RefCounted` classes (or subclasses of its classes),
  integers only, durations in ticks (`Simulation.TICKS_PER_SECOND`). No nodes, `Input`, `Time`,
  `Engine`, `OS`, global randomness, frame `delta` or `float`: CI greps for them. Randomness comes
  from `Rng` (#32, xoshiro128** in integers): each feature that rolls owns its own stream,
  `Rng.new(state.rng_seed, id())` in `start`, keeps it in its state and hashes it, and draws only
  inside its step; streams keep one system's rolls from shifting another's. Ranges use
  `below`/`between` (no modulo bias), never `next_u32() % n`. **Numbers** (#33, `Fixed`): amounts
  (HP, strength, power, damage) are whole integers up to `Fixed.MAX_AMOUNT`, fractions are in
  thousandths (`Fixed.ONE`), and every division rounds down through `Fixed` (`mul_div`, `ratio`,
  `scale`, `div_floor`), multiplying first and dividing last; never `/` on ints elsewhere.
  `GameState.state_hash()` fingerprints the whole state; a new value goes into the hash too
  (`Feature.hash_values()` for a feature's).
- **Every game rule is a feature** (owner's rule, #30): modular, and every one can be switched on or
  off per instance, also during a session (e.g. a boss phase). The core holds no game rule: only the
  tick, the seed, the region, the entities and the instance's features in their step order. A feature
  (in its slice's `rules/`, extends `Feature`) has a stable id in `Features` (never reused), its own state,
  a `step` called in order each tick, the features it `requires` earlier in the order, and its
  `hash_values`. Features talk through the tick's `events` (e.g. `EntityMoved`), not by reaching
  into each other: a feature may read the features it `requires` and change them only through
  their public methods (e.g. `DominationFeature` clears a ring off the trail with `TrailFeature.clear`), never
  their fields. Whether a feature is on is state: only rules switch it, inside a tick
  (`GameState.set_enabled`); a disabled feature keeps its state and doesn't step.
- **Entities** (#31): everything in the world (players, wild monsters, companions, later totems) is an
  `Entity` with a stable id, never reused, an owning player slot (0–3, or none) and a tile. An
  entity with a slot is that slot's player: rules treat it as one (it walks by commands, draws the
  trail, takes exits), so what belongs to a player without being one keeps its owner in its
  feature's data, like a companion (`CompanionFeature.owners`, #338). A
  feature keeps its own data per entity id, like a component (`MovementFeature.walks`), set up and
  dropped in `entity_added` / `entity_removed`. Rules go through entities in id order
  (`GameState.entities`), never in a dictionary's order, and sort ids before hashing.
- **Regions** (#36): rules ask `state.region` (`is_walkable`, `has_tile`), never a distance from
  the origin, so a region can have any shape. How regions are read, arranged, left through exits
  and purged is in `Region`, `RegionDocument`, `RegionArranger` and `World`.
- **Instance blueprints** (`InstanceBlueprints`, in `blueprints/`, outside the core, #396): a
  new mechanic is a new feature that blueprints list; it never grows the core.
- **Names in code** (owner's rule, #45): clear differentiators, never a bare `monster` where one of
  these is meant. A `species` is what every monster is, dominated or not; a `dominated_monster` was
  dominated by the player (made to submit, #317: it is never captured or caught); a `wild_monster`
  can still be dominated; an `ally_monster` fights on the player's side but isn't dominated and
  can't be. The player dominates; the act is a domination. They're names, not necessarily
  separate classes.
- **The place you play in** (owner's rule, #57, #117): **"map" is banned** in code and docs, except
  for a **map item**, an item drop that adds modifiers to an instance blueprint (#120). An
  **instance blueprint** is what an instance is loaded from (its region pieces and features); an
  **instance** is a loaded one (its region and state, #119); the **region** is the arranged place;
  a **region piece** is a hand-made piece a region is arranged from. There are **no runs** (#183):
  the players roam one persistent `World`. A **session** (loading the game to quitting it) is
  technical and never shown to the player.
- **Commands** (`Command`): the only way into the simulation, one per player per tick, integers
  only. The starting state plus every tick's commands is a replay.
- **Lasting data, above the simulation** (#37): what lasts between sessions (the `Profile` with its
  quest progress in `slices/profile/`, the saved `World`, the player's `Settings`), each in its own
  file, never inside the simulation. Saves are versioned JSON of integers and ids only, kept by
  `SaveStore`; gains are taken at once and saved debounced (owner, #73: `ProfileKeeper`,
  `WorldKeeper`). **`core/io/`** (#506) holds the readers and writers the core needs (the saves,
  the content reader, JSONC): the core's edge, which reads files and JSON's numbers, so CI's
  determinism check skips it (#515 looks into closing that), while the core-never-depends-on-a-slice
  check still covers it.
- **Content data** (#72): species, loot tables, tile blueprints, quests and, later, items are JSONC
  files, one per entry and named after its id. **Each kind lives in exactly one slice** (owner,
  #412): `slices/<slice>/data/<kind>/`, with its JSON Schema beside it (`<kind>.schema.json`), read
  only through that slice's accessor; the core gets plain integers and ids. The one exception: the
  tile blueprints, which the core's `TileKinds` needs, live in the core (owner, #506):
  `core/data/tiles/`, with their schema in `core/data/schemas/`, read by `Content` in `core/io/`. Not Godot resources
  (owner, #72: no engine lock-in). **Tile traits are
  rules** (`TileKinds`): changing one (e.g. `walkable`) bumps `Simulation.RULES_VERSION` and
  rehashes the golden replays, like any rule change.
- **`input/`, the input layer:** devices to commands. Every device presses the same InputMap
  actions (`LocalInput`); `HexInput` is the only place floats become a hex direction.
- **`view/`, the presentation:** scenes that read the state and draw it; they never write it.
  `HexLayout` is the only tile-to-world conversion. One-shot effects play from the tick's events
  (the driver's `ticked` signal, #34); lasting looks come from the state.
- **`game/`, the driver:** `GameDriver` runs whole ticks of the `World` in lockstep: real time
  decides when ticks happen, never what they do. It records every session as a `Replay`, and its
  `EventBus` subscribers never change the world.
- A new mechanic gets its own slice, `slices/<name>/`: its rules and data into a feature in
  `rules/` with a replay check, its controls into `input/` as commands, and its look into its own
  view in `look/` (like `TrailView` in `slices/trail/look/`, which paints the trail onto
  `HexGrid`; `HexGrid` itself only draws tiles).

## Lessons learned

### Game architecture

- **Single responsibility is law; "god files" are banned** (owner's rule): every class and file
  does one job, and a file that has grown a second one is split, with each part named for its job
  (e.g. reading a region file apart from the region's data). A new behaviour goes where its job
  already lives, or into a new class, never onto whatever file is handy. Test files are exempt:
  a flow is one file per user flow, however long it grows. Helpers that several flows use (walking
  a path, stepping ticks, making commands) move into a shared test file rather than being copied.
  CI fails on any copied block (jscpd, #247), in game code and tests alike.
- **GDScript only, no C#.** Godot's C# projects can't export to the web, and the project keeps one
  language for all code.
- **Every GDScript warning is an error** (`project.godot`), and **every gdstyle rule is an error**
  (`gdstyle.toml`), the opt-in ones included (owner's rule). Type every variable, parameter and
  return value explicitly (no `:=`: `inferred_declaration` is an error too). A rule or warning only
  gets relaxed when it truly conflicts with another one, with the conflict named next to it.
  Inconvenience is not a reason. **The one exception the owner chose:** no cap on return statements
  (#341), so a large `match` returns once per case instead of being split into helpers. A script
  is at most 700 lines long (#335); the tests are exempt from that, so a flow stays one file per
  user flow however long it grows. A suppression is a `# gdstyle:ignore=<rule>` or
  `# gdstyle:ignore-file=<rule>` comment directly below a line giving the reason.
- **Before pushing, run `gdstyle fmt .`**: it fixes the formatting rather than only checking it.
  gdstyle is installed with scoop from `tools/scoop/gdstyle.json`; its version is pinned there and
  in CI (with the archive's checksum), so bump both together.
- **Godot rewrites `project.godot` in its own form** whenever it runs: its own order, no comments,
  and settings equal to their default left out (four warnings are errors by default). Keep the file
  in that form so it doesn't churn, and keep the reasons for its settings in this file instead.
- **The headless renderer is a dummy**: a MultiMesh's instance transforms can't be read back, so
  code that tests need to inspect keeps its own copy of what it gave the renderer.
- **The simulation is deterministic**: see "Architecture" above. No Godot physics in gameplay.
- **The Compatibility renderer is the baseline** on every platform, because the web supports only
  that one. Shaders and effects have to work there.
- **The web page's loading screen** (#261, #264, #270) is explained in a comment at the start of
  the web presets' `html/head_include` (the same in both).
- **The camera never shakes, pulses or snaps**: the game is designed around motion sickness.
- **Fog always moves animated** (owner, #243): it eases open and closed, and no hole ever opens
  in it in one frame, not around a player at the start nor on arriving somewhere.
- **No humanoid monsters** (owner, #230): nothing stands on two legs with arms, a human-like
  upright torso and a head; every monster is clearly a monster. Four legs, a tail, a snout and a
  head is fine; so is six legs with a long horizontal belly, an upright torso, two arms and a
  monster's head. Two legs, a human-like upright torso, six arms and a head is not.
- **Monsters are wolf-smart, and humanoids are never fought** (owner's worldbuilding rules): no
  monster is smarter than an average wild wolf (packs with leaders and ambushes, never talking).
  The player fights only monsters, never humanoids. Factions may hate the player, and the player can
  make peace with them or work against them, but no humanoid fights a humanoid. Humanoids who side
  with the monsters surrender once their monsters are defeated, and battles between humans are
  fought by their monsters.
- **The player only ever sees their current rank with a faction** (owner's rule, on #484): never
  the names of the other ranks, which would spoil what's ahead. Each faction has its own design for
  its ranks.
- **Every attack is a species' own** (owner, #228): no move shared by every monster, and no
  borrowed move names. What attacks have in common is a property (a non-lethal auto attack, like a
  bird-style monster's beak strike, never takes a wild monster below 1 HP), not a common move.
- **Every feature is designed for co-op** (owner's rule, #74), though the game is played solo
  until hosting is solved (#75). Rules run in the deterministic simulation for 1–4 players, input
  reaches it only as per-player commands, nothing assumes a single player (no one "the player", no
  shared camera), and what a player obtains goes into their own profile.
- **Never color alone** (owner's rule, #68): whatever the player tells apart by color (types,
  teams, states) also gets a symbol or a shape, so the game stays colorblind friendly. Every tile
  kind names its symbol in its data (#334; the schema requires it), which the Survey draws.
- **The look is cel-shaded eye candy** (owner, #69): monsters and what the camera shows up close
  are medium-poly; only small things that don't read from the top-down camera may be low poly.
  Low-poly packs are placeholders. Every asset in the repository has a license that allows it
  here (CC0, CC BY with credit), kept next to it. **Each pack lives in `assets/<pack>/`** with its
  license file and a `SOURCE.md` (title, then `- **Author:**`, `- **Source:**`, `- **License:**`);
  `CREDITS.md` is generated from those by `tools/credits.gd`, and CI fails when it's out of date
  (owner, #69/#70). Commit only what the game uses, not whole packs.

### Testing and CI

- **Every user flow has one coherent e2e test, headless** (owner's rule): one flow for booting
  into the world, one for moving on the hex grid, one for a full domination or combat encounter, and so
  on. A change to an area extends the flow that covers it with new steps; a new flow file
  (`tests/e2e/test_<flow>.gd`) is only for a new user flow. No collections of small unrelated tests,
  and no separate unit tests while the flows already check the same things (owner, #61).
- **Exactly one e2e flow runs on the devices** (owner's rule, #61, #102, #113):
  `tests/apk/apk_flow.gd`, on an Android emulator (`apk-e2e`), in headless Chrome (`web-e2e`,
  `tests/web/web_e2e.ts`) and on the Linux build under a virtual display (`linux-e2e`) in CI,
  started by `game/test_mode.gd` in the test builds only (the `e2e_test` export feature). It
  starts from a fixed seed, scripts its touches per tick, and must end in `EXPECTED_HASH`, which
  the same flow pins headless (`tests/e2e/test_apk_flow.gd`). A rule change that moves it updates
  it on purpose, like the golden replays. Everything else stays headless. `apk-e2e` is a required
  check: it passed the first time it ran, and the owner asked to enforce it then.
- **The test runner is our own** (`tests/e2e/run_e2e.gd`). The owner kept it over a framework
  for now (#61).
- **A fresh checkout needs `godot --headless --path . --import`** before headless runs, and so
  does a worktree after a rebase brings in a new `class_name` script: with a stale class cache, the
  flows fail to load or log errors that have nothing to do with the change.
- **A script error in the runner itself leaves the SceneTree running forever.** Every CI step that
  runs Godot needs a `timeout`, and every job a `timeout-minutes`.
- **Local names that shadow a base-class method or property fail the script check**: `reference`,
  `position`, `script`, `name`, and the test's own `run` have all bitten. So have discarded return
  values (`erase`, `resize`, a method returning the thing it added): assign them to a `_`-prefixed
  local, and an inner test class named like a global one (`Walk`).
- **gdstyle can accept what Godot's parser refuses**: a multi-line lambda inside a call's arguments
  passed `gdstyle check` but failed the script check ("Unindent doesn't match"). Write a loop, or a
  one-line lambda.
- **A warning fails a flow too**, unless the flow expects it: before provoking one on purpose (a
  refused world save), it calls `tree.call("expect_warning", "<fragment>")`, and fails if the
  warning never comes. The device flows expect none.
- **A GDScript function that hits a script error returns its type's default** (`""` for `String`), so
  a test can't signal success by returning nothing. The runner counts logged errors during each test
  (a `Logger` added with `OS.add_logger`) and fails the test if any appeared.
- **Commit the `.uid` files** Godot creates next to scripts and resources. Godot only writes them on an
  import, so after adding a script run `godot --headless --path . --import` before committing. It
  generates files rather than checking anything, so it doesn't fall under not rerunning CI locally.
- **Pushing anything under `.github/workflows/` needs workflow rights.** The bot has them through the
  App's Workflows permission. For the owner's own login it is the `workflow` scope
  (`gh auth refresh -h github.com -s workflow`).
- **Never use the `pull_request_target` or `workflow_run` triggers**, and never add self-hosted
  runners to this public repository.
- **Everything CI downloads is pinned and verified:** actions by full commit SHA (with the tag in a
  comment), and Godot, its export templates and gdstyle by checksum, with cache keys that include
  the checksum. Bump a version and its checksum together, in `ci.yml` and `release.yml` both. The
  runner image is named explicitly (`ubuntu-26.04`, not `ubuntu-latest`), so a new image arrives on
  purpose, with the APK build checked, not on GitHub's date.
  **The one exception** (owner, #252): the web e2e's Mesa packages come unpinned from the runner
  image's signed Ubuntu archive. They must match the image's own Mesa, and the archive drops a
  superseded version, so an exact pin would break CI on the next security update.
- **Golden replays** (`tests/replays/*.replay`) are played by the replay flow in CI. One that stops
  matching means a change altered what the game does. If that is on purpose, bump
  `Simulation.RULES_VERSION`, rehash them (`godot --headless --path . -s
  res://tests/replays/rehash.gd`) and say in the pull request why the game plays out differently.
  Never rehash to make a surprise go away.
- **Point to the source, never enumerate it** (owner's rule, #99): a list that exists somewhere
  (the presets, the assets, the content files) is read from there, not copied into a workflow, a
  doc or a comment, where it would drift. E.g. CI unpacks the templates `tools/export_templates.sh`
  reads from `export_presets.cfg`, and `CREDITS.md` is generated from the assets.
- **No measured numbers in docs or comments** (durations, sizes, counts): they go stale. They belong
  in the PR or issue that measured them.

### Repository and accounts

- **`main` is protected by the ruleset "protect main"**, with no bypass: pull requests only, one
  approval (later pushes don't dismiss it), review threads resolved, the `headless` and `apk-e2e`
  checks from GitHub Actions green, merged through the merge queue (#329; CI runs on its
  `merge_group` events), squash merges only, no force-push or deletion. The required checks are named after the CI jobs: renaming a job means
  changing the ruleset in the same PR (owner's `gh`).
- **Release tags are immutable:** the tag ruleset "immutable release tags" (`refs/tags/v*`, owner,
  #91) blocks deleting, moving and force-updating them, with no bypass; creating one is allowed.
  A wrong release gets a new version, never a moved tag.
- **Pull requests opened with the owner's account can't be approved by the owner.** The bot opens
  them.

### Toolchain

- **Install tools with scoop** (owner's rule). The development machine runs Windows, so Homebrew isn't
  available.
- **`git push` hung on a Windows credential prompt.** In this repository the repo-local credential
  helper above avoids it. For the owner's own pushes elsewhere, `gh auth setup-git` makes git use the
  `gh` login.
