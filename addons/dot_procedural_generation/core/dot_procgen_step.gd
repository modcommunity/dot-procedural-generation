@tool
class_name DotProcGenStep
extends Resource

## One pass over the document. A pipeline is a list of these.
##
## [b]Every step takes its own named stream.[/b] That is not a style choice — it is what
## makes a pipeline editable. With one shared generator, inserting a step anywhere shifts
## every later random number, so adding a "scatter some rubble" pass changes the room
## layout and a seed somebody shared stops producing the map they shared it for.
## [DotProcGenRandom] derives a child stream by hashing a name, and two children never disturb
## each other however often either is used, so a step added at the end changes nothing
## before it.
##
## The stream is passed in rather than held, because a step is a [Resource] and a resource
## that holds a generator is a resource whose behaviour depends on how many times it has
## been used.

## A name for the stream this step draws from, and for logs.
##
## [b]Changing it changes the map.[/b] It is hashed into the key, so a rename is a
## different world from the same seed — which is worth knowing before renaming one.
@export var step_name: StringName = &"step"

## Whether this step runs at all. A pipeline keeps it in the list either way.
##
## Disabling rather than deleting matters for the reason above: deleting a step from the
## middle of a pipeline does not change any other step's numbers here, but a pipeline that
## has been edited is one whose fingerprint has changed, and keeping the entry makes the
## difference visible in a diff.
@export var enabled: bool = true


## Does the work. [param stream] is this step's own.
func apply(_doc: DotProcGenDoc, _stream: DotProcGenRandom) -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "this step does nothing")


## Checked before a run starts, so a malformed pipeline fails at boot.
func validate() -> DotResult:
	return DotResult.success(null)


## What this step contributes to a pipeline's fingerprint.
##
## Every exported value that changes the output belongs in here. A step whose settings are
## not in its fingerprint is a step two peers can disagree about while both reporting the
## same hash — which is the worst possible failure, because the check that exists to catch
## a mismatch is the thing that hides it.
func fingerprint() -> String:
	var parts := PackedStringArray([String(step_name), str(enabled)])
	for key in _fingerprint_keys():
		parts.append("%s=%s" % [key, str(get(key))])
	return ":".join(parts)


## The exported property names that change the output. Override in every subclass.
func _fingerprint_keys() -> PackedStringArray:
	return PackedStringArray()


func describe_line() -> String:
	return "%-18s %s" % [String(step_name), "" if enabled else "(disabled)"]
