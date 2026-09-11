# dot-procedural-generation

Generation that produces a document, and refuses one nobody could finish.

**The distributable is `addons/dot_procedural_generation/`.** It requires [dot-core](../dot-core), a separate repository, and nothing else.

```bash
ln -s ../../dot-core/addons/dot_core addons/dot_core
```

The folder is `dot_procedural_generation` rather than `dot_procgen` because **bootstrap maps an addon folder to its repository by replacing `_` with `-`**, with no special cases anywhere. A shorter folder name would need one, and a special case in a list is how every stale list in this tree started. The classes are `DotProcGen*`, which is the same split dot-fps-controller already has.

## Why a document

A generator that instantiates as it goes cannot be compared between two machines, cannot be asserted on by a suite, cannot serve 2D and 3D from one implementation, and cannot be paused half-way. Those are four separate arguments and they all land on the same design, which is the one dot-loadout and dot-user-avatar already use: **data first, nodes later, and the builder is the game's.**

The one that decides it is the first. Two peers that both generate cannot check they agree by looking at their scene trees; they compare `fingerprint()` and a seed, and the whole comparison is thirty-two characters.

## The validator is the whole point, and it is the part everybody leaves out

Generation is easy. Generation that cannot produce an unplayable round is the problem, and this family already has the lesson from the other direction: **eight imported maps passed 168 assertions about their zones while five of them could not be finished**, because every assertion was about a zone existing and none was about the zones adding up to a run. *A map that loads is not a level.*

`DotProcGenValidate` floods from a marker and refuses:

- a marker that cannot be reached from the start,
- a start inside a wall,
- a map that is technically connected and **mostly wasted** — one thread of corridor to a far wing satisfies "everything is reachable" while nine tenths of the space is a sealed pocket nobody will see, which reads as a generator that makes small maps rather than one making large broken ones.

`fill_unreachable` is usually better than failing: a cave with its sealed pockets filled in is a good cave, and the same cave with them left in has rooms that exist for a navigation mesh, a light bake and a spawn placer but not for a player.

A refusal is caught by the pipeline, which retries. **The attempt is mixed into the seed, not added** — `seed + 1` is somebody else's world, so a failure on seed 41 would hand a player the map seed 42 should have produced and two people comparing notes would disagree about what 41 looks like. The suite asserts a retry is not simply the next seed's map.

## One stream per step, and why it is not optional

With a single shared generator, inserting a step anywhere shifts every later number. Adding a rubble pass at the end changes the room layout; a seed somebody shared stops producing the map they shared it for; and a replay recorded last week plays back as a different world.

`DotProcGenRandom.stream(name)` hashes the name into the key, so two steps never disturb each other however much either draws. The suite asserts that exactly: 500 draws from one step's stream leave another's untouched.

**Two steps may not share a name** — `DotProcGenPipeline.validate()` refuses it. Two steps with one name share one stream, so the second continues where the first left off, and reordering them then changes both. Nobody expects that from a rename.

### It is a second implementation on purpose

dot-randomness has this class. Using it would make it a hard dependency, which the family forbids, so this is the same decision dot-browser made when it wrote a second implementation of dot-server's wire format rather than depending on it.

What is shared is the **design**, not the numbers: counter-based, splittable by name, 53 bits in a unit, a logical right shift because GDScript's `>>` is arithmetic and the top of the mixer's output is otherwise a run of ones for half of every value. Nothing anywhere compares dot-procgen's numbers with dot-randomness'; what crosses the boundary is a **seed**, through `seed_source`, duck-typed on `seed_for(name)`.

## What building it found

**An untyped array literal in a `for` loop is a parse error, not a warning.** `for d in [Vector2i(1,0), ...]` gives `d` as a Variant, `x + d.x` is then a Variant, and `var nx := x + d.x` fails with *"Cannot infer the type of nx"* — pointing at the variable rather than at the literal three lines up that caused it. Every script in the addon failed to compile behind it, which is the cascade this tree already knows from a missing addon link. `const NEIGHBOURS: Array[Vector2i]` is the fix and it is worth doing for its own sake.

And one in the suite: `Rect2i(1, 1, 3, 3)` is **end-exclusive**, covering x and y in `[1, 4)`. The check expected ten floor cells and got nine. Off by one in grid code is the commonest arithmetic mistake there is, which is why the count is asserted rather than the corners.

## The pieces

| | |
| --- | --- |
| `DotProcGenDoc` | The grid, the rooms, the links, the markers. Plus `reachable_from`, `fingerprint` and `to_ascii`. |
| `DotProcGenRandom` | A counter-based splittable stream. A second implementation, deliberately. |
| `DotProcGenStep` | One pass. Declares its own fingerprint keys. |
| `DotProcGenRooms` | BSP. Gives a connection plan for free, and does not get slower as the map fills. |
| `DotProcGenCave` | Cellular automata. Produces sealed pockets by construction; that is what it is. |
| `DotProcGenConnect` | A spanning tree, plus loops on purpose. |
| `DotProcGenMarkers` | Where things go. One step configured, not a class per kind. |
| `DotProcGenValidate` | The step that makes this shippable. |
| `DotProcGenPipeline` | The list, the retries and the fingerprint. |
| `DotProcGenRunner` | A step per frame, on the main thread. |

## Decisions

### BSP rather than rejection sampling

"Place rectangles at random, reject overlaps" is the obvious approach and is wrong in a way that only shows on a big map: it gets slower as the map fills, so a 64×64 map generates instantly and a 256×256 one with the same settings takes seconds. The failure is a frame hitch on the one map somebody made big, not a bug anybody can find. BSP is also a tree, which is a connection plan for free.

### A spanning tree, and then loops

`extra_loops` defaults to 3 and is the difference between a place and a sequence. A tree has exactly one route between any two rooms: every fight is a corridor and every retreat is the way you came. The suite asserts there are *more* links than a spanning tree would have.

### Cellular automata smooths into a copy

Reading the grid you are writing means a cell sees its left neighbour's new value and its right neighbour's old one, which drags every feature to one side. It is invisible in a screenshot, because the result still looks like a plausible cave.

### Slicing is between steps, never inside one

A step is the unit that leaves the document consistent. Half a carving pass is a document with a partial room in it, and a half-generated document is the one thing worse than a slow generator. The suite asserts the sliced and the blocking runs produce the **same fingerprint**, which is what makes slicing an implementation detail rather than a second code path.

### Main thread, not a worker

`DotPlatform.has_threads()` is false on a web template that was not built for them, which is most of them. Same reason `DotScheduler` slices inside a frame budget.

## Things deliberately not here

- **A builder.** Turning a grid into a `TileMap`, a `GridMap` or extruded geometry is the game's, and every game wants it differently. `to_ascii()` is the debugging one.
- **Noise terrain.** Godot ships `FastNoiseLite` with an explicit seed and it is deterministic; a heightmap step would be a thin wrapper over it, and a game that wants one writes six lines.
- **Wave function collapse.** It is a good algorithm and a large one, and it wants a tile-adjacency format that is a project in itself. `DotProcGenStep` is the extension point.
- **Networking.** The seed and the fingerprint are two numbers a game sends through the transport it already has. A wire format here would be a third copy of something dot-net already does.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
timeout 180 godot --headless --path . res://examples/procgen_selftest.tscn
```

8 sections, 61 checks. **Do not add a check that asserts a particular cell is floor.** That asserts the mixer, breaks whenever a step gains a setting, and says nothing about whether the map is any good. Assert the properties: nothing reaches the border, no two rooms overlap, every marker is reachable, there are more corridors than a tree, two runs of one seed agree.
