class_name Player
extends CharacterBody3D
## Third-person player: camera-relative movement, jump, dodge roll and a three-hit claw combo.
## Drives the Emberline Strider model's Idle, Walk and Attack animations.

signal health_changed(current: int, maximum: int)
signal died

@export_group("Movement")
@export var move_speed := 6.0
@export var acceleration := 40.0
@export var jump_velocity := 5.5
@export var turn_speed := 12.0

@export_group("Dodge")
@export var dodge_speed := 14.0
@export var dodge_duration := 0.25
@export var dodge_cooldown := 0.6

@export_group("Combat")
@export var max_health := 100
@export var attack_damage := 20
## Extra damage added for each step further into the combo.
@export var combo_damage_bonus := 10
@export var attack_knockback := 6.0
## Invulnerability time after taking a hit.
@export var hurt_invulnerability := 0.5

@export_group("Animation")
## Playback speed of the Attack animation (1.0 is the speed it was authored at).
@export var attack_anim_speed := 1.4
## Point in the Attack animation, in seconds, where the claws connect and damage is dealt.
@export var attack_hit_time := 0.5
## Point in the Attack animation, in seconds, where the swing is over and the next can start.
@export var attack_end_time := 1.0
## Walk animation playback speed when moving at full move_speed.
@export var walk_anim_speed := 1.3
@export var anim_blend_time := 0.15

@export_group("Camera")
@export var mouse_sensitivity := 0.003
@export var min_pitch := deg_to_rad(-60.0)
@export var max_pitch := deg_to_rad(20.0)

var health := 0
var is_dead := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _move_direction := Vector3.ZERO
var _dodge_time_left := 0.0
var _dodge_cooldown_left := 0.0
var _dodge_direction := Vector3.ZERO
var _invulnerable_time_left := 0.0
var _attacking := false
var _combo_queued := false
var _hurt_material := StandardMaterial3D.new()

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _model: Node3D = $Model
@onready var _hitbox: Area3D = $Model/Hitbox
@onready var _anim: AnimationPlayer = $Model/Strider.find_child("AnimationPlayer") as AnimationPlayer
@onready var _meshes: Array[Node] = $Model/Strider.find_children("*", "MeshInstance3D")
@onready var _idle_anim := _find_anim(["Idle", "Idle-loop"])
@onready var _walk_anim := _find_anim(["Walk", "Walk-loop"])
@onready var _attack_anim := _find_anim(["Attack"])


func _ready() -> void:
	health = max_health
	_hurt_material.albedo_color = Color(1, 0.2, 0.2)
	_hurt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for anim_name in [_idle_anim, _walk_anim]:
		if anim_name != &"":
			_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_play(_idle_anim)
	health_changed.emit(health, max_health)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		_spring_arm.rotation.x = clampf(
			_spring_arm.rotation.x - event.relative.y * mouse_sensitivity, min_pitch, max_pitch
		)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		move_and_slide()
		return

	_dodge_cooldown_left = maxf(_dodge_cooldown_left - delta, 0.0)
	_invulnerable_time_left = maxf(_invulnerable_time_left - delta, 0.0)

	# The pivot only yaws (pitch lives on the spring arm), so its basis gives a flat direction.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_move_direction = _camera_pivot.global_basis * Vector3(input.x, 0.0, input.y)
	_move_direction.y = 0.0
	_move_direction = _move_direction.normalized()

	if Input.is_action_just_pressed("attack"):
		if _attacking:
			_combo_queued = true
		elif _dodge_time_left <= 0.0:
			_attack_sequence()

	if (
		Input.is_action_just_pressed("dodge")
		and _dodge_cooldown_left <= 0.0
		and is_on_floor()
		and not _attacking
	):
		_dodge_direction = _move_direction if _move_direction != Vector3.ZERO else _forward()
		_dodge_time_left = dodge_duration
		_dodge_cooldown_left = dodge_cooldown
		_invulnerable_time_left = maxf(_invulnerable_time_left, dodge_duration)

	if _dodge_time_left > 0.0:
		_dodge_time_left -= delta
		velocity.x = _dodge_direction.x * dodge_speed
		velocity.z = _dodge_direction.z * dodge_speed
		_face(_dodge_direction, delta)
	else:
		var speed := move_speed * (0.3 if _attacking else 1.0)
		velocity.x = move_toward(velocity.x, _move_direction.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, _move_direction.z * speed, acceleration * delta)
		if Input.is_action_just_pressed("jump") and is_on_floor() and not _attacking:
			velocity.y = jump_velocity
		if not _attacking:
			_face(_move_direction, delta)

	move_and_slide()
	_update_locomotion_anim()


