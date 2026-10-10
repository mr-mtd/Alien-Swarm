class_name ModelAnimator
extends Node
## Plays named animations on an imported, rigged model (a .glb), whatever the import produced:
## - binds every skinned mesh to the model's Skeleton3D (an import can leave a mesh's
##   skeleton path empty, which keeps it frozen in its bind pose while the bones move),
## - copies the clips into an AnimationLibrary of its own under fixed names, so renamed
##   clips ("Idle-loop", "lib/Walk", "Jump_Attack", ...) and import loop settings don't matter.

## The instanced model scene (the .glb) to drive.
@export var model: Node3D
## Cross-fade time between animations, in seconds.
@export var blend_time := 0.15
## Name of the AnimationLibrary the clips are copied into.
@export var library_name := &"model"
## Clips to look for, as clip name -> whether it loops. Names match the model's clips ignoring
## case, spaces, "-", "_", any library prefix and a "loop"/"cycle" suffix.
@export var clips := {&"idle": true, &"walk": true, &"attack": false}

var _player: AnimationPlayer
var _log_name := "ModelAnimator"


func _ready() -> void:
	_log_name = get_script().get_global_name()
	if not model:
		push_error("%s: no model assigned." % _log_name)
		return
	var skeleton := model.find_children("*", "Skeleton3D", true, false)
	_player = _first(model.find_children("*", "AnimationPlayer", true, false))
	if skeleton.is_empty() or not _player:
		push_error("%s: %s has no Skeleton3D or AnimationPlayer. Reimport the model with animations enabled." % [_log_name, model.name])
		_player = null
		return
	_bind_meshes(skeleton[0])
	_build_library()


## True once the model was set up and every clip in `clips` was found.
func is_ready() -> bool:
	if not _player:
		return false
	for clip: StringName in clips:
		if not has_clip(clip):
			return false
	return true


func has_clip(clip: StringName) -> bool:
	return _player != null and _player.has_animation(_full(clip))


## Loops `clip`, cross-fading from whatever is playing. Calling it again only changes the speed.
func play_loop(clip: StringName, speed := 1.0) -> void:
	if not has_clip(clip):
		return
	if _player.current_animation != _full(clip):
		_player.play(_full(clip), blend_time)
	_player.speed_scale = speed


## Plays `clip` from its first frame, even if it is already playing.
func play_once(clip: StringName, speed := 1.0) -> void:
	if not has_clip(clip):
		return
	_player.speed_scale = 1.0
	_player.play(_full(clip), 0.05, speed)
	_player.seek(0.0, true)


## Length of `clip` in seconds at normal speed, or 0 if it is missing.
func clip_length(clip: StringName) -> float:
	return _player.get_animation(_full(clip)).length if has_clip(clip) else 0.0


## Freezes the model in its current pose.
func freeze() -> void:
	if _player:
		_player.pause()


func _full(clip: StringName) -> StringName:
	return StringName("%s/%s" % [library_name, clip])


func _bind_meshes(skeleton: Skeleton3D) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not mesh.skin and not _has_bones(mesh):
			continue
		if mesh.get_node_or_null(mesh.skeleton) is Skeleton3D:
			print_verbose("%s: %s is bound to %s." % [_log_name, mesh.name, mesh.get_node(mesh.skeleton).name])
		else:
			print("%s: %s had no skeleton (path '%s'); binding it to %s." % [_log_name, mesh.name, mesh.skeleton, skeleton.name])
			mesh.skeleton = mesh.get_path_to(skeleton)


func _build_library() -> void:
	var library := AnimationLibrary.new()
	for clip: StringName in clips:
		var source := _find_clip(clip)
		if source == &"":
			push_error("%s: no '%s' animation in %s. Found: %s" % [_log_name, clip, model.name, _player.get_animation_list()])
			continue
		var anim: Animation = _player.get_animation(source).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR if clips[clip] else Animation.LOOP_NONE
		library.add_animation(clip, anim)
		print_verbose("%s: %s/%s <- '%s' (%.2fs)" % [_log_name, library_name, clip, source, anim.length])
	if _player.has_animation_library(library_name):
		_player.remove_animation_library(library_name)
	_player.add_animation_library(library_name, library)


## Finds the model's clip whose simplified name matches `clip`'s.
func _find_clip(clip: StringName) -> StringName:
	var wanted := _simplify(clip)
	for anim_name in _player.get_animation_list():
		if String(anim_name).begins_with(library_name + "/"):
			continue
		if _simplify(anim_name) == wanted:
			return anim_name
	return &""


static func _simplify(anim_name: String) -> String:
	var short := anim_name.get_slice("/", anim_name.get_slice_count("/") - 1).to_lower()
	for c in ["-", "_", " "]:
		short = short.replace(c, "")
	for suffix in ["loop", "cycle"]:
		if short.length() > suffix.length():
			short = short.trim_suffix(suffix)
	return short


static func _has_bones(mesh: MeshInstance3D) -> bool:
	if not mesh.mesh:
		return false
	for i in mesh.mesh.get_surface_count():
		if mesh.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_BONES:
			return true
	return false


static func _first(nodes: Array[Node]) -> Node:
	return nodes[0] if not nodes.is_empty() else null
