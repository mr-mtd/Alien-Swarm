class_name Player
extends CharacterBody3D
## Third-person player: camera-relative movement, jump, dodge roll and a three-hit claw combo
## that opens with a breath of fire reaching further than the claws.
## Drives the Emberline Strider model's Idle, Walk, Attack and roll animations.

signal health_changed(current: int, maximum: int)
signal died

@export_group("Movement")
@export var move_speed := 6.0
@export var acceleration := 40.0
@export var jump_velocity := 5.5
@export var turn_speed := 12.0

@export_group("Dodge")
## The Strider tumbles through a full roll in this time, and can't be hurt until it lands.
@export var dodge_duration := 0.45
## Roll distance is dodge_speed * dodge_duration (3.6 m by default).
@export var dodge_speed := 8.0
## Counted from the start of a roll.
@export var dodge_cooldown := 0.6

@export_group("Combat")
@export var max_health := 100
@export var attack_damage := 20
## Extra damage added for each step further into the combo.
@export var combo_damage_bonus := 10
@export var attack_knockback := 6.0
## Invulnerability time after taking a hit.
@export var hurt_invulnerability := 0.5

@export_group("Flame breath")
## How far in front of the Strider's mouth the flames reach and do damage, in metres.
@export var flame_range := 7.5
## Width of the flames right at the mouth, in metres. The cone widens from this...
@export var flame_start_width := 1.0
## ...to this at flame_range.
@export var flame_width := 4.0
## Damage each enemy in the flames takes per tick (a claw hit does attack_damage).
@export var flame_damage := 10
@export var flame_tick_interval := 0.15
## Longest a breath lasts. It also stops as soon as the attack (or combo) ends.
@export var flame_duration := 1.5
## Time from the start of one breath until the next attack can breathe fire again.
@export var flame_cooldown := 3.0
## Push per tick, so the flames hold enemies back.
@export var flame_knockback := 1.0
## Aims the flames slightly down so they reach the ground at the end of their range, in degrees.
@export var flame_tilt := 6.0
## Bone the flames come out of; if the model has no such bone they come from flame_fallback_mouth.
@export var flame_bone := &"jaw"
## How far past that bone, along the Strider's facing, the mouth is.
@export var flame_mouth_offset := 0.25
## Mouth position relative to the player, used when flame_bone is missing.
@export var flame_fallback_mouth := Vector3(0, 1.47, -0.6)

@export_group("Animation")
## Playback speed of the Attack animation (1.0 is the speed it was authored at).
@export var attack_anim_speed := 1.4
## Point in the Attack animation, in seconds, where the claws connect and damage is dealt.
@export var attack_hit_time := 0.5
## Point in the Attack animation, in seconds, where the swing is over and the next can start.
@export var attack_end_time := 1.0
## Walk animation playback speed when moving at full move_speed.
@export var walk_anim_speed := 1.3

@export_group("Audio")
@export var attack_sound: AudioStream = preload("res://audio/player_attack.wav")
@export var attack_volume_db := -3.0
## How long before the claws connect the swing sound starts, so its whoosh peaks on the hit.
@export var attack_sound_lead := 0.12
## Played at the enemy whenever a swing connects.
@export var enemy_hit_sound: AudioStream = preload("res://audio/enemy_hit.wav")
@export var enemy_hit_volume_db := 0.0
## Played whenever the player takes damage, from enemies and from lava.
@export var hurt_sound: AudioStream = preload("res://audio/player_hit.wav")
@export var hurt_volume_db := -2.0
## Roar of the flame breath, faded out early when the breath is cut short.
@export var flame_sound: AudioStream = preload("res://audio/player_flame.wav")
@export var flame_volume_db := -4.0
## Hit sound volume for flame ticks, quieter than claw hits since they come in quick succession.
@export var flame_hit_volume_db := -8.0

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
var _flame_cooldown_left := 0.0
var _flame_time_left := 0.0
var _flame_tick_left := 0.0
var _flame_ticks := 0
var _mouth: Node3D

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _model: Node3D = $Model
@onready var _hitbox: Area3D = $Model/Hitbox
@onready var _animator: StriderAnimator = $Animator
@onready var _flame: FlameBreath = $FlameBreath
@onready var _meshes: Array[Node] = $Model/Strider.find_children("*", "MeshInstance3D")


func _ready() -> void:
	health = max_health
	_hurt_material.albedo_color = Color(1, 0.2, 0.2)
	_hurt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_animator.play_idle()
	_mouth = _find_mouth()
	_flame.configure(flame_range, flame_width)
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
	_flame_cooldown_left = maxf(_flame_cooldown_left - delta, 0.0)

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
		# Roll where the player is steering; with no input, back away from whatever is in front.
		_dodge_direction = _move_direction if _move_direction != Vector3.ZERO else -_forward()
		_dodge_time_left = dodge_duration
		_dodge_cooldown_left = dodge_cooldown
		_invulnerable_time_left = maxf(_invulnerable_time_left, dodge_duration)
		_animator.play_roll(_roll_direction_for(_dodge_direction), dodge_duration)

	if _dodge_time_left > 0.0:
		_dodge_time_left -= delta
		velocity.x = _dodge_direction.x * dodge_speed
		velocity.z = _dodge_direction.z * dodge_speed
		# The model keeps its facing for the whole roll: back and side rolls only read that way
		# if the Strider doesn't turn into them.
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
	_update_flame(delta)


func take_damage(amount: int, knockback: Vector3 = Vector3.ZERO) -> void:
	if is_dead or _invulnerable_time_left > 0.0:
		return
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	velocity += knockback + Vector3.UP * 2.0
	_invulnerable_time_left = hurt_invulnerability
	Sfx.play(self, hurt_sound, hurt_volume_db)
	_flash()
	if health == 0:
		_die()


