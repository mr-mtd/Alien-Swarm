class_name Enemy
extends CharacterBody3D
## Skitterer: an insectoid alien that walks toward the player, slashes when close and leaps at the
## player from mid range with a heavier jump attack. Idles when there is nothing to chase.

signal died(enemy: Enemy)

enum State { IDLE, CHASE, ATTACK, JUMP_ATTACK, STAGGER, DEAD }

@export var max_health := 60
@export var move_speed := 3.5
@export var turn_speed := 10.0
@export var detection_range := 30.0
@export var stagger_time := 0.35

@export_group("Attack")
## Distance (between centres) at which the skitterer stops walking and slashes.
@export var attack_range := 2.0
@export var attack_damage := 10
@export var attack_knockback := 4.0
@export var attack_cooldown := 1.2
## Point in the Attack animation, in seconds, where the blades connect.
@export var attack_hit_time := 0.4
@export var attack_anim_speed := 1.0

@export_group("Jump attack")
## The skitterer leaps when the player is between these two distances.
@export var jump_min_range := 4.0
@export var jump_max_range := 9.0
@export var jump_attack_damage := 20
@export var jump_knockback := 8.0
@export var jump_cooldown := 5.0
## The landing hits everything within this distance.
@export var jump_hit_radius := 2.2
## Points in the JumpAttack animation, in seconds, where it leaves the ground and lands.
@export var jump_takeoff_time := 0.27
@export var jump_land_time := 0.8
@export var jump_max_speed := 14.0

@export_group("Animation")
## Walk animation playback speed at full move_speed.
@export var walk_anim_speed := 1.4

@export_group("Loot")
## Chance, from 0 to 1, that it drops a health pack when it dies.
@export_range(0.0, 1.0) var health_pack_drop_chance := 0.25

var health := 0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _target: Player
var _state := State.IDLE
var _state_time := 0.0
var _attack_cooldown_left := 0.0
var _jump_cooldown_left := 0.0
var _hit_done := false
var _leap_velocity := Vector3.ZERO
var _hurt_material := StandardMaterial3D.new()

@onready var _model: Node3D = $Model
@onready var _animator: ModelAnimator = $Animator


func _ready() -> void:
	health = max_health
	_target = get_tree().get_first_node_in_group("player") as Player
	_hurt_material.albedo_color = Color(1, 1, 1, 0.7)
	_hurt_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hurt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Stagger the first jump so a fresh wave doesn't all leap at once.
	_jump_cooldown_left = randf_range(1.0, jump_cooldown)
	_animator.play_loop(&"idle")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_state_time += delta
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	_jump_cooldown_left = maxf(_jump_cooldown_left - delta, 0.0)

	match _state:
		State.DEAD, State.STAGGER:
			# Slide out the knockback.
			velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
			if _state == State.STAGGER and _state_time >= stagger_time:
				_set_state(State.IDLE)
		State.ATTACK:
			_face_target(delta)
			velocity.x = 0.0
			velocity.z = 0.0
			if not _hit_done and _state_time >= attack_hit_time / attack_anim_speed:
				_hit_done = true
				_hit_target(attack_range + 0.3, attack_damage, attack_knockback)
			if _state_time >= _animator.clip_length(&"attack") / attack_anim_speed:
				_attack_cooldown_left = attack_cooldown
				_set_state(State.IDLE)
		State.JUMP_ATTACK:
			_update_jump(delta)
		State.IDLE, State.CHASE:
			_update_chase(delta)
	move_and_slide()


func take_damage(amount: int, knockback: Vector3 = Vector3.ZERO) -> void:
	if _state == State.DEAD:
		return
	health -= amount
	_flash()
	if health <= 0:
		velocity = knockback * 0.5
		_die()
		return
	# Hits interrupt a slash before it lands and a leap before it leaves the ground;
	# once airborne the skitterer is committed.
	var airborne := _state == State.JUMP_ATTACK and _state_time >= jump_takeoff_time
	var attack_landed := _state == State.ATTACK and _hit_done
	if airborne or attack_landed:
		return
	velocity = knockback + Vector3.UP * 2.0
	_set_state(State.STAGGER)
	_animator.play_loop(&"idle")


