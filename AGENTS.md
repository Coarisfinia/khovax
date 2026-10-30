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
- **The owner's login is looked up, never written down:** the repository's one human admin (the
  repository's own owner is the organisation, not a person). The lookup fails unless there is
  exactly one:
  `OWNER=$(agent-gh api "repos/Coarisfinia/khovax/collaborators?permission=admin" --jq '[.[] | select(.type == "User")] | if length == 1 then .[0].login else error("expected one human admin") end')`
- **Pull requests and comments:** `agent-gh pr create --assignee "$OWNER" …`, `agent-gh pr comment …`.
- **What the bot doesn't do:** change repository settings, or merge a user-facing pull request
  without the owner's approval. It queues one the owner approved, or a pull request that isn't
  user-facing once it is reviewed (below), or merges itself when auto-merge stalls (below).
  Settings changes the owner asks for are made with the owner's `gh` login.
- **In Git Bash, `gh api` takes endpoints without a leading slash** (`installation/repositories`):
  the shell rewrites `/path` into a Windows file path.
- **Name other repositories' issues and pull requests only as code text** (`` `owner/repo#123` ``),
  never as a link: GitHub adds a "mentioned this" entry to the other repository for every linked
  mention from this public one.
- **No individual contributor is named in the repository** (owner's rule, #1060): no hard-coded
  login, name or ping in code, docs, skills or tools ("ping <login>", `--assignee <login>`). Say
  "the owner" and look the login up (above). A list a tool generates and keeps up to date, such as
  an automatic contributor list, is fine.

## Pull requests

You own a pull request from the moment you open it until it is merged. "Pushed" is not "done".

**One issue, one pull request** (owner's rule). Every pull request says `Closes #n` for its issue and
is assigned to the owner (`--assignee "$OWNER"`, the login looked up as above).

**Every branch is a worktree next to `main/`** (owner's rule, the same layout as the owner's other
repositories). The container folder `project-khovax/` holds `main/` (the primary checkout, always on
`main`) and one `<issue>-<slug>/` worktree per open branch, created
with `git -C main worktree add ../<branch> -b <branch>` and removed once its pull request is merged.
Never create or switch branches inside `main/`.

**Having 5 pull requests waiting for the owner's review at all times is the mandatory goal**
(owner's rule, #1088), so the owner can go through them fast: whenever fewer than 5 wait, building
the next one comes before anything but the owner's comments, right up to the usage budget's stop
line. One the owner has approved, or one in the merge queue, no longer counts toward the 5 (owner,
#1088). Each is
branched from `main` and independent of the others: never stack pull requests, since they're
squash-merged, which rewrites the history a stacked branch is built on. Work that needs another
open pull request waits until that one is merged. The merge queue tests each one on top of `main`
and the ones queued before it, so a pull request needs no rebase just because `main` moved; rebase
it (`git rebase origin/main`) only when it conflicts, fixing what collides, and push. Two rule
changes don't collide (#876): each adds its own file, and nothing that a build computes is
committed.

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

**Avoid pull requests that only change docs** (owner, a loose rule, #1748): by default a change to
this file or the README rides along with the next real pull request, and that pull request's
description says so. A docs-only pull request that exists anyway is never closed or undone for it.

**Rules live in this file, not in an agent's memory.** When the owner states a rule for this
repository, write it here in the next real pull request.

**Every part of the game can be played with a controller** (owner's rule, on #438): whatever a
touch or a click does, a controller can do too.

**Buttons always show their item's or attack's icon, with its charges or cooldown** (owner's rule, on
#429): a button never vanishes when it's empty or cooling down; it shows 0, or a cooldown circle with
the seconds left.

**The agent decides the region legend's format** (owner's rule, on #389): how a region file marks
a tile, a place or a monster isn't the owner's call; pick a clear wording and note it in the issue.

**Region files use only same-width emoji** (owner's rule, #711): every tile in a region's grid is
one emoji as wide as two spaces, so a region reads as a neat picture; a letter, digit or other
narrow character is refused, and so is any emoji the legend doesn't explain. Pick single-code-point
emoji that show as emoji by default (no variation selector).

**Track queued work as GitHub issues.** Every idea or request that isn't being built right now gets an
issue assigned to the owner. Nothing waits only in a chat. **Read the issue and all its comments
before starting work on it**: the owner decides things in comments, and the description alone can be
out of date.

**Anything off, missing or tech debt gets an issue** (owner's rule, #630): whenever an agent or
subagent notices something wrong, missing or owed while working, it files a GitHub issue before
its work is done, labelled `question`, with numbered options and a ★ on the recommendation.

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
an existing issue is a comment there, and that issue gets the label too. Once the owner has answered
every question in an issue, remove its `question` label (owner's rule, #737).

**Obvious choices aren't asked** (owner's ground rule, #806): if the choice is obvious, don't ask;
file the task as a plain issue (no `question` label) and queue it. Investigating a cause is part
of the work, never a question.

**A decision issue, once decided, is split into follow-up issues and closed** (owner's rule): one
issue per thing to build, each carrying the decisions it needs, and the decision issue links them.

**Close an issue once everything in it is built or tracked elsewhere** (owner's rule, #265):
an open issue is work still to do, never a record. Say in the closing comment where each part went.

**Stuck? File an issue and move on.** When something can't be finished without the owner, file an
issue saying what is blocked and why, and continue with the next work.

**Run long things in the background and keep working.** CI watchers and reviewer agents run in the
background; only wait in the foreground for a result the very next step needs.

### Before you push

- **Run gdstyle's check before every push** (owner's rule, #761; it's instant), after `gdstyle fmt
  .`: `gdstyle check --no-color --ignore quality/max-file-length .` and, for the file length outside
  the game's `tests/`, `git ls-files -z '*.gd' ':!packages/game/tests/' | xargs -0 gdstyle check
  --no-color --select quality/max-file-length`. Fix what it finds.
- **Don't run other tests or lint locally** (owner's rule): CI takes care of them. The script check,
  the e2e tests, the unused code and asset checks and the load test all run on every push, so push
  and let CI check, after a rebase too. Run one locally only to reproduce a CI failure.
- **Check exit codes without pipes**, or with `${PIPESTATUS[0]}`: a pipe hides the exit code.
- **Batch your changes** into one push.
- **Every pull request that changes what the player sees shows it** in its description as a
  screenshot. Headless runs have no renderer, so render it locally with a throwaway `-s` script
  that never shows a window on the owner's desktop (owner's rule: the owner works on the same PC,
  and under WSL every window on WSLg's display, even a one-pixel one, becomes a Windows window that
  takes the focus from their typing). Run it on a private virtual display instead, through
  `uv run --locked packages/game-offscreen/offscreen.py -- --path packages/game -s res://<script>.gd --
  <args>`
  (Xvfb, the Compatibility renderer, silent audio; nothing reaches the desktop, so no
  `override.cfg`). Never `--display-driver wayland`, never the desktop's `DISPLAY`. The script runs
  the main scene inside a `SubViewport` (`UPDATE_ALWAYS`, its own `msaa_3d`) and saves
  `get_texture().get_image()` as a PNG after enough frames for the camera to settle. Publish it on
  the `assets` branch (an orphan branch that is never merged) with `uv run --locked --package
  khovax-game-visuals packages/game-visuals/publish.py pr-<n>-<what>.png ...`, which prints the
  link for the description: `![what it shows](https://github.com/Coarisfinia/khovax/blob/assets/pr-<n>-<what>.png?raw=true)`.
  **Never publish through a shared checkout of `assets`, and never reset one** (#1428): agents
  publish at the same time, and a reset drops another agent's pictures. The script commits without
  a checkout and starts over on the newer `origin/assets` when another publish got there first.
  When the change has no visible part, say so instead. **Before and after pictures always go in
  that order** (owner's rule): the before first, then the after.
- **Show the flow as a replay whenever sensible** (owner's rule, #214): a pull request that
  changes how something plays shows it in its description as an animated GIF of that flow,
  rendered the same hidden, silent way (a PNG every few frames, assembled into the GIF) and
  published on the `assets` branch like a screenshot.
- **If a pull request has something to see, its description shows it, test replays included**
  (owner's ground rule, #887).
- **A model pull request shows its animation clips in its description** (owner's ground rule,
  #1331): a GIF of each clip it builds or changes, in game, before and after, the same set
  earlier model pull requests showed. They're essential, so they go in the description, not only
  in a comment.

### After every push

- **Update the PR description** so it describes what the branch does now.
- **Keep the project watcher running in the background**: household-brain's Claude Code plugin
  `project-watcher` (#142); what each event asks for is in its `babysit-prs` skill
  ([`SKILL.md`](https://github.com/Flixbox/household-brain/blob/main/packages/watcher/skills/babysit-prs/SKILL.md)).
  Set it up as the owner's laptop-wide agent notes describe, with this repository's values:
  `REPO=Coarisfinia/khovax`,
  `WORKFLOW=ci.yml`, `GH=agent-gh`, `ACTIVITY_GH=gh`, `SELF='coarisfinia-ai-agent[bot]'` (it has
  no default), `DISMISS_STALE_BOT_REVIEWS=1` (owner, #1551: it dismisses CodeRabbit's stale
  change request itself, below), `REVIEW_BOTS=coderabbitai` (`Flixbox/household-brain#299`: it
  holds `READY_TO_MERGE` for a draft the owner approved until CodeRabbit has reviewed its head;
  `Flixbox/household-brain#324` makes it wait only for a review that was asked for),
  `READY_APPROVED_DRAFTS=1` (owner, #1667: it marks a draft ready once the owner approves its head,
  below), `RESOLVE_BOT_REVIEWS=coderabbitai` (owner, #1603: once CodeRabbit's change request on the head is
  settled, every thread resolved and CI green, it posts `@coderabbitai resolve` whatever the merge
  risk, and reports `BOT_RESOLVE_ASKED`) and `CLEARED_LABEL=subagent-cleared`
  (`Flixbox/household-brain#331`: with `DISMISS_STALE_BOT_REVIEWS=1` it dismisses settled
  CodeRabbit change requests on a pull request so labelled, below). `.claude/watcher.env` holds
  them all, for the plugin's own monitor and for
  `bun --env-file=.claude/watcher.env <watcher>/src/watch-project.ts --follow`; the environment
  still wins. The watcher finds the owner, whose reviews count, itself: the organisation's one
  human admin (`Flixbox/household-brain#296`); `OWNER` only overrides that. On a failing CI run,
  read the job with
  `agent-gh run view <run-id> --log-failed`, reproduce it locally, fix it, and push once.

### Review and merge

- **Every pull request gets one review**, by Codex as the laptop-wide agent notes describe: read-only, reporting findings with severity and
  evidence. Fix blockers and should-fix items before merge, in one push, and say in the PR
  description what was addressed. Four review rounds is the soft cap.
- **Every comment gets an answer.** Fix what is asked in one push, then reply saying what changed. If
  a comment needs the owner's decision, say so and leave it open.
- **A review thread is settled with a reply that starts exactly `Resolved: <reason>`** (owner's
  rule, #1433): `Resolved: fixed in <sha>, …` or `Resolved: not changing, because …`. That one
  reply answers the comment and asks for the thread to be resolved, and the project watcher
  resolves it and reports `THREAD_RESOLVED`. This holds for every reviewer's thread, CodeRabbit's
  included, except one that waits on the owner's decision: that one is answered and left open
  (above). Only when no watcher runs, resolve it yourself with `resolve-review-thread PRRT_<id>`.
  The watcher's `reply-review-thread <pr> <comment-id|PRRT_id> <body>` helper
  (`Flixbox/household-brain#307`) sends such a reply through GraphQL (below) and waits out a rate
  limit once: `bun --env-file=.claude/watcher.env <watcher>/src/reply-review-thread.ts …`.
- **A draft only when there is something to see** (owner, #1566, #1569): a pull request that
  changes models (a `.glb`, its rig, clips or textures, `packages/game-models/`, the model skill)
  or UI (anything the player sees or touches on screen) **and** shows the owner something in its
  description (renders, screenshots, a before and after) is opened with `agent-gh pr create
  --draft …` and stays a draft until the owner approves. Once the owner approves its head, the
  watcher marks it ready itself and reports `DRAFT_READIED` (`Flixbox/household-brain#301`,
  `Flixbox/household-brain#316`); only on `APPROVED_DRAFT` (an older head approved, or marking it
  ready failed) run `agent-gh pr ready <n>` yourself, then queue it (below). Until
  `Flixbox/household-brain#324` is live, the watcher's `REVIEW_BOTS` hold never reports
  `READY_TO_MERGE` for such a draft without a CodeRabbit review: don't wait for that event, queue
  it once it may be queued. Every other pull request is not a draft.
- **Reply in a review thread through GraphQL, not REST** (#1573): the bot's REST calls (the
  `pulls/<n>/comments/<id>/replies` endpoint, review reads) got HTTP 403 "API rate limit exceeded
  for installation" in bursts while `rate_limit` still showed much of the hourly quota left: many
  agents and the watcher share the one installation, and a short-window limit (GitHub's secondary
  limits count REST points per minute) refuses a burst. GraphQL has its own quota and went
  through. The `reply-review-thread` helper (above) does this; by hand, find the thread's id from
  the comment's id, then reply:

  ```sh
  T=$(agent-gh api graphql -f query='{repository(owner:"Coarisfinia",name:"khovax"){pullRequest(number:<n>){reviewThreads(first:100){nodes{id comments(first:100){nodes{databaseId}}}}}}}' \
    --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(any(.comments.nodes[]; .databaseId == <comment-id>)) | .id')
  agent-gh api graphql -f t="$T" -f b='Resolved: fixed in <sha>, …' --jq .data.addPullRequestReviewThreadReply.comment.url \
    -f query='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){comment{url}}}'
  ```

  An empty `T` means the comment wasn't found: never send the reply then. The lookup reads the
  first 100 threads and 100 comments each; a pull request with more pages them with `after:`.

  Read reviews with `agent-gh pr view <n> --json reviews` (GraphQL) too. If any call still gets a
  403 or 429 about a rate limit, or a GraphQL error of type `RATE_LIMITED` (GraphQL reports it with
  HTTP 200), wait the seconds its `retry-after` header gives (`agent-gh api -i`
  shows it; without it, until `x-ratelimit-reset` when `x-ratelimit-remaining` is 0, else a minute)
  and retry once; never retry in a loop.
- **Every merge goes through the merge queue** (owner's rule): never merge around it.
- **When a pull request may be queued** (owner's ground rule, #1783): Codex's findings are
  handled, CI is green and every review thread is settled, and then:
  - **user-facing** (gameplay, content, UI, models, #1381): only once the owner has **approved** it;
  - **not user-facing** (tooling, CI, docs, refactors, agent rules): once a review subagent finds
    nothing blocking, named on the pull request. The merge queue still needs one approving review
    and doesn't apply the bot's bypass (#1867), so the main session then labels the pull request
    `subagent-cleared` and `.github/workflows/approve-cleared.yml` approves it (#1874) as a
    separate reviewer GitHub App, but only
    when the agent bot or a human admin put the label on, only into the default branch, and never
    for a pull request that changes or renames user-facing files (`packages/game/` outside its
    `tests/` and `tools/`; owner's pick 1 on #1874), nor for one that changes any workflow
    (`.github/workflows/`): any workflow could reach the guard's environment, so **a change to the
    guard, or to any workflow, always needs the owner**. A push or a new base withdraws that approval,
    never a person's; clear it again (label off and on).
    Queue it once that approval is there.

  **CodeRabbit reviews at most once per pull request** (owner's ground rule, #1783): its automatic
  reviews are off (`.coderabbit.yml`), and its approval is no part of the rule above. Only for a
  complex pull request, and only after the review subagent's review, the main session may ask for
  one CodeRabbit review, through the watcher (`Flixbox/household-brain#324`); its points are
  settled before queueing. Agents never ask it themselves. A settled CodeRabbit change request
  still blocks the merge, and no second review may replace it after a fix push
  (`Flixbox/household-brain#331`): once the review subagent has cleared a non-user-facing pull
  request, the main session (never an implementation agent) labels it `subagent-cleared`, and once
  CI is green at the head and it is no draft, the watcher dismisses CodeRabbit's change requests
  submitted before the label was last put on, each once settled by `Resolved:` replies
  (`REVIEW_DISMISSED`). Only the owner's or the agent bot's labelling counts. A change request
  after that needs a new clearance: label off and on again.
- **Merging:** once the pull request may be queued (above), read it for unanswered comments (an
  approval and a comment often arrive together), then enable auto-merge:
  `agent-gh pr merge <n> --auto --squash`. It joins the merge queue, which tests it on top of the
  pull requests queued before it and merges it once the required checks are green. Otherwise
  never enable auto-merge. **If it doesn't merge** although it may be queued (above), CI is green
  and it shows as clean and mergeable (GitHub's auto-merge sometimes stalls), merge it yourself:
  `agent-gh pr merge <n> --squash` (owner, #99). The watcher reports an approved one as
  `NOT_QUEUED` (`Flixbox/household-brain#311`: auto-merge on, approved, clean and green, yet
  outside the queue after 5 minutes); run the `enqueuePullRequest` mutation the event names, with
  `agent-gh`, which queues it at once. A pull request that isn't user-facing has no approval for
  the watcher to see, so check it yourself a few minutes after enabling auto-merge
  (GraphQL `pullRequest(number:<n>){mergeQueueEntry{position}}` is null while it is still open)
  and enqueue it the same way. The owner's approval stays valid
  through later pushes (owner's rule), so check the comments again before enabling auto-merge after a
  fix. **Name every
  change pushed after the owner's approval** (owner's pick on #1632): before enabling auto-merge (or
  enqueueing), post a PR comment listing each such change and what it does.
- **Read the reviews themselves to see the owner's approval** of a user-facing pull request
  (a pull request that isn't user-facing goes by the review subagent's result named on it instead)
  (`gh api repos/Coarisfinia/khovax/pulls/<n>/reviews`),
  never `reviewDecision` or the watcher's status line: under the ruleset `reviewDecision` stays
  empty, so an approved pull request shows as "awaiting approval" (`Flixbox/household-brain#197`).
  An approval often arrives together with review comments, and the watcher reports only those.

## Architecture

Game logic and control logic are strictly separated (owner's rule, #26), so that the same start
and the same commands always give the same game: for replays, lockstep co-op and tests. The game's
paths in this file (`core/`, `slices/`, `game/`, `tests/`, `assets/`, `tools/godot/`) are inside
the game's project, `packages/game/` (#1101), where `res://` starts.

```
devices -> slices/controls/input/ -> Command -> core/ + slices/*/rules/ -> GameState -> look/, ui/
                                  ^
                        game/ driver: fixed ticks
```

- **Vertical slices** (owner, #290, #371): what belongs together lives in one folder,
  `slices/<name>/`, in fixed subfolders, each only where the slice has one: `rules/` (the
  simulation, under every rule below for `core/`, checked by CI the same way), `look/` (views in
  the world, under the presentation's rules below), `ui/` (screens and menus), `input/` (devices to
  commands, only in `slices/controls/`, #514) and `meta/` (profile, content
  and saves, under the rules for lasting data below). The split between them holds inside every slice. Shared
  slices (the trail, loot tables) come before the ones that use them: **a slice names only the
  slices before it** in the order `packages/game-checks/import_rules.py` declares once (CI, #821;
  today's back-edges are listed there, each with its issue), so a new slice takes its place in it. **The core never depends on
  a slice** (CI, `packages/game-checks/import_rules.py`: no script in `core/` names a class declared in
  `slices/` or names a `slices/` path in its code, even one built from parts, #526): data the core holds (a
  region's exits) and events it reads (`ExitTaken`, which the `World` moves a player through) stay
  in the core, and only the rules that run them move; what a slice places on a region (people,
  triggers) the core keeps only as its legend meaning, which the slice reads (`PlacementReader`,
  #824). The core is `core/` (#297):
  the tick, the state, the region, the world, the grid math and the feature list. Scripts reach
  each other by `class_name`; where a path is needed (a scene, a model, a `preload`), it is
  absolute from `res://`, never relative (`./`, `../`), which the same check refuses (#375). It
  also keeps the rules pure and the tests and tools apart (owner, #526): `core/` and every
  `rules/` never reach a `look/`, `ui/`, `input/` or `game/` class or path, no `meta/` reaches a
  `look/`, `ui/` or `input/` class or path (#827, #831), nothing outside `tests/` reaches the tests, and nothing outside `tools/` and `tests/` reaches the tools.
  **`game/` wires the game together and nothing reaches back into it** (owner, #514): it may name
  any slice, but no script outside `game/`, `tests/` and `tools/` names a `game/` class or path,
  and no scene or resource outside them names a `game/` file. The slices see the driver only as a
  `Session` (`slices/board/look/`), which `GameDriver` extends.
- **The simulation:** the core (`core/`: `Simulation.step(state, commands)`, `GameState`, the grid
  math `Hex`) and the features (each slice's `rules/`). Plain `RefCounted` classes (or subclasses of its classes),
  integers only, durations in ticks (`Simulation.TICKS_PER_SECOND`). No nodes, `Input`, `Time`,
  `Engine`, `OS`, global randomness, frame `delta`, `float` or float-backed types (`Vector2`, `Color`,
  `Rect2` and the like; `Vector2i` and `Rect2i` are fine), `FileAccess`, `DirAccess` or `JSON`:
  CI greps for them (`packages/game-checks/determinism_check.py`, #572). A file that can't pass yet is
  exempt only with a reason, in its top comment lines (owner, #515), and gets an issue to drop the marker:
  `# TODO_REFACTOR_IF_POSSIBLE: IGNORE_DETERMINISM_CHECK (reason)`. Randomness comes
  from `Rng` (#32, xoshiro128** in integers): each feature that rolls owns its own stream,
  `Rng.new(state.rng_seed, stream())` in `start`, keeps it in its state and hashes it, and draws only
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
  (in its slice's `rules/`, extends `Feature`) has a stable string id, its own `ID` constant (a
  name, never a hand-kept number, so parallel pull requests never claim the same one, #784; never
  reused or renamed once shipped), its own state,
  a `step` called in order each tick (the order is `FeatureFactories`' list in the blueprints slice,
  reviewed like code; each blueprint's data file names its rule set and the rules it adds or drops, #823, #941, and what its region pieces' legends place brings the features that run it, #879), the features it `requires` earlier in the order (and those it reads that an instance may
  lack: `after` when they step earlier, `before` when they step later, #822; the replay flow
  checks that every feature it reads is declared), and its
  `hash_values`. Features talk through the tick's `events` (e.g. `EntityMoved`), not by reaching
  into each other: a feature may read the features it declares and change them only through
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
  and purged is in `Region`, `RegionDocument` (in the blueprints slice, reading its grid through
  the shared `EmojiGrid` slice, #865), `RegionArranger`, `World` and `WorldTravel`.
- **Instance blueprints** (`InstanceBlueprints`, in their own slice `slices/blueprints/meta/`,
  outside the core and above the features they list, #396, #513, #821): a new mechanic is a new feature that blueprints list, built by its own slice's factory
  (`FeatureFactories` maps its id to it, #823); it never grows the core. The core
  gets them only as an `InstanceSource` it's handed (`BlueprintSource`).
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
- **Lasting data, above the simulation** (#37): what lasts between sessions (the `Profile` in `slices/profile/`,
  with what later slices keep in its file, like the quest progress, #855; the saved `World`, the player's `Settings`), each in its own
  file, never inside the simulation. Saves are versioned JSON of integers and ids only, kept by
  `SaveStore`; gains are taken at once and saved debounced (owner, #73: `ProfileKeeper`,
  `WorldKeeper`). **Anything that versions data across builds records names, never a count or a
  hand-kept number** (owner, #801): a save names the format changes it was written with
  (`FormatChanges`), and a format change adds its `<issue>-<slug>.md` to its format's
  `format_changes/` folder (append-only, checked by CI) instead of bumping a `FORMAT`. **`core/io/`** (#506) holds the readers and writers the core needs (the saves,
  the content reader, JSONC): the core's edge, which reads files and JSON's numbers. Only
  `Content` (reading files and JSON), `SaveStore` (writing them), through which every other reader
  and writer there goes (#591, #1177), and `JsonNumbers`, the one place JSON's floats become whole
  numbers (#589), carry the determinism check's exemption marker (#515); the rest pass it (a tile
  blueprint keeps its color as a whole `0xRRGGBB`, which `TileLooks.color_of` turns into a
  `Color`, #1179). The core-never-depends-on-a-slice check covers them all. A
  reader takes JSON's numbers as whole
  numbers through `JsonNumbers` (#589), never by checking floats itself.
- **Content data** (#72): species, loot tables, tile blueprints, quests and, later, items are JSONC
  files, one per entry and named after its id. **Each kind lives in exactly one slice** (owner,
  #412): `slices/<slice>/data/<kind>/`, with its JSON Schema beside it (`<kind>.schema.json`), read
  only through that slice's accessor; the core gets plain integers and ids. The one exception: the
  tile blueprints, which the core's `TileKinds` needs, live in the core (owner, #506):
  `core/data/tiles/`, with their schema in `core/data/schemas/`, read by `TileContent` in `core/io/`. Not Godot resources
  (owner, #72: no engine lock-in). A tile kind is named by its blueprint's file, never a hand-kept
  number (#802, like features, #784). **Tile traits are
  rules** (`TileKinds`): changing one (e.g. `walkable`) is a rule change, like any other (see the
  golden replays below).
- **The presentation** (each slice's `look/` and `ui/`; the hex board everything stands on in
  `slices/board/look/`, the menu in `slices/menu/ui/`, #507): scenes that read the state and draw
  it; they never write it. `HexLayout` is the only tile-to-world conversion. One-shot effects play
  from the tick's events (the session's `ticked` signal, #34); lasting looks come from the state.
- **`game/`, the driver:** `GameDriver` runs whole ticks of the `World` in lockstep: real time
  decides when ticks happen, never what they do. It records every session as a `Replay`, and the
  `EventBus`'s subscribers never change the world. It also holds the boot, the launch options and
  test mode; the slices hold everything it wires (#514), the `EventBus`, the `WorldKeeper` and
  `WebStorage` included (`slices/board/`).
- **The controls** (`slices/controls/input/`, #514): devices to commands. Every device presses the
  same InputMap actions (`LocalInput`), and `HexInput` is the only place floats become a hex
  direction.
- A new mechanic gets its own slice, `slices/<name>/`: its rules and data into a feature in
  `rules/` with a replay check, its controls into `LocalInput` as commands, and its look into its own
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
  gdstyle is installed with scoop from `tools/scoop/gdstyle.json`; its version is pinned only there
  (CI reads it from the manifest), so a bump also updates CI's `GDSTYLE_SHA256`, the checksum of
  that version's Linux archive.
- **Godot rewrites `project.godot` in its own form** whenever it runs: its own order, no comments,
  and settings equal to their default left out (four warnings are errors by default). Keep the file
  in that form so it doesn't churn, and keep the reasons for its settings in this file instead.
  It overrides `ui_accept` to add a controller's A (#635): Godot's built-in one has keys only, so
  without it no controller could press a focused button.
- **The headless renderer is a dummy**: a MultiMesh's instance transforms can't be read back, so
  code that tests need to inspect keeps its own copy of what it gave the renderer.
- **The simulation is deterministic**: see "Architecture" above. No Godot physics in gameplay.
- **The Compatibility renderer is the baseline** on every platform, because the web supports only
  that one. Shaders and effects have to work there.
- **The web page's loading screen** (#261, #264, #270) is explained in a comment at the start of
  the web presets' `html/head_include` (the same in both, which CI checks).
- **The camera never shakes, pulses or snaps**: the game is designed around motion sickness.
- **Fog always moves animated** (owner, #243): it eases open and closed, and no hole ever opens
  in it in one frame, not around a player at the start nor on arriving somewhere.
- **No humanoid monsters** (owner, #230): nothing stands on two legs with arms, a human-like
  upright torso and a head; every monster is clearly a monster. Four legs, a tail, a snout and a
  head is fine; so is six legs with a long horizontal belly, an upright torso, two arms and a
  monster's head. Two legs, a human-like upright torso, six arms and a head is not.
- **Monsters may be strange** (owner, #990): obscure, barely alive, mystical or warped monsters
  are encouraged (a swirling vortex with glowing rocks for eyes is a wonderful creature); not
  every monster has four legs and barks.
- **Monsters are wolf-smart, and humanoids are never fought** (owner's worldbuilding rules): no
  monster is smarter than an average wild wolf (packs with leaders and ambushes, never talking).
  The player fights only monsters, never humanoids. Factions may hate the player, and the player can
  make peace with them or work against them, but no humanoid fights a humanoid. Humanoids who side
  with the monsters surrender once their monsters are defeated, and battles between humans are
  fought by their monsters.
- **Monsters act on needs and instincts, never strolling at random** (owner's ground rule, #1199):
  every species has a list of behaviour traits (`behaviour` in its data, #1200), and each monster
  acts by them on a daily schedule made from them. A `pack_species` monster bands with its own
  species, a `pack_type` one with monsters of the same or similar typing; a `predator` roams in
  search of prey (weaker or `grazer` monsters), a `drinker` finds its way to the nearest water now
  and then, a `grazer` finds grass to eat now and then. Every species has exactly one sleep rhythm
  (`diurnal`, `nocturnal`, `cathemeral` for sleeping in bouts, or `sleepless` for those that never
  sleep, like eldritch or gaseous ones) and enough needs to form a schedule (at least one of
  `grazer`, `drinker`, `predator`); the content flow refuses a species that hasn't. A sleeping
  monster wakes only when struck or enraged, unless its species is a `light_sleeper` (owner, #1230):
  then a player coming next to it wakes it too.
- **Randomness sparingly** (owner's ground rule, #1602): random rolls feel unsatisfying,
  especially on enemies. Prefer deterministic, readable rules (counters, thresholds, every Nth
  time, cooldowns) over chance; a new chance-based mechanic needs a reason in its issue.
- **Territory quests keep to ground rules** (draft for the owner's review, #638): a territory
  quest (`territory` in its quest data) names one instance and one faction, and finishing it hands
  that instance to that faction, whoever held it. It's written for its territory: its steps happen
  there (its region pieces, places and monsters), each naming its instance, so it counts only there
  (#769), and no two territory quests are one quest renamed. It has a clear goal there that fits its faction (chart it, hold its points, clear the
  monsters another faction keeps there, bring something back). It's a side quest that starts once
  the player first enters its territory, so it never shows before they've been there. It asks to
  fight monsters only: battling a humanoid's monsters in a trainer fight is fine, the humanoid
  themselves never (owner, #638). CI checks what it can (#639).
- **Powerful unique items are found, never handed over** (owner, #1553): no person gives one to
  the player (no gift, no shop). It's obtained in the world, possibly as a quest's reward, through
  something tied to the quest there. How each one is obtained is decided case by case, in its own
  issue; don't invent one. Two patterns the owner gave as examples: a person follows the player to
  a spot and unlocks it (going there alone, and saying so, if the player leaves the instance); or a
  boss chest in the world, a quest pointing at it until it's found, then a second piece to find and
  a person who joins the two.
- **The player only ever sees their current rank with a faction** (owner's rule, on #484): never
  the names of the other ranks, which would spoil what's ahead. Each faction has its own design for
  its ranks.
- **Places connect across several tiles, never one** (owner's rule, on #689): region pieces join
  in the middle of a flat edge, so neighbours meet along the whole edge, and every exit to another
  instance is at least three tiles wide. The world flow checks both.
- **Every attack is a species' own** (owner, #228): no move shared by every monster, and no
  borrowed move names. What attacks have in common is a property (a non-lethal auto attack, like a
  bird-style monster's beak strike, never takes a wild monster below 1 HP), not a common move.
- **Every species has a fantasy name** (owner's rule, #717): one invented word ("Degaea",
  "Zylopakas"), never a description ("Moss toad", "dark skeleton wolf"); the content flow refuses
  anything but one capitalised word. Its sound matches the monster (bouba/kiki): round, soft sounds
  (b, m, l, o, u) for round, gentle monsters, sharp ones (k, t, z, i) for spiky, fast ones.
- **A species' id is its name, in lower case** (owner's rule, #763): `ombulumo` for Ombulumo,
  everywhere: its file, its abilities, harvest and loot tables, legends, quests, text tags and
  saves. Renaming a species renames its id with it, and lasting data naming the old id migrates
  forward. The content flow refuses a species whose id isn't its name.
- **Every id and name is unique across all content** (owner's ground rule, #909): no two things
  share one, whatever their kinds (a tile, an instance, a region piece, a place, a person, a
  species, an ability, an item, a faction, a quest), in any case; a thing's own id and name may
  match. A region piece is a place inside its instance and is named after it ("the pond of
  <instance>", owner, #909), so two instances may each have a pond. The content flow refuses a
  duplicate (`ContentTerms`); the ones today's content still has wait in its list, each with its
  issue, and the list only shrinks.
- **Proper nouns get invented names, each kind under its own rules** (owner, #909): species,
  abilities, realms, instances and their places, factions, people and unique items are named, and
  each kind has its own tongue, so a name alone shows its kind and the world reads as one coherent
  whole; vocabulary (tile kinds, slots, stats, conditions, categories) stays descriptive, and gear
  is named in plain words. The six tongues adopted on #909 set each kind's shape, its closed
  lexicons (landform, oath and rune words) and the marks only one kind may use (beast-call letters,
  dh/gh/hr/wh, the hyphen, the apostrophe, vo/na, -ai, -vaun). `ContentTerms.NAME_RULES` holds
  each kind's rule for the content flow; a name breaking one today waits in `NAME_EXCEPTIONS` with
  its rename issue, and that list only shrinks.
- **Every new name is checked before it's suggested or used** (owner's rule, #717, #909; for
  suggested names, in chat, #1743): a name offered in a question counts too. It passes its kind's
  rule in `ContentTerms.NAME_RULES`, and it is searched as an exact phrase in Claude in Chrome on
  Google, the name in quotes with `nfpr=1` so Google doesn't swap in its own spelling, never with a
  web-search tool, which is unreliable for exact matches. Any real hit rules it out; the results go
  onto its issue.
- **Invented names use sound symbolism** (owner's rule): the bouba/kiki pattern is one tool
  (round, soft-sounding names for round, soft things, like Ombulumo; sharp, spiky-sounding names for
  sharp, quick ones, like Tikazzir), and other linguistic patterns are used alongside it, so no
  single pattern shapes every name.
- **Locking dialogs stay away from danger** (owner's ground rule, #981): a dialog that holds its
  player (it locks, or it offers an answer that commits, #912) is never placed at or near an
  aggressive spawn point or a combat area. Holding the player there makes it unfair in co-op, and
  the pause makes it cheesy solo.
- **Every feature is designed for co-op** (owner's rule, #74), though the game is played solo
  until hosting is solved (#75). Rules run in the deterministic simulation for 1–4 players, input
  reaches it only as per-player commands, nothing assumes a single player (no one "the player", no
  shared camera), and what a player obtains goes into their own profile.
- **Every text the player reads is translatable** (owner's pick on #1608): gettext, with the
  English text as the msgid. A script shows its texts through `tr()` with a literal string, a
  content field the player reads is marked `"x-translate": true` in its schema, and
  `translations/khovax.pot` is written again after a text changes (README, "Translations"); CI
  fails when it's out of date. CI also fails on a text shown to the player that doesn't go
  through `tr()` with a literal (`packages/game-checks/hardcoded_texts.py`, #1693): today's hits
  wait in its known list, each with the issue that moves it over, and that list only shrinks; a
  deliberate exception goes into its allow list with a reason. A text with two or more values
  names them (`tr("{a} of {b}").format({…})`), so a translation can reorder them; CI fails on a
  `tr()` literal with two or more `%` placeholders (`packages/game-checks/tr_placeholders.py`,
  #1704).
- **Never color alone** (owner's rule, #68): whatever the player tells apart by color (types,
  teams, states) also gets a symbol or a shape, so the game stays colorblind friendly. Every tile
  kind names its symbol in its data (#334; the schema requires it), which the Survey draws.
- **Models follow the model skill** (owner): every 3D model is placed, rigged, textured and
  checked from all sides and in game by the playbook in `.claude/skills/model/SKILL.md` (Blender
  5.2.2 headless from a committed script in `packages/game-models/`, then Godot).
- **New models come only from the owner** (owner's base rule, #1568): agents never make a new model
  from scratch. Its source (the mesh, and the rig if it has one) comes from the owner, or for a
  prop or scenery from a free source (B below); agents import, rig, animate, check and fix it, and
  work on the model tooling.
- **If you need a new model** (owner's ground rule, #1575):
  - A. **A new monster:** file a `question` issue for the owner, one issue per beast (owner's
    ground rule, #1726). The owner makes the model from it.
    - **A brand-new beast:** its vibe, its type and 20 or more base prompts for the image
      generator, as diverse, unique and weird as possible: no generic puppies or cute blobs.
    - **A baby form or any other evolution** (owner, #1754): the best picture of the earlier form
      (a clean render), attached as the reference, and 20 variations of the evolution copypasta
      in the model skill, word for word, each with its own change as a plain sentence and its
      own body line: for a later form `Its body also evolves. It becomes <how> - redesign it.`
      ("more sturdy" by default). **An evolved form redesigns its body, never copies the earlier one** (owner's
      ground rule, 2026-10-30, #1821). Every variation adds something unique, unusual or
      fantastical, such as nine tails, a skateboard, wings, extra heads or a landscape on its
      back, and a form later than the pictured one looks more powerful and more fantastical,
      never the same animal recoloured (owner, #1772). A baby form's prompt says `Draw its baby
      form.` and `Its body also changes. It becomes younger and smaller - redesign it.` (owner's
      pick on #1823, 2026-10-30).
    - **Every beast is rigged and animated by us** (owner, #1732, #1754): a model Meshy can't rig
      ("no rig possible") gets its own skeleton and the full set of clips in Blender (the model
      skill, "Rig").
  - B. **Anything else** (props, scenery): use a free source whose license allows it here (below);
    if there is none, do A.
- **A beast exists only from the owner's vibe or model** (owner's ground rule, #1686): prompt
  suggestions, such as the brainstormed lists for A, make no beast: only the owner's vibe or model
  does. They're never rewritten, asked about or tracked as creatures, and a rule about "every beast"
  covers only the beasts the owner gave a vibe or a model for.
- **Every item has a 3D model** (owner, #1579, #1581): gear, unique items, anything the player
  holds, named in its data (`model`). The content flow checks the gear's; a material's is optional
  until every material has one (#1585, #1586). For now each comes from a free source whose license
  allows it here (B above), like the trees and other non-monster models.
- **Item models look held** (owner's ground rule, #1596): an item's model (gear, unique items,
  materials, anything the player holds or carries) looks like something a hand holds or a player
  carries, such as a pebble for stone. A model with a flat base, made to stand on the ground, is a
  prop or a tile's decoration, never an item in the inventory.
- **The look is cel-shaded eye candy** (owner, #69): monsters and what the camera shows up close
  are medium-poly; only small things that don't read from the top-down camera may be low poly.
  Low-poly packs are placeholders. Every asset in the repository has a license that allows it
  here, kept next to it: CC0, CC BY with credit, or, for an asset the project owns, the
  **Unlicense**, the repository's own license (owner, #1511). The project owns what is built in
  the repository and what the owner makes or generates for it, such as a model generated on a paid
  Meshy plan with the Private license (#1476); its `LICENSE.md` is a copy of the root `LICENSE`, and
  its `SOURCE.md` names the project (or its contributors) as the author and says how the asset was
  made (the Fohossa, the Frostfire Hound and the Drakkudor show how). **Each pack lives in
  `assets/<pack>/`** with its license file and a `SOURCE.md` (title, then `- **Author:**`,
  `- **Source:**`, `- **License:**`); `CREDITS.md` is generated from those by
  `tools/godot/credits.gd`, and CI fails when it's out of date (owner, #69/#70). Commit only what the game uses, not whole packs.

### Testing and CI

- **Every user flow has one coherent e2e test, headless** (owner's rule): one flow for booting
  into the world, one for moving on the hex grid, one for a full domination or combat encounter, and so
  on. A change to an area extends the flow that covers it with new steps; a new flow file
  (`tests/e2e/test_<flow>.gd`) is only for a new user flow. No collections of small unrelated tests,
  and no separate unit tests while the flows already check the same things (owner, #61).
- **Exactly one e2e flow runs on the devices** (owner's rule, #61, #102, #113):
  `tests/apk/apk_flow.gd`, on an Android emulator (`apk-e2e`), in headless Chrome (`web-e2e`,
  the repository's `packages/game-web-e2e/web_e2e.py`) and on the Linux build under a virtual display (`linux-e2e`) in CI,
  started by `game/test_mode.gd` in the test builds only (the `e2e_test` export feature). It
  starts from a fixed seed, scripts its touches per tick, and must end in the same state hash as
  the same flow played headless for the same commit (`tests/e2e/test_apk_flow.gd`, in the
  `rules-compare` job's outcome report, #876): each device job fails on another hash, which is
  the cross-platform determinism lockstep co-op needs. No hash is committed, so a rule change
  updates nothing here. Everything else stays headless. `apk-e2e` is a required check: it passed
  the first time it ran, and the owner asked to enforce it then.
- **The playground is test-only** (owner, #712): `regions/senwel_sael.md` has no exit, so normal
  play never reaches it, and the world starts in Lumwen Hoal. The e2e runner starts its flows there; a
  flow that walks through an exit starts in an instance that has one.
- **The test runner is our own** (`tests/e2e/run_e2e.gd`). The owner kept it over a framework
  for now (#61).
- **Local Godot runs pass `--user-dir=<branch>`** (owner, #786): the e2e runner, the load test, the
  game and screenshot scripts, e.g. `-s res://tests/e2e/run_e2e.gd -- --seed=0
  --user-dir=786-user-dir-flag`. Every worktree shares one `user://` folder otherwise, and parallel
  runs overwrite each other's saves. CI runs without it. Runs through `offscreen.py` need none:
  each gets its own throwaway `user://` folder (#1188), since a `-s` script touches `user://`
  before `--user-dir` applies.
- **A fresh checkout needs `godot --headless --path packages/game --import`** before headless
  runs, and so does a worktree after a rebase brings in a new `class_name` script: with a stale class cache, the
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
- **`gdstyle fmt` strips the leading spaces inside a multi-line string** (#643): a hex grid drawn in
  a `"""` string loses its half-tile indents and reads as another region. Write such a string on
  one line with `\n`.
- **A warning fails a flow too**, unless the flow expects it: before provoking one on purpose (a
  refused world save), it calls `tree.call("expect_warning", "<fragment>")`, and fails if the
  warning never comes. The device flows expect none.
- **A GDScript function that hits a script error returns its type's default** (`""` for `String`), so
  a test can't signal success by returning nothing. The runner counts logged errors during each test
  (a `Logger` added with `OS.add_logger`) and fails the test if any appeared.
- **Commit the `.uid` files** Godot creates next to scripts and resources. Godot only writes them on an
  import, so after adding a script run `godot --headless --path packages/game --import` before
  committing. It generates files rather than checking anything, so it doesn't fall under not rerunning CI locally.
- **Pushing anything under `.github/workflows/` needs workflow rights.** The bot has them through the
  App's Workflows permission. For the owner's own login it is the `workflow` scope
  (`gh auth refresh -h github.com -s workflow`).
- **Never use the `pull_request_target` or `workflow_run` triggers**, and never add self-hosted
  runners to this public repository. **The one exception** (owner's pick on #1867, #1874):
  `approve-cleared.yml` runs on `pull_request_target` (`labeled`, `synchronize`, `edited`), with a
  read-only token, and never checks out or runs anything from the pull request. It approves and
  dismisses as a separate reviewer GitHub App (Pull requests: write, Contents: read), whose key is
  the secret `REVIEWER_APP_KEY` (its ID the variable `REVIEWER_APP_ID`) of the environment
  `approve-cleared`, which only `main` may use: a workflow on any other branch can't approve.
  "Allow GitHub Actions to create and approve pull requests" stays off (owner's pick on #1874).
- **Everything CI downloads is pinned and verified:** actions by full commit SHA (with the tag in a
  comment), and Godot, its export templates, Blender, gdstyle and uv by checksum, with cache keys
  that include the checksum. Bump a version and its checksum together, in `ci.yml` and `release.yml` both.
  Godot's are pinned once, in `.github/actions/setup-godot/action.yml`, the setup every job that
  needs Godot uses (#924), and Blender's in `.github/actions/setup-blender/action.yml` (#1161), with
  the model skill naming the same version. The runner image is named explicitly (`ubuntu-26.04`, not
  `ubuntu-latest`), so a new image arrives on purpose, with the APK build checked, not on GitHub's
  date.
  **The one exception** (owner, #252): the web e2e's Mesa packages come unpinned from the runner
  image's signed Ubuntu archive. They must match the image's own Mesa, and the archive drops a
  superseded version, so an exact pin would break CI on the next security update. **One fallback**
  (#1429), also an exception to the pinning: when updating from the Ubuntu snapshot that Blender's
  container pins fails (`apt-get update --error-on=any`, after apt's retries), its libraries come
  from the live, signed archive, possibly in newer versions than the snapshot's, with a warning on
  the run, rather than a mirror outage turning the run red.
- **Golden replays** (`tests/replays/*.replay`) hold only their inputs, the start and the
  commands, never a hash or the rules (#876): nothing a build computes is committed. CI's
  `rules-compare` job plays them and the APK flow on the commit and on its parent
  (`packages/game-replays/rules_compare.py`, run from the parent's checkout) and fails a difference that
  comes without a new rule change file. If the change is on purpose, add its file to `core/rules_changes/`
  (`<issue>-<slug>.md`: only the `issue` in its frontmatter, then one line on what plays
  differently linking the issue; no `pr`, which CI refuses: the squash commit that added the file
  names it, `git log --diff-filter=A -- core/rules_changes/<file>`, #758; the rules id,
  `RulesChanges`, is a digest of their names, so the folder is append-only: CI refuses a file
  deleted or renamed), and say in the pull request why the game plays out differently; the job's
  summary shows where each replay diverges first. Never declare a change to make a surprise go
  away.
- **Point to the source, never enumerate it** (owner's rule, #99): a list that exists somewhere
  (the presets, the assets, the content files) is read from there, not copied into a workflow, a
  doc or a comment, where it would drift. E.g. CI unpacks the templates
  `packages/game-build/export_templates.py` reads from `export_presets.cfg`, and `CREDITS.md` is
  generated from the assets.
- **No measured numbers in docs or comments** (durations, sizes, counts): they go stale. They belong
  in the PR or issue that measured them.

### Repository and accounts

- **`main` is protected by two rulesets** (#1783). **"main approval"** requires one approval
  (later pushes don't dismiss it). The agent bot is on its bypass list for pull requests only, but
  the merge queue ignores that bypass, so a pull request that isn't user-facing gets its approval
  from the reviewer app through `approve-cleared.yml` instead (above, #1874). **"protect main"**, with no bypass,
  requires no approval itself but pull requests only, review threads resolved, the `headless` and `apk-e2e`
  checks from GitHub Actions green (`models`, the Blender model checks in their own job, #1357, joins
  them once the owner adds it to the ruleset), merged through the merge queue (#329; CI runs on its
  `merge_group` events), squash merges only, no force-push or deletion. The required checks are named after the CI jobs: renaming a job means
  changing the ruleset in the same PR (owner's `gh`). `rules-compare` runs on every pull request
  and in the merge queue but isn't a required check (owner, #894: an agent working around it is
  an accepted risk). A failing `rules-compare` fails the required `apk-e2e` (its first step), so
  the queue won't merge it. **`rules-compare` can't compare** a removed
  golden replay, one whose inputs changed, a changed APK flow or a changed outcome report
  (`tests/replays/outcomes.gd`), and fails on them unless the pull request carries the label
  `outcomes-change` (#889). **The agent applies that label itself** (owner's baseline rule, #899,
  [comment](https://github.com/Coarisfinia/khovax/issues/899#issuecomment-6291010157)) when a pull
  request changes one of those on purpose, and says why in the pull request; the owner's approval
  is the explicit OK. Rerun the job after it's set.
- **Release tags are immutable:** the tag ruleset "immutable release tags" (`refs/tags/v*`, owner,
  #91) blocks deleting, moving and force-updating them, with no bypass; creating one is allowed.
  A wrong release gets a new version, never a moved tag.
- **Pull requests opened with the owner's account can't be approved by the owner.** The bot opens
  them.
- **`.coderabbit.yml` is a copy of the organization's CodeRabbit settings** (owner's rule, #1340):
  both are kept identical by hand, so a change to one goes into the other in the same step (the
  organization's side is the YAML editor in CodeRabbit's organization settings, with the owner's
  browser login). Automatic approvals have no security-risk limit.
- **A stale change request from CodeRabbit is dismissed, not waited out** (owner's rule, #1390):
  GitHub blocks merging while any reviewer's latest review is CHANGES_REQUESTED, even with the
  owner's approval. "protect main" doesn't dismiss reviews on a push, which keeps the owner's
  approval across rebases but keeps CodeRabbit's old change requests too. So:
  1. Answer or fix every CodeRabbit comment, and settle its thread with a `Resolved: <reason>`
     reply (above), only once it is fixed or answered. When no watcher runs, resolve it with
     `resolve-review-thread PRRT_<id>` (owner, #1363). The unresolved threads' ids:
     `agent-gh api graphql -f query='{repository(owner:"Coarisfinia",name:"khovax"){pullRequest(number:<n>){reviewThreads(first:100){nodes{id isResolved}}}}}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not) | .id'`.
  2. Rebase when needed.
  3. Keep auto-merge on and wait: the project watcher dismisses it itself
     (`DISMISS_STALE_BOT_REVIEWS=1`, owner, #1551) once the owner has approved (or the pull request
     is labelled `subagent-cleared` since before the change request, above), CI is green and
     every review thread is settled, whether it was left on an older commit or is on the head and
     was settled with `Resolved:` replies, and reports `REVIEW_DISMISSED`. Agents don't run
     `dismiss-stale-coderabbit` (#1390) any more. The watcher reports `REVIEW_DISMISS_FAILED`
     only once per review, so on the first one tell the owner on the pull request at once.

  Fix what a change request on the head commit asks, then settle each of its threads with a
  `Resolved:` reply: the watcher dismisses it once the owner has approved, or once the main
  session has labelled the pull request `subagent-cleared` after it (above); CodeRabbit never reviews the
  fix push. A person's change request is never dismissed. Never post
  `@coderabbitai` commands yourself: the watcher posts `@coderabbitai resolve` when it is due
  (`RESOLVE_BOT_REVIEWS`, above). `resolve-review-thread` lives in `~/.local/bin` on the owner's machine,
  not in the repository.
- **CodeRabbit's approval no longer counts for merging** (owner's ground rule, #1783, replacing
  #1363's low-risk rule): queueing follows "When a pull request may be queued" above, whatever
  CodeRabbit rates a pull request. Its Triage rule "Merge low-risk changes" (in its app, not
  `.coderabbit.yml`) is paused; if it ever queues a pull request on its own, take it off the queue
  unless that pull request meets the queue rule above: `agent-gh pr merge <n> --disable-auto`,
  and, when it already has a queue entry, the GraphQL `dequeuePullRequest(input:{id:<PR node
  id>})` mutation, which removes it.

### Toolchain

- **The repository is a uv workspace of packages** (#1036, #1101): the root's `pyproject.toml`
  and its `uv.lock`, and one folder per package in `packages/`. `packages/game/` is the Godot
  project (open it in the editor; its `.godot/` cache is per worktree); the others are the Python
  tooling, one workspace member per job: `game-checks/` (CI's checks of the game), `game-replays/`
  (comparing replays, load tests and the APK flow), `game-build/` (export helpers), `game-models/`
  (the Blender model scripts), `game-offscreen/` (Godot on a private display), `game-visuals/`
  (publishing a pull request's pictures on the `assets` branch, #1428), `game-web-e2e/`
  (the web build's e2e in headless Chrome, #1041) and `game-shared/` (what the others share, #1115:
  the one member that is built, as `game_shared`, so the ones depending on it can import it). **The
  tools report through `game_shared.log`** (#1115), which writes GitHub's annotations in CI and plain
  lines elsewhere, never a workflow command of their own. **Any package related to the game gets the
  `game-` prefix** (owner, #1114: *"any package related to the game gets the game- prefix"*), so
  names like `web` or `site` stay free for other parts of the project, such as a website; the game
  itself is `packages/game/`, and a member's uv name is `khovax-<its folder>`. A member with dependencies runs with `--package <its name>`, which installs them. The GDScript tools Godot runs stay in the
  game, in `packages/game/tools/` (`godot/`, and `models/` for the model checks and renders),
  since Godot only runs scripts under `res://`. `tools/scoop/` holds the pinned scoop manifests.
  New tooling is Python, run with uv from the repository's root (`uv run --locked
  packages/<package>/<script>.py`). Godot commands name the project: `--path packages/game`.
- **Only the file endings on the list** (owner, #1095: *"I would like all currently used file
  endings to be allowed, except for .sh and .bat. A new entry requires signoff."*): CI refuses a
  tracked file whose ending isn't in `ENDINGS` in `packages/game-checks/file_endings.py`. **An agent
  never adds an ending without the owner's approval on its issue.** The shell scripts still tracked wait
  in its exception list, each with the issue that ports it, and that list only shrinks.
- **Install tools with scoop** (owner's rule). The development machine runs Windows, so Homebrew isn't
  available.
- **`git push` hung on a Windows credential prompt.** In this repository the repo-local credential
  helper above avoids it. For the owner's own pushes elsewhere, `gh auth setup-git` makes git use the
  `gh` login.