## Restores health, never past max_health. Returns how much was actually restored.
func heal(amount: int) -> int:
	if is_dead:
		return 0
	var before := health
	health = mini(health + amount, max_health)
	health_changed.emit(health, max_health)
	return health - before


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
	_stop_flame()


func _swing(step: int) -> void:
	# The finisher plays a little slower so it reads as a heavier blow.
	var speed := attack_anim_speed * (0.85 if step == 3 else 1.0)
	_animator.play_attack(speed)
	var hit_delay := attack_hit_time / speed
	var sound_lead := minf(attack_sound_lead, hit_delay)
	await get_tree().create_timer(hit_delay - sound_lead, false, true).timeout
	if is_dead:
		return
	Sfx.play(self, attack_sound, attack_volume_db, 0.85 if step == 3 else 1.0)
	if _flame_cooldown_left <= 0.0:
		_start_flame()
	await get_tree().create_timer(sound_lead, false, true).timeout
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
			var pitch := (body as Enemy).sound_pitch if body is Enemy else 1.0
			Sfx.play_at(self, enemy_hit_sound, body.global_position + Vector3.UP, enemy_hit_volume_db, pitch)


func is_breathing_fire() -> bool:
	return _flame_time_left > 0.0


func _start_flame() -> void:
	_flame_time_left = flame_duration
	_flame_cooldown_left = flame_cooldown
	# The first burn lands once the flames are out of the mouth.
	_flame_tick_left = 0.1
	_flame_ticks = 0
	_place_flame()
	_flame.start(flame_sound, flame_volume_db)


func _stop_flame() -> void:
	_flame_time_left = 0.0
	_flame.stop()


func _update_flame(delta: float) -> void:
	if _flame_time_left <= 0.0:
		return
	_place_flame()
	_flame_tick_left -= delta
	if _flame_tick_left <= 0.0:
		_flame_tick_left += flame_tick_interval
		_flame_tick()
	_flame_time_left -= delta
	if _flame_time_left <= 0.0:
		_stop_flame()


## Burns every enemy inside the cone in front of the mouth.
func _flame_tick() -> void:
	_flame_ticks += 1
	var origin := _flame.global_position
	var forward := _forward()
	var right := forward.cross(Vector3.UP)
	var knockback := forward * flame_knockback
	for body in get_tree().get_nodes_in_group("enemies"):
		if not body is Node3D or not body.has_method("take_damage"):
			continue
		if body is Enemy and (body as Enemy).health <= 0:
			continue
		var offset: Vector3 = (body as Node3D).global_position - origin
		# Enemies stand on the ground below the mouth; only ignore ones far above or below.
		if offset.y > 2.0 or offset.y < -3.5:
			continue
		var along := offset.dot(forward)
		if along < -0.5 or along > flame_range:
			continue
		var half_width := lerpf(flame_start_width, flame_width, clampf(along / flame_range, 0.0, 1.0)) * 0.5
		if absf(offset.dot(right)) > half_width:
			continue
		body.take_damage(flame_damage, knockback)
		# Every tick's hit sound at once would be a buzz: one on the first tick, then every third.
		if _flame_ticks % 3 == 1:
			var pitch := (body as Enemy).sound_pitch if body is Enemy else 1.0
			Sfx.play_at(self, enemy_hit_sound, body.global_position + Vector3.UP, flame_hit_volume_db, pitch)


## Keeps the flames at the mouth, pointing the way the Strider faces (not the way its head bobs).
func _place_flame() -> void:
	var mouth := _mouth.global_position if _mouth else to_global(flame_fallback_mouth)
	var facing := _model.global_basis.orthonormalized()
	_flame.global_basis = facing * Basis(Vector3.RIGHT, deg_to_rad(-flame_tilt))
	_flame.global_position = mouth + _forward() * (flame_mouth_offset if _mouth else 0.0)


## A node that follows flame_bone as the animations move it, or null if the model has no such bone.
func _find_mouth() -> Node3D:
	var skeletons := _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return null
	var skeleton := skeletons[0] as Skeleton3D
	if skeleton.find_bone(flame_bone) < 0:
		push_warning("Player: no '%s' bone on the Strider; flames come from flame_fallback_mouth." % flame_bone)
		return null
	var attachment := BoneAttachment3D.new()
	attachment.name = "Mouth"
	attachment.bone_name = flame_bone
	skeleton.add_child(attachment)
	return attachment


func _die() -> void:
	is_dead = true
	_stop_flame()
	_animator.freeze()
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
	if is_dead or _attacking or _dodge_time_left > 0.0:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.5:
		_animator.play_walk(walk_anim_speed * clampf(horizontal_speed / move_speed, 0.5, 2.0))
	else:
		_animator.play_idle()


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() > 0.01:
		_model.rotation.y = lerp_angle(_model.rotation.y, _yaw_for(direction), turn_speed * delta)


func _forward() -> Vector3:
	return -_model.global_basis.z


## Which roll animation fits a dodge in world `direction`, given the way the model faces right now.
func _roll_direction_for(direction: Vector3) -> StringName:
	# The model's front is -Z and its right is +X.
	var local := _model.global_basis.inverse() * direction
	if absf(local.z) >= absf(local.x):
		return &"forward" if local.z < 0.0 else &"back"
	return &"right" if local.x > 0.0 else &"left"


static func _yaw_for(direction: Vector3) -> float:
	# Yaw that points the model's -Z (its front) along the given direction.
	return atan2(-direction.x, -direction.z)