func _update_chase(delta: float) -> void:
	if not _can_see_target():
		velocity.x = 0.0
		velocity.z = 0.0
		_set_state(State.IDLE)
		_animator.play_loop(&"idle")
		return
	var offset := _flat_offset_to_target()
	var distance := offset.length()
	_face_target(delta)
	if distance <= attack_range and _attack_cooldown_left <= 0.0:
		_start_attack()
		return
	if distance >= jump_min_range and distance <= jump_max_range and _jump_cooldown_left <= 0.0 and is_on_floor():
		_start_jump()
		return
	if distance > attack_range * 0.8:
		var direction := offset / distance
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		_set_state(State.CHASE)
		_animator.play_loop(&"walk", walk_anim_speed)
	else:
		# In range and waiting on the cooldown.
		velocity.x = 0.0
		velocity.z = 0.0
		_set_state(State.IDLE)
		_animator.play_loop(&"idle")


func _start_attack() -> void:
	_set_state(State.ATTACK)
	_hit_done = false
	_animator.play_once(&"attack", attack_anim_speed)


func _start_jump() -> void:
	_set_state(State.JUMP_ATTACK)
	_hit_done = false
	_leap_velocity = Vector3.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	_animator.play_once(&"jump_attack")


func _update_jump(delta: float) -> void:
	var takeoff := jump_takeoff_time
	var land := jump_land_time
	if _state_time < takeoff:
		# Crouch and aim.
		_face_target(delta)
		velocity.x = 0.0
		velocity.z = 0.0
	elif _leap_velocity == Vector3.ZERO and not _hit_done:
		# Take off toward where the player is now, aiming to land just short of them.
		var offset := _flat_offset_to_target() if _can_see_target() else Vector3.ZERO
		var air_time := land - takeoff
		var distance := maxf(offset.length() - attack_range * 0.6, 0.0)
		var speed := minf(distance / air_time, jump_max_speed)
		_leap_velocity = offset.normalized() * speed if offset.length() > 0.01 else -_model.global_basis.z * 0.1
		velocity = Vector3(_leap_velocity.x, _gravity * air_time * 0.5, _leap_velocity.z)
	elif _state_time < land:
		velocity.x = _leap_velocity.x
		velocity.z = _leap_velocity.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if not _hit_done:
			_hit_done = true
			_leap_velocity = Vector3.ZERO
			_hit_target(jump_hit_radius, jump_attack_damage, jump_knockback)
		if _state_time >= _animator.clip_length(&"jump_attack"):
			_jump_cooldown_left = jump_cooldown
			_attack_cooldown_left = attack_cooldown * 0.5
			_set_state(State.IDLE)


func _hit_target(reach: float, damage: int, knockback: float) -> void:
	if not _can_see_target():
		return
	var offset := _flat_offset_to_target()
	if offset.length() <= reach:
		_target.take_damage(damage, offset.normalized() * knockback)


func _face_target(delta: float) -> void:
	if not _can_see_target():
		return
	var offset := _flat_offset_to_target()
	if offset.length() > 0.01:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-offset.x, -offset.z), turn_speed * delta)


func _flat_offset_to_target() -> Vector3:
	var offset := _target.global_position - global_position
	offset.y = 0.0
	return offset


func _can_see_target() -> bool:
	return (
		_state != State.DEAD
		and is_instance_valid(_target)
		and not _target.is_dead
		and global_position.distance_to(_target.global_position) <= detection_range
	)


func _set_state(state: State) -> void:
	if state != _state:
		_state = state
		_state_time = 0.0


func _die() -> void:
	_set_state(State.DEAD)
	collision_layer = 0
	died.emit(self)
	if _animator.has_clip(&"death"):
		_animator.play_once(&"death")
	else:
		# No death animation: freeze and topple over.
		_animator.freeze()
		create_tween().tween_property(_model, "rotation:x", deg_to_rad(-90.0), 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(_animator.clip_length(&"death") + 1.0).timeout
	var tween := create_tween()
	tween.tween_property(_model, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(queue_free)


func _flash() -> void:
	var meshes := _model.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		mesh.material_overlay = _hurt_material
	await get_tree().create_timer(0.08).timeout
	for mesh: MeshInstance3D in meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
