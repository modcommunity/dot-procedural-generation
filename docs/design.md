# Design

Why dot-procedural-generation is shaped the way it is. The one-line rules are in [CLAUDE.md](../CLAUDE.md).

## Why a document

A generator that instantiates as it goes cannot be compared between two machines, cannot be asserted on by a suite, cannot serve 2D and 3D from one implementation, and cannot be paused half-way. All four land on the design dot-loadout and dot-user-avatar already use: **data first, nodes later, and the builder is the game's.** The first decides it: two peers that both generate cannot compare scene trees; they compare `fingerprint()` and a seed, and the whole comparison is thirty-two characters.

## The validator is the whole point

Generation is easy; generation that cannot produce an unplayable round is the problem. The family has the lesson from the other direction: eight imported maps passed every assertion about their zones while five of them could not be finished, because every assertion was about a zone existing and none about the zones adding up to a run ([bugs-found](../../../docs/bugs-found.md#found-by-running-the-examples)). *A map that loads is not a level.*

`DotProcGenValidate` floods from a marker and refuses:

- a marker that cannot be reached from the start (`must_reach`),
- a start inside a wall,
- a map that is technically connected and **mostly wasted** (`min_connected_fraction`): one thread of corridor to a far wing satisfies "everything is reachable" while nine tenths of the space is a sealed pocket, which reads as a generator that makes small maps rather than large broken ones.

`fill_unreachable` (on by default) is usually better than failing: a cave with its sealed pockets filled in is a good cave, and with them left in it has rooms that exist for a navigation mesh, a light bake and a spawn placer but not for a player.

A refusal is caught by the pipeline, which retries up to `max_attempts`. **The attempt is mixed into the seed, not added**: `seed + 1` is somebody else's world, so a failure on seed 41 would hand a player the map seed 42 should have produced, and two people comparing notes would disagree about what 41 looks like. The suite asserts a retry is not simply the next seed's map.

## One stream per step

With a single shared generator, inserting a step anywhere shifts every later number: adding a rubble pass at the end changes the room layout, a shared seed stops producing the shared map, and last week's replay plays back as a different world. `DotProcGenRandom.stream(name)` hashes the name into the key, so two steps never disturb each other however much either draws; the suite asserts 500 draws from one step's stream leave another's untouched.

**Two steps may not share a name**: `DotProcGenPipeline.validate()` refuses it. Two steps with one name share one stream, so the second continues where the first left off, and reordering them changes both.

The design is counter-based and splittable by name, with 53 bits in a unit and a logical right shift (GDScript's `>>` is arithmetic, so the top of the mixer's output is otherwise a run of ones for half of every value). What crosses into a game is a **seed**, through `DotProcGenPipeline.seed_source`, duck-typed on `seed_for(name)`; dot-core's `DotRandomManager` answers it. `DotProcGenRandom` is a second implementation of dot-core's `DotRandomStream` design; see the open item in [CLAUDE.md](../CLAUDE.md#open).

## The pieces

| | |
| --- | --- |
| `DotProcGenDoc` | The grid, the rooms, the links, the markers; `reachable_from`, `fingerprint`, `to_ascii`. |
| `DotProcGenRandom` | A counter-based splittable stream. |
| `DotProcGenStep` | One pass. Declares its own fingerprint keys. |
| `DotProcGenRooms` | BSP. A connection plan for free, and no slower as the map fills. |
| `DotProcGenCave` | Cellular automata. Produces sealed pockets by construction. |
| `DotProcGenConnect` | A spanning tree, plus loops on purpose. |
| `DotProcGenMarkers` | Where things go. One step configured, not a class per kind. |
| `DotProcGenValidate` | The step that makes this shippable. |
| `DotProcGenPipeline` | The list, the retries and the fingerprint. |
| `DotProcGenRunner` | A step per frame, on the main thread. |

## Decisions

**BSP rather than rejection sampling.** "Place rectangles at random, reject overlaps" gets slower as the map fills, so a 64×64 map generates instantly and a 256×256 one with the same settings takes seconds: a frame hitch on the one map somebody made big, not a bug anybody can find. BSP is also a tree, which is a connection plan for free.

**A spanning tree, and then loops.** `extra_loops` defaults to 3 and is the difference between a place and a sequence. A tree has exactly one route between any two rooms: every fight is a corridor and every retreat is the way you came. The suite asserts more links than a spanning tree would have.

**Cellular automata smooths into a copy.** Reading the grid you are writing means a cell sees its left neighbour's new value and its right neighbour's old one, which drags every feature to one side, invisibly, because the result still looks like a plausible cave.

**Slicing is between steps, never inside one.** A step is the unit that leaves the document consistent; half a carving pass is a document with a partial room in it. The suite asserts the sliced and the blocking runs produce the **same fingerprint**, which makes slicing an implementation detail rather than a second code path.

**Main thread, not a worker.** `DotPlatform.has_threads()` is false on most web templates. `DotProcGenRunner` slices inside `frame_budget_ms`, for the reason `DotScheduler` does.

## Deliberately not here

- **A builder.** Turning a grid into a `TileMap`, a `GridMap` or extruded geometry is the game's. `to_ascii()` is the debugging one.
- **Noise terrain.** `FastNoiseLite` takes an explicit seed and is deterministic; a heightmap step would be a thin wrapper a game writes in six lines.
- **Wave function collapse.** A good algorithm and a large one, wanting a tile-adjacency format that is a project in itself. `DotProcGenStep` is the extension point.
- **Networking.** The seed and the fingerprint are two values a game sends through the transport it already has.
