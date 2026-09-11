This is the **procedural generation** asset for TMC's **Dot** collection. It adds generated levels as an ordered pipeline of deterministic steps over a document, with a validator that refuses a map nobody could finish.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

## It produces a document, not a world

A generator that instantiates nodes as it goes cannot be compared between two machines, cannot be asserted on by a suite, cannot serve a 2D and a 3D game from one implementation, and cannot be paused half-way. `DotProcGenDoc` is a grid, a list of rooms, a list of links and a list of markers; a **builder** turns it into nodes, and the builder is the game's.

What that buys, in order of how much it matters:

- **Two peers agree by comparing a hash.** A seed and a `fingerprint()`, not a map.
- **"Is it finishable?" is a question you can ask.** It is a flood fill over a grid.
- **One generator, two dimensions.** A top-down game reads the grid as tiles; a first-person game extrudes it.
- **It can be generated over several frames** without anybody being able to walk into a half-built world.

## The validator is the whole point

Generation is easy. Generation that cannot produce an unplayable round is the problem.

A cellular-automata cave has sealed pockets *by construction*. A room placer can wall off a start it carved earlier. A scattered objective lands in a chamber with no door about one seed in thirty. **Every one of those is invisible to every other kind of check.** The map is well formed, the counts are right, the rooms are the size they should be, and a player walks in and cannot finish.

```gdscript
var check := DotProcGenValidate.new()
check.from_kind = &"spawn"
check.min_connected_fraction = 0.6     # connected AND not mostly wasted
check.fill_unreachable = true          # usually better than failing
```

Failing is not a crash: the pipeline catches it and **tries another seed**, up to `max_attempts`. The attempt is *mixed* into the seed rather than added, because `seed + 1` is somebody else's world, and a failure on seed 41 would quietly hand a player the map seed 42 should have produced.

## Every step draws from its own named stream

With one shared generator, inserting a step anywhere shifts every later random number, so adding a "scatter some rubble" pass changes the room layout, and a seed somebody shared stops producing the map they shared it for.

`DotProcGenRandom` derives a child stream by hashing a name, and two children never disturb each other however often either is used. A step added at the end changes nothing before it. (It is a second implementation of what the randomness asset has, deliberately: only dot-core may be a hard dependency, and it is the same choice the server-browser asset made about a wire format. What a game's randomness asset supplies is the **seed**, through `seed_source`.)

## A spanning tree is a bad level

`DotProcGenConnect` builds a minimum spanning tree, the cheapest corridors that guarantee one piece, and then adds `extra_loops` more. A tree has exactly one route between any two rooms, so every fight is a corridor, every retreat is the way you came, and the map reads as a sequence rather than as a place. Every hand-built level in the genre has loops in it.

## Using it

```gdscript
var p := DotProcGenPipeline.new()
p.width = 64
p.height = 64
p.add(rooms).add(corridors).add(spawns).add(validate)
p.seed_source = rng                       # optional; takes the session's seed

var res := p.generate(seed)
if res.ok:
    build(res.value as DotProcGenDoc)
```

Or sliced across frames, one step at a time, on the main thread, because a web template without threads is most of them:

```gdscript
runner.pipeline = p
runner.finished.connect(_build)
runner.begin(seed)
```

The sliced and the blocking runs produce **exactly the same map**, which is what makes slicing an implementation detail.

## `to_ascii()` is worth more than it looks

Every generator bug this kind of code has is visible in ten lines of text and invisible in every assertion that does not print one. Print the map when a check fails.

## Installing

Copy `addons/dot_procedural_generation/` and [`dot-core`](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable it in **Project → Project Settings → Plugins**.

## Dependencies

[dot-core](https://github.com/modcommunity/dot-core). Nothing else.

## License

MIT.
