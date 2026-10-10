# dot-procedural-generation

Generation that produces a document, and refuses one nobody could finish: rooms (BSP), caves (cellular automata), connections with loops, markers, a validator that floods from the start, a retrying pipeline with a fingerprint, and a runner that slices across frames.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to procedural generation.

**The distributable is `addons/dot_procedural_generation/`.** It requires [dot-core](../dot-core) and nothing else (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored). The classes are `DotProcGen*`. The folder is not `dot_procgen` because bootstrap and dot-ci map an addon folder to its repository by replacing `_` with `-` (the weapon pack is the one listed exception), and a shorter folder would need another.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | anything: why a document, the validator and retries, one stream per step, the pieces, BSP, loops, smoothing, slicing, what is not here |
| [docs/history.md](docs/history.md) | the untyped-literal parse failure, `Rect2i` end-exclusivity |

## Layout

| Path | What |
| --- | --- |
| `core/dot_procgen_doc.gd` | `DotProcGenDoc`: grid, rooms, links, markers; `reachable_from`, `fingerprint`, `to_ascii` |
| `core/dot_procgen_random.gd` | `DotProcGenRandom`: counter-based stream, `stream(name)`, `at(index)` |
| `core/dot_procgen_step.gd` | `DotProcGenStep`: one pass, the extension point |
| `core/dot_procgen_pipeline.gd` | `DotProcGenPipeline`: steps, `validate()`, retries (`max_attempts`), `seed_source` |
| `steps/` | `DotProcGenRooms`, `...Cave`, `...Connect` (`extra_loops`), `...Markers`, `...Validate` (`fill_unreachable`, `min_connected_fraction`) |
| `runtime/dot_procgen_runner.gd` | `DotProcGenRunner`: a step per frame within `frame_budget_ms` |
| `examples/procgen_selftest.tscn` | the suite |

Paths except `examples/` are in `addons/dot_procedural_generation/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 180 godot --headless --path . res://examples/procgen_selftest.tscn`.

**Never add a check that a particular cell is floor.** That asserts the mixer, breaks whenever a step gains a setting, and says nothing about whether the map is any good. Assert properties: nothing reaches the border, no two rooms overlap, every marker is reachable, more corridors than a tree, two runs of one seed agree.

## Rules that bite

- Generation produces a `DotProcGenDoc`; nodes are the game's builder. Peers compare `fingerprint()` and the seed. [design](docs/design.md#why-a-document)
- Every pipeline that ships ends in `DotProcGenValidate`; prefer `fill_unreachable` to failing. [design](docs/design.md#the-validator-is-the-whole-point)
- A retry mixes the attempt into the seed; never `seed + attempt`. [design](docs/design.md#the-validator-is-the-whole-point)
- Each step draws from `stream(its name)`; no two steps share a name (`validate()` refuses). [design](docs/design.md#one-stream-per-step)
- A step's settings go in its declared fingerprint keys. [design](docs/design.md#the-pieces)
- Rooms by BSP, never rejection sampling; cellular automata write into a copy. [design](docs/design.md#decisions)
- Slice only between steps, on the main thread; sliced and blocking runs must give the same fingerprint. [design](docs/design.md#decisions)
- Type array literals you iterate (`const X: Array[Vector2i]`); `Rect2i` is end-exclusive. [history](docs/history.md)

Deliberately not here: a builder, noise terrain, wave function collapse, networking. [design](docs/design.md#deliberately-not-here)

## Open

- `DotProcGenRandom` is a second implementation of dot-core's `DotRandomStream` (same SplitMix64 constants, counter-based, `stream(name)`, `at(index)`). Its stated reason, that dot-randomness could not be a dependency, no longer holds: dot-randomness was folded into dot-core's `random/`. Not yet converted. Converting changes every generated map for a given seed, so it wants a decision on whether existing seeds must keep their maps.
