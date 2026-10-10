# History

What building it found. The rules they left are in [CLAUDE.md](../CLAUDE.md).

## An untyped array literal in a `for` loop is a parse error

`for d in [Vector2i(1,0), ...]` gives `d` as a Variant, `x + d.x` is then a Variant, and `var nx := x + d.x` fails with "Cannot infer the type of nx", pointing at the variable rather than the literal three lines up. Every script in the addon failed to compile behind it. `const NEIGHBOURS: Array[Vector2i]` in `DotProcGenDoc` is the fix, and worth doing for its own sake. The general trap is in [gdscript-hazards.md](../../../docs/gdscript-hazards.md).

## `Rect2i` is end-exclusive

`Rect2i(1, 1, 3, 3)` covers x and y in `[1, 4)`. A suite check expected ten floor cells and got nine. Off by one in grid code is the commonest arithmetic mistake there is, which is why the suite asserts counts rather than corners.
