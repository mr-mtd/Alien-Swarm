class_name StriderAnimator
extends Node
## Plays the Emberline Strider's Idle, Walk and Attack animations.
##
## Sets the imported model up at runtime so it animates whatever the import produced:
## - binds every skinned mesh to the model's Skeleton3D (an import can leave a mesh's
##   skeleton path empty, which keeps it frozen in its bind pose while the bones move),
## - copies the clips into an AnimationLibrary of its own under fixed names, so renamed
##   clips ("Idle-loop", "lib/Walk", ...) and import loop settings don't matter.

## The instanced model scene (the .glb) to drive.
@export var model: Node3D
## Cross-fade time between animations, in seconds.
@export var blend_time := 0.15

const LIBRARY := &"strider"
const IDLE := &"strider/idle"
const WALK := &"strider/walk"
const ATTACK := &"strider/attack"

var _player: AnimationPlayer


func _ready() -> void:
	if not model:
		push_error("StriderAnimator: no model assigned.")
		return
	var skeleton := model.find_children("*", "Skeleton3D", true, false)
	_player = _first(model.find_children("*", "AnimationPlayer", true, false))
	if skeleton.is_empty() or not _player:
		push_error("StriderAnimator: %s has no Skeleton3D or AnimationPlayer. Reimport the model with animations enabled." % model.name)
		_player = null
		return
	_bind_meshes(skeleton[0])
	_build_library()


## True once the model was set up and all three animations were found.
func is_ready() -> bool:
	return _player != null and _player.has_animation(IDLE) and _player.has_animation(WALK) and _player.has_animation(ATTACK)


func play_idle() -> void:
	_loop(IDLE, 1.0)


func play_walk(speed := 1.0) -> void:
	_loop(WALK, speed)


## Plays the attack from its first frame, even if an attack is already playing.
func play_attack(speed := 1.0) -> void:
	if not _player or not _player.has_animation(ATTACK):
		return
	_player.speed_scale = 1.0
	_player.play(ATTACK, 0.05, speed)
	_player.seek(0.0, true)


## Freezes the model in its current pose.
func freeze() -> void:
	if _player:
		_player.pause()


func _loop(anim: StringName, speed: float) -> void:
	if not _player or not _player.has_animation(anim):
		return
	if _player.current_animation != anim:
		_player.play(anim, blend_time)
	_player.speed_scale = speed


func _bind_meshes(skeleton: Skeleton3D) -> void:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if not mesh.skin and not _has_bones(mesh):
			continue
		if mesh.get_node_or_null(mesh.skeleton) is Skeleton3D:
			print("StriderAnimator: %s is bound to %s." % [mesh.name, mesh.get_node(mesh.skeleton).name])
		else:
			print("StriderAnimator: %s had no skeleton (path '%s'); binding it to %s." % [mesh.name, mesh.skeleton, skeleton.name])
			mesh.skeleton = mesh.get_path_to(skeleton)


func _build_library() -> void:
	var library := AnimationLibrary.new()
	var sources := {&"idle": Animation.LOOP_LINEAR, &"walk": Animation.LOOP_LINEAR, &"attack": Animation.LOOP_NONE}
	for clip: StringName in sources:
		var source := _find_clip(clip)
		if source == &"":
			push_error("StriderAnimator: no '%s' animation in the model. Found: %s" % [clip, _player.get_animation_list()])
			continue
		var anim: Animation = _player.get_animation(source).duplicate()
		anim.loop_mode = sources[clip]
		library.add_animation(clip, anim)
		print("StriderAnimator: %s/%s <- '%s' (%.2fs)" % [LIBRARY, clip, source, anim.length])
	if _player.has_animation_library(LIBRARY):
		_player.remove_animation_library(LIBRARY)
	_player.add_animation_library(LIBRARY, library)


## Finds a clip by base name, ignoring case, any library prefix and loop suffixes.
func _find_clip(base_name: String) -> StringName:
	for anim_name in _player.get_animation_list():
		if String(anim_name).begins_with(LIBRARY + "/"):
			continue
		var short := String(anim_name).get_slice("/", String(anim_name).get_slice_count("/") - 1).to_lower()
		for suffix in ["-loop", "_loop", "-cycle", "_cycle"]:
			short = short.trim_suffix(suffix)
		if short == base_name:
			return anim_name
	return &""


static func _has_bones(mesh: MeshInstance3D) -> bool:
	if not mesh.mesh:
		return false
	for i in mesh.mesh.get_surface_count():
		if mesh.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_BONES:
			return true
	return false


static func _first(nodes: Array[Node]) -> Node:
	return nodes[0] if not nodes.is_empty() else null
