class_name FlameBreath
extends Node3D
## The look and sound of the Strider's flame breath: a cone of fire particles streaming along -Z,
## trailing smoke, a flickering light and a roar. Visual only; the player deals the damage.
## Built in code so it needs no textures and stays cheap on the GL Compatibility renderer
## (billboard quads, no turbulence or particle collision).

## How long the fire lives. With `reach`, sets how fast it flies.
const FIRE_LIFETIME := 0.45
const SMOKE_LIFETIME := 0.9
const LIGHT_ENERGY := 3.0

var _fire: GPUParticles3D
var _smoke: GPUParticles3D
var _light: OmniLight3D
var _sound: AudioStreamPlayer
var _light_tween: Tween
var _sound_tween: Tween
var _flicker_time := 0.0


func _ready() -> void:
	_fire = _make_fire()
	_smoke = _make_smoke()
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.15)
	_light.light_energy = 0.0
	_light.omni_range = 6.0
	_light.position = Vector3(0, 0, -2.0)
	_light.visible = false
	add_child(_light)
	_sound = AudioStreamPlayer.new()
	_sound.bus = Sfx.BUS
	add_child(_sound)
	set_process(false)


## Shapes the cone so the fire visibly reaches `reach` metres and is `width` metres across there.
func configure(reach: float, width: float) -> void:
	var spread := rad_to_deg(atan((width * 0.5) / maxf(reach, 0.1)))
	var fire := _fire.process_material as ParticleProcessMaterial
	fire.spread = spread
	fire.initial_velocity_min = reach / FIRE_LIFETIME * 0.9
	fire.initial_velocity_max = reach / FIRE_LIFETIME * 1.05
	var smoke := _smoke.process_material as ParticleProcessMaterial
	smoke.spread = spread * 1.2
	smoke.initial_velocity_min = reach / SMOKE_LIFETIME * 0.8
	smoke.initial_velocity_max = reach / SMOKE_LIFETIME * 1.0
	_light.position = Vector3(0, 0, -reach * 0.35)


func is_breathing() -> bool:
	return _fire.emitting


func start(sound: AudioStream, volume_db: float) -> void:
	_fire.emitting = true
	_smoke.emitting = true
	_light.visible = true
	_flicker_time = 0.0
	if _light_tween:
		_light_tween.kill()
	_light.light_energy = LIGHT_ENERGY
	set_process(true)
	if _sound_tween:
		_sound_tween.kill()
	if sound:
		_sound.stream = sound
		_sound.volume_db = volume_db
		_sound.pitch_scale = randf_range(0.94, 1.06)
		_sound.play()


## Stops breathing. Flames already in the air burn out on their own; the light and roar fade.
func stop() -> void:
	if not _fire.emitting:
		return
	_fire.emitting = false
	_smoke.emitting = false
	set_process(false)
	_light_tween = create_tween()
	_light_tween.tween_property(_light, "light_energy", 0.0, 0.25)
	_light_tween.tween_callback(_light.hide)
	if _sound.playing:
		_sound_tween = create_tween()
		_sound_tween.tween_property(_sound, "volume_db", -40.0, 0.2)
		_sound_tween.tween_callback(_sound.stop)


func _process(delta: float) -> void:
	_flicker_time += delta
	_light.light_energy = LIGHT_ENERGY * (0.8 + 0.2 * sin(_flicker_time * 37.0) * sin(_flicker_time * 23.0) + randf_range(-0.1, 0.1))


func _make_fire() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 0, -1)
	process.spread = 12.0
	process.gravity = Vector3(0, 1.5, 0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.08
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.scale_min = 0.6
	process.scale_max = 1.0
	# Small at the mouth, billowing out as it flies.
	process.scale_curve = _curve([Vector2(0, 0.25), Vector2(0.4, 0.9), Vector2(1, 1.6)])
	process.color_ramp = _gradient([
		[0.0, Color(1.0, 0.9, 0.55, 0.55)],
		[0.2, Color(1.0, 0.6, 0.12, 0.45)],
		[0.55, Color(0.95, 0.25, 0.03, 0.32)],
		[0.85, Color(0.5, 0.06, 0.01, 0.15)],
		[1.0, Color(0.2, 0.02, 0.0, 0.0)],
	])
	return _make_emitter("Fire", process, 110, FIRE_LIFETIME, 0.9, BaseMaterial3D.BLEND_MODE_ADD)


func _make_smoke() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 0, -1)
	process.spread = 15.0
	process.gravity = Vector3(0, 2.0, 0)
	process.damping_min = 2.0
	process.damping_max = 3.0
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.scale_curve = _curve([Vector2(0, 0.4), Vector2(1, 2.2)])
	process.color_ramp = _gradient([
		[0.0, Color(0.15, 0.1, 0.08, 0.0)],
		[0.3, Color(0.12, 0.09, 0.08, 0.55)],
		[1.0, Color(0.08, 0.07, 0.07, 0.0)],
	])
	var smoke := _make_emitter("Smoke", process, 36, SMOKE_LIFETIME, 1.2, BaseMaterial3D.BLEND_MODE_MIX)
	# Smoke is drawn behind the fire.
	smoke.draw_pass_1.surface_get_material(0).render_priority = -1
	return smoke


func _make_emitter(
	node_name: String, process: ParticleProcessMaterial, amount: int, lifetime: float, size: float,
	blend: BaseMaterial3D.BlendMode
) -> GPUParticles3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = blend
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _soft_dot()
	material.no_depth_test = false
	material.disable_receive_shadows = true
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = material
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.emitting = false
	particles.one_shot = false
	# World-space particles leave a curving trail when the Strider turns mid-breath.
	particles.local_coords = false
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-5, -3, -11), Vector3(10, 8, 13))
	add_child(particles)
	return particles


static func _soft_dot() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 64
	texture.height = 64
	return texture


static func _curve(points: Array[Vector2]) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = 3.0
	for point in points:
		curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


static func _gradient(stops: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(stops.map(func(s): return s[0]))
	gradient.colors = PackedColorArray(stops.map(func(s): return s[1]))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