func take_damage(amount: int, knockback: Vector3 = Vector3.ZERO) -> void:
	if is_dead or _invulnerable_time_left > 0.0:
		return
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	velocity += knockback + Vector3.UP * 2.0
	_invulnerable_time_left = hurt_invulnerability
	_flash()
	if health == 0:
		_die()


func _attack_sequence() -> void:
	_attacking = true
	var step := 0
	while true:
		step += 1
		_combo_queued = false
		# Let the player aim each swing with the movement keys.
		if _move_direction != Vector3.ZERO:
			_model.rotation.y = _yaw_for(_move_direction)
		await _swing(step)
		if is_dead or not _combo_queued or step >= 3:
			break
	_attacking = false


func _swing(step: int) -> void:
	# The finisher plays a little slower so it reads as a heavier blow.
	var speed := attack_anim_speed * (0.85 if step == 3 else 1.0)
	_anim.speed_scale = 1.0
	_anim.play(_attack_anim, 0.05, speed)
	_anim.seek(0.0, true)
	await get_tree().create_timer(attack_hit_time / speed, false, true).timeout
	if is_dead:
		return
	_apply_hit(step)
	await get_tree().create_timer((attack_end_time - attack_hit_time) / speed, false, true).timeout


func _apply_hit(step: int) -> void:
	var damage := attack_damage + combo_damage_bonus * (step - 1)
	var knockback := _forward() * attack_knockback * (1.8 if step == 3 else 1.0)
	for body in _hitbox.get_overlapping_bodies():
		if body.is_in_group("enemies") and body.has_method("take_damage"):
			body.take_damage(damage, knockback)


func _die() -> void:
	is_dead = true
	_anim.pause()
	var tween := create_tween()
	tween.tween_property(_model, "rotation:x", deg_to_rad(-90.0), 0.4)
	died.emit()


func _flash() -> void:
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay = _hurt_material
	await get_tree().create_timer(0.1).timeout
	for mesh: MeshInstance3D in _meshes:
		mesh.material_overlay = null


func _update_locomotion_anim() -> void:
	if is_dead or _attacking:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.5:
		_play(_walk_anim, walk_anim_speed * clampf(horizontal_speed / move_speed, 0.5, 2.0))
	else:
		_play(_idle_anim)


func _play(anim_name: StringName, speed := 1.0) -> void:
	if anim_name == &"":
		return
	if _anim.current_animation != anim_name:
		_anim.play(anim_name, anim_blend_time)
	_anim.speed_scale = speed


func _find_anim(candidates: Array[String]) -> StringName:
	for anim_name in candidates:
		if _anim.has_animation(anim_name):
			return StringName(anim_name)
	push_warning("Player model has no animation named %s" % candidates[0])
	return &""


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() > 0.01:
		_model.rotation.y = lerp_angle(_model.rotation.y, _yaw_for(direction), turn_speed * delta)


func _forward() -> Vector3:
	return -_model.global_basis.z


static func _yaw_for(direction: Vector3) -> float:
	# Yaw that points the model's -Z (its front) along the given direction.
	return atan2(-direction.x, -direction.z)
