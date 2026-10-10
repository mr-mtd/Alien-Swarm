@tool
class_name AlienTerrain
extends Node3D
## Builds the open alien world from code: rolling walkable ground with glowing veins, swaying grass,
## fiddlehead ferns, alien trees, shrubs, rocks, crystals, drifting spores and coloured point lights.
## The ground, tree trunks and boulders have collision; plants are decoration you walk through.
## The playable area is a circle of play_radius around the origin, ringed by rising mountains and
## an invisible wall. Change world_seed for a different layout.

const GROUND_SHADER := preload("res://shaders/alien_ground.gdshader")
const GRASS_SHADER := preload("res://shaders/alien_grass.gdshader")
const FLORA_SHADER := preload("res://shaders/alien_flora.gdshader")

@export var world_seed := 7: set = _set_world_seed
## Radius of the flat clearing the player starts in.
@export var clearing_radius := 10.0
## How far from the origin the player can roam before the mountains and edge wall stop them.
@export var play_radius := 90.0
## Height of the rolling hills across the playable area. Keep it low enough to walk up.
@export var hill_height := 7.0
@export var world_size := 300.0
@export var grass_clumps := 3500
@export var grass_radius := 70.0
@export var fern_count := 350
@export var tree_count := 90
@export var shrub_count := 260
@export var spore_count := 500
## Point lights cast from glowing trees, crystals and shrubs across the map.
@export var point_lights := true
@export var light_energy := 2.2
## Lights farther than this from the camera fade out to keep the frame rate up.
@export var light_fade_distance := 45.0
## Tick to rebuild in the editor after changing settings.
@export var rebuild := false: set = _set_rebuild

var _rng := RandomNumberGenerator.new()
var _hills := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _patches := FastNoiseLite.new()
var _generated: Node3D
var _grass_material: ShaderMaterial
var _player: Node3D
var _spores: CPUParticles3D
# Trunks and boulders the player collides with, as (x, z, radius), so spawns can avoid them.
var _obstacles: Array[Vector3] = []

var _flora_material: ShaderMaterial
var _rock_material: ShaderMaterial
# Set by each _make_* builder: the glow colour of the mesh it just built and how high the glow sits.
var _last_glow := Color.WHITE
var _last_glow_height := 1.0


func _ready() -> void:
	_build()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _grass_material == null:
		return
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player:
		_grass_material.set_shader_parameter("player_position", _player.global_position)
		# Spores drift around wherever the player is; particles already emitted stay put.
		_spores.global_position = _player.global_position + Vector3.UP * 2.5


func _set_world_seed(value: int) -> void:
	world_seed = value
	if is_inside_tree():
		_build()


func _set_rebuild(_value: bool) -> void:
	if is_inside_tree():
		_build()


## Ground height at a world position. Zero in the starting clearing, rolling hills across the
## playable area and mountains rising around its edge.
func height_at(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var hill_blend := smoothstep(clearing_radius, clearing_radius + 22.0, r)
	var hills := (_hills.get_noise_2d(x, z) * 0.5 + 0.5) * hill_height + 0.5
	var ridge := 1.0 - absf(_ridges.get_noise_2d(x, z))
	var mountains := smoothstep(play_radius - 15.0, play_radius + 50.0, r) * (ridge * ridge * 45.0 + 8.0)
	return hills * hill_blend + mountains


## True when nothing solid (a trunk or boulder) stands within margin of this spot.
func is_open_ground(x: float, z: float, margin := 1.0) -> bool:
	for o in _obstacles:
		if Vector2(o.x - x, o.y - z).length() < o.z + margin:
			return false
	return true


func _build() -> void:
	if _generated:
		_generated.free()
	_generated = Node3D.new()
	_generated.name = "Generated"
	add_child(_generated)

	_rng.seed = world_seed
	_hills.seed = world_seed
	_hills.frequency = 0.018
	_hills.fractal_octaves = 3
	_ridges.seed = world_seed + 1
	_ridges.frequency = 0.011
	_ridges.fractal_octaves = 3
	_patches.seed = world_seed + 2
	_patches.frequency = 0.035

	_flora_material = ShaderMaterial.new()
	_flora_material.shader = FLORA_SHADER
	_rock_material = ShaderMaterial.new()
	_rock_material.shader = FLORA_SHADER
	_rock_material.set_shader_parameter("sway", 0.0)
	_rock_material.set_shader_parameter("roughness_value", 0.9)
	_rock_material.set_shader_parameter("glow_strength", 1.8)
	_rock_material.set_shader_parameter("rim_strength", 0.5)

	_obstacles.clear()
	_build_ground()
	_build_edge_wall()
	_build_grass()
	_build_rocks_and_crystals()
	_build_trees()
	_build_shrubs()
	_build_ferns()
	_build_spores()


# --- Ground -------------------------------------------------------------------------------------

func _build_ground() -> void:
	# Built in tiles so each one only picks up the point lights near it (the Compatibility
	# renderer limits how many lights touch a single mesh) and off-screen tiles are culled.
	var step := 2.0
	var tile := 20.0
	var tiles := ceili(world_size / tile)
	var per_tile := int(tile / step)
	var start := -tiles * tile * 0.5
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	for tz in tiles:
		for tx in tiles:
			var verts := PackedVector3Array()
			var normals := PackedVector3Array()
			var indices := PackedInt32Array()
			var count := per_tile + 1
			for iz in count:
				for ix in count:
					var x := start + tx * tile + ix * step
					var z := start + tz * tile + iz * step
					verts.append(Vector3(x, height_at(x, z), z))
					normals.append(_normal_at(x, z))
			for iz in per_tile:
				for ix in per_tile:
					var i := iz * count + ix
					indices.append_array([i, i + 1, i + count, i + 1, i + count + 1, i + count])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, material)
			var ground := MeshInstance3D.new()
			ground.name = "Ground_%d_%d" % [tx, tz]
			ground.mesh = mesh
			_generated.add_child(ground)
			# Tiles the player can reach get collision built from the very same triangles.
			var center := Vector2(start + (tx + 0.5) * tile, start + (tz + 0.5) * tile)
			if center.length() - tile * 0.71 < play_radius + 4.0:
				var body := StaticBody3D.new()
				var shape := CollisionShape3D.new()
				shape.shape = mesh.create_trimesh_shape()
				body.add_child(shape)
				ground.add_child(body)


## An invisible ring of walls in the foothills, so nobody walks off into the mountains.
func _build_edge_wall() -> void:
	var segments := 64
	var radius := play_radius + 2.0
	var box := BoxShape3D.new()
	box.size = Vector3(radius * TAU / segments * 1.15, 120.0, 2.0)
	var wall := StaticBody3D.new()
	wall.name = "EdgeWall"
	for i in segments:
		var a := i * TAU / segments
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.transform = Transform3D(Basis(Vector3.UP, -a - PI * 0.5), Vector3(cos(a), 0.0, sin(a)) * (radius + 1.0) + Vector3.UP * 40.0)
		wall.add_child(shape)
	_generated.add_child(wall)


## A static cylinder for a trunk or boulder, recorded so enemies don't spawn inside it.
func _add_obstacle(pos: Vector3, radius: float, height: float) -> void:
	if Vector2(pos.x, pos.z).length() > play_radius + radius + 3.0:
		return
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	shape.shape = cylinder
	body.add_child(shape)
	body.position = pos + Vector3.UP * height * 0.5
	_generated.add_child(body)
	_obstacles.append(Vector3(pos.x, pos.z, radius))


func _normal_at(x: float, z: float) -> Vector3:
	var e := 0.5
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


# --- Grass --------------------------------------------------------------------------------------

func _build_grass() -> void:
	_grass_material = ShaderMaterial.new()
	_grass_material.shader = GRASS_SHADER
	var blade_mesh := _make_grass_clump_mesh()
	blade_mesh.surface_set_material(0, _grass_material)

	# Split the field into chunks so off-screen and distant grass is culled.
	var chunk_size := 20.0
	var chunks := {}
	var tips := [
		Color(0.2, 0.75, 1.0), Color(0.15, 0.45, 1.0), Color(1.0, 0.55, 0.15), Color(1.0, 0.75, 0.3),
	]
	var placed := 0
	var attempts := 0
	while placed < grass_clumps and attempts < grass_clumps * 4:
		attempts += 1
		var x := _rng.randf_range(-grass_radius, grass_radius)
		var z := _rng.randf_range(-grass_radius, grass_radius)
		var r := Vector2(x, z).length()
		if r > grass_radius or _rng.randf() < r / grass_radius * 0.5:
			continue
		var patch := _patches.get_noise_2d(x, z)
		if patch < -0.45:
			continue  # bare patches break up the carpet
		if _normal_at(x, z).y < 0.8:
			continue
		var tall := _rng.randf_range(0.25, 0.4) if r < clearing_radius else _rng.randf_range(0.3, 0.8)
		var wide := _rng.randf_range(0.8, 1.3)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(wide, tall, wide))
		var xform := Transform3D(basis, Vector3(x, height_at(x, z) - 0.02, z))
		var tip_index := clampi(int((patch * 0.5 + 0.5) * tips.size() + _rng.randf_range(-0.6, 0.6)), 0, tips.size() - 1)
		var tip: Color = tips[tip_index].lerp(Color(0.3, 0.8, 1.0), _rng.randf() * 0.2)
		tip.a = _rng.randf()
		var key := Vector2i(floori(x / chunk_size), floori(z / chunk_size))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append([xform, tip])
		placed += 1

	for key: Vector2i in chunks:
		var items: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = blade_mesh
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i][0])
			mm.set_instance_custom_data(i, items[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Grass_%d_%d" % [key.x, key.y]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 85.0
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_generated.add_child(mmi)


## A clump of six curved, tapering blades, one unit tall. UV.y runs from root (0) to tip (1).
func _make_grass_clump_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var segments := 4
	var blades := 6
	for blade in blades:
		var angle := blade * TAU / blades + _rng.randf_range(-0.4, 0.4)
		var offset := Vector3(cos(angle * 1.7), 0.0, sin(angle * 1.7)) * _rng.randf_range(0.02, 0.12)
		var lean_dir := Vector3(cos(angle), 0.0, sin(angle))
		var side := lean_dir.cross(Vector3.UP).normalized()
		var lean := _rng.randf_range(0.15, 0.4)
		var width := _rng.randf_range(0.025, 0.045)
		var start := verts.size()
		for s in segments + 1:
			var t := float(s) / segments
			var center := offset + lean_dir * lean * t * t + Vector3.UP * t
			var w := width * (1.0 - t)
			verts.append(center - side * w)
			verts.append(center + side * w)
			for k in 2:
				normals.append(Vector3.UP)
				uvs.append(Vector2(k, t))
		for s in segments:
			var i := start + s * 2
			indices.append_array([i, i + 1, i + 2, i + 1, i + 3, i + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Trees --------------------------------------------------------------------------------------

func _build_trees() -> void:
	# Each variant is [mesh, glow colour, glow height].
	var variants: Array = []
	for i in 3:
		for builder in [_make_lantern_tree, _make_parasol_tree, _make_coral_tree]:
			var mesh: ArrayMesh = builder.call()
			variants.append([mesh, _last_glow, _last_glow_height])

	var spots: Array[Vector2] = []
	var attempts := 0
	while spots.size() < tree_count and attempts < tree_count * 30:
		attempts += 1
		var angle := _rng.randf() * TAU
		# Trees grow all over the map and into the foothills, but leave the clearing open.
		var r := clearing_radius + 5.0 + pow(_rng.randf(), 0.9) * (play_radius + 25.0 - clearing_radius)
		var p := Vector2(cos(angle), sin(angle)) * r
		var clear := true
		for other in spots:
			if other.distance_to(p) < 6.0:
				clear = false
				break
		if clear:
			spots.append(p)

	for p in spots:
		var variant: Array = variants[_rng.randi() % variants.size()]
		var tree := MeshInstance3D.new()
		tree.mesh = variant[0]
		tree.material_override = _flora_material
		var s := _rng.randf_range(0.8, 1.35)
		var base := Vector3(p.x, height_at(p.x, p.y) - 0.3, p.y)
		tree.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), base)
		tree.visibility_range_end = 160.0
		_generated.add_child(tree)
		_add_obstacle(base, 0.45 * s, 4.0)
		if p.length() < play_radius:
			_add_light(base + Vector3.UP * variant[2] * s, variant[1], 9.0 * s, light_energy)


## Curving trunk with glowing spiral veins and drooping branches that end in lantern bulbs.
func _make_lantern_tree() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var h := _rng.randf_range(6.0, 10.0)
	var bark := Color(0.12, 0.13, 0.2)
	var vein: Color = _pick([Color(0.3, 0.85, 1.0), Color(1.0, 0.5, 0.12)])
	var bulb: Color = _pick([Color(1.0, 0.72, 0.28), Color(1.0, 0.5, 0.12), Color(0.3, 0.85, 1.0)])
	var phase := _rng.randf() * TAU
	var bend := _rng.randf_range(0.6, 1.4)
	var trunk: Array[Vector3] = []
	var radii: Array[float] = []
	for i in 12:
		var t := i / 11.0
		trunk.append(Vector3(sin(t * 2.2 + phase) * bend * t, h * t, cos(t * 1.7 + phase) * bend * 0.6 * t))
		radii.append(lerpf(0.42, 0.12, t) * (1.0 + 1.4 * pow(1.0 - t, 5.0)))
	mb.tube(trunk, radii, 10, bark, bark.lightened(0.15), vein, 3.0)

	var branches := _rng.randi_range(4, 6)
	for b in branches:
		var t0 := _rng.randf_range(0.5, 0.92)
		var start := _sample_path(trunk, t0)
		var dir := Vector3.FORWARD.rotated(Vector3.UP, b * TAU / branches + _rng.randf_range(-0.4, 0.4))
		var length := _rng.randf_range(1.8, 3.4)
		var path: Array[Vector3] = []
		var path_radii: Array[float] = []
		for i in 8:
			var s := i / 7.0
			path.append(start + dir * length * s + Vector3.UP * (sin(s * PI * 0.8) * 1.3 - s * s * 1.1))
			path_radii.append(lerpf(0.12, 0.04, s))
		mb.tube(path, path_radii, 6, bark, bark.lightened(0.2), vein, 2.0)
		var tip := path[path.size() - 1]
		var size := _rng.randf_range(0.3, 0.55)
		mb.ellipsoid(tip + Vector3.DOWN * size * 0.8, Vector3(size, size * 1.25, size), bulb, bulb, 1.0)
		# A few smaller bulbs dangle from each branch on thin threads.
		for k in _rng.randi_range(1, 3):
			var hang := _sample_path(path, _rng.randf_range(0.3, 0.85))
			var drop := _rng.randf_range(0.4, 1.2)
			mb.tube([hang, hang + Vector3.DOWN * drop] as Array[Vector3], [0.015, 0.015] as Array[float], 4, bark, bark, vein, 0.0)
			mb.ellipsoid(hang + Vector3.DOWN * (drop + 0.1), Vector3.ONE * _rng.randf_range(0.1, 0.18), bulb, bulb, 1.0)
	var top := trunk[trunk.size() - 1]
	mb.ellipsoid(top + Vector3.UP * 0.3, Vector3(0.6, 0.8, 0.6), bulb, bulb, 1.0)
	_last_glow = bulb
	_last_glow_height = h * 0.85
	return mb.commit()


## Slender twisting stalk under a wide mushroom cap with glowing gills and hanging tendrils.
func _make_parasol_tree() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var h := _rng.randf_range(7.0, 12.0)
	var stalk := Color(0.6, 0.52, 0.45)
	var cap_top: Color = _pick([Color(0.08, 0.16, 0.35), Color(0.4, 0.15, 0.05), Color(0.05, 0.22, 0.38)])
	var gills: Color = _pick([Color(1.0, 0.5, 0.12), Color(0.3, 0.85, 1.0), Color(1.0, 0.72, 0.28)])
	var phase := _rng.randf() * TAU
	var trunk: Array[Vector3] = []
	var radii: Array[float] = []
	for i in 12:
		var t := i / 11.0
		trunk.append(Vector3(sin(t * 3.0 + phase) * 0.5 * t, h * t, cos(t * 2.5 + phase) * 0.4 * t))
		radii.append(lerpf(0.38, 0.22, t) * (1.0 + 1.0 * pow(1.0 - t, 6.0)))
	mb.tube(trunk, radii, 10, stalk.darkened(0.45), stalk, gills, 0.0)

	var top := trunk[trunk.size() - 1]
	var cap_r := _rng.randf_range(3.0, 4.6)
	mb.cap(top, cap_r, cap_r * 0.32, 24, 8, cap_top, gills)
	for i in _rng.randi_range(10, 16):
		var a := _rng.randf() * TAU
		var root := top + Vector3(cos(a), 0.0, sin(a)) * cap_r * _rng.randf_range(0.45, 0.88) + Vector3.DOWN * 0.15
		var length := _rng.randf_range(1.0, 3.2)
		var path: Array[Vector3] = []
		var path_radii: Array[float] = []
		for k in 5:
			var s := k / 4.0
			path.append(root + Vector3(sin(s * 3.0 + a) * 0.15, -length * s, cos(s * 2.0 + a) * 0.15))
			path_radii.append(lerpf(0.05, 0.015, s))
		mb.tube(path, path_radii, 4, gills.darkened(0.5), gills, gills, 0.0, 0.5)
		mb.ellipsoid(path[path.size() - 1] + Vector3.DOWN * 0.05, Vector3.ONE * 0.08, gills, gills, 1.0)
	_last_glow = gills
	_last_glow_height = h - 1.0
	return mb.commit()


## Branching coral fronds whose tips glow like embers.
func _make_coral_tree() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var palette: Array = _pick([
		[Color(0.3, 0.08, 0.03), Color(1.0, 0.5, 0.15)],
		[Color(0.04, 0.1, 0.28), Color(0.3, 0.8, 1.0)],
		[Color(0.25, 0.12, 0.04), Color(1.0, 0.78, 0.3)],
	])
	_coral_branch(mb, Vector3.ZERO, Vector3.UP, _rng.randf_range(2.6, 3.4), 0.4, 3, palette[0], palette[1])
	_last_glow = palette[1]
	_last_glow_height = 5.0
	return mb.commit()


func _coral_branch(mb: MeshBuilder, start: Vector3, dir: Vector3, length: float, radius: float, depth: int, base: Color, tip: Color) -> void:
	var curl := Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)) * 0.25
	var path: Array[Vector3] = []
	var radii: Array[float] = []
	for i in 6:
		var s := i / 5.0
		path.append(start + (dir + curl * s) * length * s)
		radii.append(lerpf(radius, radius * 0.6, s))
	var level := 1.0 - float(depth) / 3.0
	var c0 := base.lerp(tip, level * 0.5)
	var c1 := base.lerp(tip, level * 0.5 + 0.25)
	mb.tube(path, radii, 7, c0, c1, tip, 0.0)
	var end := path[path.size() - 1]
	if depth == 0:
		mb.ellipsoid(end, Vector3.ONE * radius * 2.4, tip, tip, 1.0)
		return
	var children := _rng.randi_range(2, 3)
	var axis := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized()
	for c in children:
		var spin := c * TAU / children + _rng.randf_range(-0.5, 0.5)
		var tilt := _rng.randf_range(0.35, 0.75)
		var child_dir := dir.rotated(axis.rotated(dir, spin), tilt).normalized()
		child_dir = (child_dir + Vector3.UP * 0.25).normalized()
		_coral_branch(mb, end, child_dir, length * _rng.randf_range(0.65, 0.85), radius * 0.62, depth - 1, base, tip)


# --- Shrubs -------------------------------------------------------------------------------------

func _build_shrubs() -> void:
	var variants: Array[ArrayMesh] = []
	var glows: Array[Color] = []
	for i in 2:
		for builder in [_make_bulb_shrub, _make_frond_shrub, _make_spike_shrub]:
			variants.append(builder.call())
			glows.append(_last_glow)
	var placements: Array = []
	for v in variants.size():
		placements.append([])

	# Shrubs grow in patches across the map. They are low and have no collision.
	var placed := 0
	while placed < shrub_count:
		var angle := _rng.randf() * TAU
		var center := Vector2(cos(angle), sin(angle)) * sqrt(_rng.randf()) * (play_radius + 10.0)
		if center.length() < 5.0:
			continue  # keep the spawn point clear
		var patch_variant := _rng.randi() % variants.size()
		if _rng.randf() < 0.2:
			_add_light(Vector3(center.x, height_at(center.x, center.y) + 0.8, center.y), glows[patch_variant], 5.0, light_energy * 0.8)
		for k in _rng.randi_range(3, 7):
			var p := center + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3))
			var s := _rng.randf_range(0.6, 1.0) if p.length() < clearing_radius else _rng.randf_range(0.8, 1.5)
			var xform := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, height_at(p.x, p.y) - 0.05, p.y))
			placements[patch_variant if _rng.randf() < 0.7 else _rng.randi() % variants.size()].append(xform)
			placed += 1

	for v in variants.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variants[v]
		mm.instance_count = placements[v].size()
		for i in placements[v].size():
			mm.set_instance_transform(i, placements[v][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Shrubs_%d" % v
		mmi.multimesh = mm
		mmi.material_override = _flora_material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_generated.add_child(mmi)


## Thin stalks topped with glowing bulbs.
func _make_bulb_shrub() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var stem := Color(0.08, 0.12, 0.22)
	var bulb: Color = _pick([Color(1.0, 0.72, 0.28), Color(0.3, 0.85, 1.0), Color(1.0, 0.5, 0.12)])
	for i in _rng.randi_range(5, 9):
		var a := _rng.randf() * TAU
		var h := _rng.randf_range(0.4, 1.2)
		var out := Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(0.1, 0.45)
		var path: Array[Vector3] = []
		for k in 5:
			var s := k / 4.0
			path.append(out * s * 0.3 + out * s * s + Vector3.UP * h * s)
		mb.tube(path, [0.035, 0.03, 0.025, 0.02, 0.018] as Array[float], 4, stem, stem.lightened(0.2), bulb, 0.0)
		var size := _rng.randf_range(0.07, 0.14)
		mb.ellipsoid(path[path.size() - 1] + Vector3.UP * size * 0.6, Vector3(size, size * 1.3, size), bulb, bulb, 1.0)
	_last_glow = bulb
	return mb.commit()


## A fan of arching leaves with a glowing midrib.
func _make_frond_shrub() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var leaf: Color = _pick([Color(0.05, 0.12, 0.28), Color(0.25, 0.1, 0.04), Color(0.04, 0.1, 0.22)])
	var rib: Color = _pick([Color(0.3, 0.85, 1.0), Color(1.0, 0.5, 0.12), Color(1.0, 0.72, 0.28)])
	var count := _rng.randi_range(7, 11)
	for i in count:
		var a := i * TAU / count + _rng.randf_range(-0.2, 0.2)
		mb.leaf(Vector3.ZERO, Vector3(cos(a), 0.0, sin(a)), _rng.randf_range(0.8, 1.5), _rng.randf_range(0.12, 0.2), _rng.randf_range(0.6, 1.1), leaf, rib)
	_last_glow = rib
	return mb.commit()


## A spray of sharp glowing spines, like a sea urchin crossed with a crystal.
func _make_spike_shrub() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var color: Color = _pick([Color(0.3, 0.85, 1.0), Color(1.0, 0.5, 0.12), Color(0.15, 0.6, 1.0)])
	for i in _rng.randi_range(9, 15):
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 1.6), _rng.randf_range(-1, 1)).normalized()
		mb.crystal(Vector3.ZERO, dir, _rng.randf_range(0.3, 0.8), _rng.randf_range(0.03, 0.06), color.darkened(0.6), color)
	mb.ellipsoid(Vector3.ZERO, Vector3(0.18, 0.12, 0.18), color.darkened(0.7), color.darkened(0.5), 0.2)
	_last_glow = color
	return mb.commit()


# --- Ferns --------------------------------------------------------------------------------------

func _build_ferns() -> void:
	var variants: Array[ArrayMesh] = []
	for i in 4:
		variants.append(_make_fern())

	# Ferns cluster in the hollows where the ground-patch noise runs high, scattered over the map.
	var chunk_size := 30.0
	var chunks := {}
	var placed := 0
	var attempts := 0
	while placed < fern_count and attempts < fern_count * 20:
		attempts += 1
		var angle := _rng.randf() * TAU
		var center := Vector2(cos(angle), sin(angle)) * sqrt(_rng.randf()) * (play_radius + 10.0)
		if center.length() < 6.0 or _patches.get_noise_2d(center.x, center.y) < 0.0:
			continue
		var variant := _rng.randi() % variants.size()
		for k in _rng.randi_range(2, 5):
			var p := center + Vector2(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-2.5, 2.5))
			if _normal_at(p.x, p.y).y < 0.8:
				continue
			var s := _rng.randf_range(0.7, 1.3)
			var xform := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(p.x, height_at(p.x, p.y) - 0.05, p.y))
			var key := Vector3i(floori(p.x / chunk_size), floori(p.y / chunk_size), variant if _rng.randf() < 0.8 else _rng.randi() % variants.size())
			if not chunks.has(key):
				chunks[key] = []
			chunks[key].append(xform)
			placed += 1

	for key: Vector3i in chunks:
		var items: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variants[key.z]
		mm.instance_count = items.size()
		for i in items.size():
			mm.set_instance_transform(i, items[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Ferns_%d_%d_%d" % [key.x, key.y, key.z]
		mmi.multimesh = mm
		mmi.material_override = _flora_material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 80.0
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_generated.add_child(mmi)


## A tuft of tall fiddlehead fronds: dark stalks with paired leaflets, each tip rolled into a
## glowing spiral coil.
func _make_fern() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var stem: Color = _pick([Color(0.05, 0.1, 0.22), Color(0.2, 0.08, 0.04), Color(0.04, 0.14, 0.2)])
	var glow: Color = _pick([Color(0.3, 0.85, 1.0), Color(1.0, 0.5, 0.12), Color(1.0, 0.72, 0.28), Color(0.15, 0.6, 1.0)])
	var fronds := _rng.randi_range(5, 7)
	for f in fronds:
		var a := f * TAU / fronds + _rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0.0, sin(a))
		var h := _rng.randf_range(0.7, 1.4)
		var lean := _rng.randf_range(0.2, 0.55)
		var coil := _rng.randf_range(0.1, 0.18)
		var path: Array[Vector3] = []
		var radii: Array[float] = []
		for i in 6:
			var t := i / 5.0
			path.append(out * lean * t * t + Vector3.UP * h * t)
			radii.append(lerpf(0.035, 0.025, t))
		# The coil starts heading straight up and rolls outward over itself, tightening as it goes.
		var top := path[path.size() - 1]
		var hub := top + out * coil
		for i in range(1, 19):
			var s := i / 18.0
			var turn := s * 1.7 * TAU
			var r := coil * (1.0 - 0.75 * s)
			path.append(hub + (-out * cos(turn) + Vector3.UP * sin(turn)) * r)
			radii.append(lerpf(0.025, 0.01, s))
		mb.tube(path, radii, 5, stem, glow.darkened(0.3), glow, 0.0, 1.0)
		mb.ellipsoid(path[path.size() - 1], Vector3.ONE * 0.03, glow, glow, 1.0, 3, 6)
		var side := out.cross(Vector3.UP).normalized()
		for k in 3:
			var t := 0.3 + k * 0.2
			var at := _sample_path(path.slice(0, 6), t)
			var length := lerpf(0.32, 0.16, k / 2.0) * h
			for flip: float in [-1.0, 1.0]:
				var dir := (side * flip + out * 0.4 + Vector3.UP * 0.2).normalized()
				mb.leaf(at, dir, length, 0.05, 0.06, stem.lightened(0.1), glow)
	_last_glow = glow
	return mb.commit()


# --- Rocks and crystals -------------------------------------------------------------------------

func _build_rocks_and_crystals() -> void:
	var rocks: Array[ArrayMesh] = []
	for i in 5:
		rocks.append(_make_rock())
	var crystals: Array[ArrayMesh] = []
	var crystal_glows: Array[Color] = []
	for i in 3:
		crystals.append(_make_crystal_cluster())
		crystal_glows.append(_last_glow)

	# Outcrops and crystal clusters scattered over the hills. Boulders are solid; crystals are not.
	for i in 70:
		var angle := _rng.randf() * TAU
		var r := _rng.randf_range(clearing_radius + 4.0, 115.0)
		var p := Vector2(cos(angle), sin(angle)) * r
		var big := _rng.randf_range(1.5, 5.0)
		var tall := big * _rng.randf_range(0.6, 1.8)
		var pos := Vector3(p.x, height_at(p.x, p.y) - big * 0.2, p.y)
		_add_mesh(rocks[_rng.randi() % rocks.size()], _rock_material, pos, Vector3(big, tall, big), true)
		_add_obstacle(pos, big * 0.42, tall)
	for i in 50:
		var angle := _rng.randf() * TAU
		var r := _rng.randf_range(clearing_radius, play_radius + 10.0)
		var p := Vector2(cos(angle), sin(angle)) * r
		var ci := _rng.randi() % crystals.size()
		var pos := Vector3(p.x, height_at(p.x, p.y) - 0.1, p.y)
		_add_mesh(crystals[ci], _flora_material, pos, Vector3.ONE * _rng.randf_range(1.2, 3.0), false)
		if _rng.randf() < 0.35:
			_add_light(pos + Vector3.UP * 1.2, crystal_glows[ci], 7.0, light_energy)


func _add_light(pos: Vector3, color: Color, light_range: float, energy: float) -> void:
	if not point_lights:
		return
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = Color(color.r, color.g, color.b)
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = light_fade_distance
	light.distance_fade_length = 10.0
	_generated.add_child(light)


func _add_mesh(mesh: Mesh, material: Material, pos: Vector3, scale_by: Vector3, shadows: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(scale_by), pos)
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_generated.add_child(mi)


## A lumpy unit boulder with mossy tops and specks of glowing lichen.
func _make_rock() -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 1.6
	noise.fractal_octaves = 3
	var lichen: Color = _pick([Color(0.3, 0.85, 1.0), Color(1.0, 0.5, 0.12)])
	var mb := MeshBuilder.new()
	var rings := 10
	var segs := 14
	var grid: Array = []
	for i in rings + 1:
		var row: Array[Vector3] = []
		var v := float(i) / rings
		var phi := v * PI
		for j in segs:
			var theta := float(j) / segs * TAU
			var n := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var bump := 1.0 + noise.get_noise_3dv(n) * 0.45
			var p := n * bump * 0.5
			p.y = maxf(p.y, -0.25) + 0.25  # flat bottom, sitting on y = 0
			row.append(p)
		grid.append(row)
	for i in rings:
		for j in segs:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i][(j + 1) % segs]
			var c: Vector3 = grid[i + 1][j]
			var dd: Vector3 = grid[i + 1][(j + 1) % segs]
			for tri in [[a, b, c], [b, dd, c]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if n.dot(tri[0] - Vector3(0, 0.25, 0)) < 0.0:
					n = -n
				var cols: Array[Color] = []
				for p: Vector3 in tri:
					var moss := smoothstep(0.4, 0.8, n.y)
					var col := Color(0.3, 0.27, 0.27).lerp(Color(0.12, 0.2, 0.32), moss)
					col = col.darkened(0.25 * (1.0 - p.y))
					col.a = 0.0
					if noise.get_noise_3dv(p * 6.0 + Vector3(9, 9, 9)) > 0.42:
						col = lichen
						col.a = 0.8
					cols.append(col)
				mb.triangle(tri[0], tri[1], tri[2], n, n, n, cols[0], cols[1], cols[2])
	return mb.commit()


## Several glowing prisms jutting from one spot.
func _make_crystal_cluster() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var color: Color = _pick([Color(0.3, 0.85, 1.0), Color(1.0, 0.5, 0.12), Color(0.15, 0.6, 1.0)])
	for i in _rng.randi_range(4, 7):
		var dir := Vector3(_rng.randf_range(-0.6, 0.6), 1.0, _rng.randf_range(-0.6, 0.6)).normalized()
		var base := Vector3(_rng.randf_range(-0.25, 0.25), -0.1, _rng.randf_range(-0.25, 0.25))
		mb.crystal(base, dir, _rng.randf_range(0.6, 1.6), _rng.randf_range(0.08, 0.18), color.darkened(0.3), color.lightened(0.3))
	_last_glow = color
	return mb.commit()


# --- Spores -------------------------------------------------------------------------------------

func _build_spores() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.gradient = Gradient.new()
	dot.gradient.set_color(0, Color(1, 1, 1, 1))
	dot.gradient.set_color(1, Color(1, 1, 1, 0))
	dot.width = 32
	dot.height = 32
	material.albedo_texture = dot
	quad.material = material

	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.7, 0.3, 0.0))
	fade.set_color(1, Color(0.4, 0.8, 1.0, 0.0))
	fade.add_point(0.2, Color(1.0, 0.7, 0.3, 1.0))
	fade.add_point(0.8, Color(0.4, 0.8, 1.0, 1.0))

	var spores := CPUParticles3D.new()
	_spores = spores
	spores.name = "Spores"
	spores.mesh = quad
	spores.amount = spore_count
	spores.lifetime = 14.0
	spores.preprocess = 14.0
	spores.position = Vector3(0, 2.5, 0)
	spores.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	spores.emission_box_extents = Vector3(45, 3, 45)
	spores.direction = Vector3.UP
	spores.spread = 180.0
	spores.initial_velocity_min = 0.05
	spores.initial_velocity_max = 0.3
	spores.gravity = Vector3(0.05, 0.06, 0.02)
	spores.scale_amount_min = 0.5
	spores.scale_amount_max = 1.6
	spores.color_ramp = fade
	spores.visibility_aabb = AABB(Vector3(-50, -5, -50), Vector3(100, 20, 100))
	_generated.add_child(spores)


func _pick(options: Array) -> Variant:
	return options[_rng.randi() % options.size()]


static func _sample_path(path: Array[Vector3], t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (path.size() - 1)
	var i := mini(int(f), path.size() - 2)
	return path[i].lerp(path[i + 1], f - i)


## Collects triangles with per-vertex colours (alpha = glow) and turns them into one mesh.
class MeshBuilder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	func triangle(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
		verts.append_array([a, b, c])
		normals.append_array([na, nb, nc])
		colors.append_array([ca, cb, cc])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
		triangle(a, b, c, na, nb, nc, ca, cb, cc)
		triangle(b, d, c, nb, nd, nc, cb, cd, cc)

	## A tube along a path. Colour fades from color_a to color_b; stripe_count spiral veins glow.
	func tube(path: Array[Vector3], radii: Array[float], sides: int, color_a: Color, color_b: Color, vein: Color, stripe_count: float, glow_end := 0.0) -> void:
		var rings: Array = []
		var ring_normals: Array = []
		var ring_colors: Array = []
		var tangent := (path[1] - path[0]).normalized()
		var normal := tangent.cross(Vector3.RIGHT if absf(tangent.x) < 0.9 else Vector3.FORWARD).normalized()
		for i in path.size():
			var t := float(i) / (path.size() - 1)
			var next_tangent := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
			# Parallel transport keeps the ring from twisting as the path bends.
			normal = (normal - next_tangent * normal.dot(next_tangent)).normalized()
			tangent = next_tangent
			var binormal := tangent.cross(normal)
			var ring: Array[Vector3] = []
			var ns: Array[Vector3] = []
			var cs: Array[Color] = []
			for s in sides + 1:
				var a := float(s) / sides * TAU
				var dir := normal * cos(a) + binormal * sin(a)
				ring.append(path[i] + dir * radii[i])
				ns.append(dir)
				var col := color_a.lerp(color_b, t)
				col.a = glow_end * t * t
				if stripe_count > 0.0 and sin(a * stripe_count + t * 14.0) > 0.88:
					col = vein
					col.a = 0.7
				cs.append(col)
			rings.append(ring)
			ring_normals.append(ns)
			ring_colors.append(cs)
		for i in path.size() - 1:
			for s in sides:
				quad(rings[i][s], rings[i][s + 1], rings[i + 1][s], rings[i + 1][s + 1],
					ring_normals[i][s], ring_normals[i][s + 1], ring_normals[i + 1][s], ring_normals[i + 1][s + 1],
					ring_colors[i][s], ring_colors[i][s + 1], ring_colors[i + 1][s], ring_colors[i + 1][s + 1])

	## An ellipsoid shading from bottom_color to top_color.
	func ellipsoid(center: Vector3, radii: Vector3, bottom_color: Color, top_color: Color, glow: float, rings := 8, segs := 12) -> void:
		var grid: Array = []
		var grid_n: Array = []
		var grid_c: Array = []
		for i in rings + 1:
			var phi := float(i) / rings * PI
			var row: Array[Vector3] = []
			var row_n: Array[Vector3] = []
			var row_c: Array[Color] = []
			for j in segs + 1:
				var theta := float(j) / segs * TAU
				var n := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
				row.append(center + n * radii)
				row_n.append((n / radii).normalized())
				var col := bottom_color.lerp(top_color, 0.5 + 0.5 * n.y)
				col.a = glow
				row_c.append(col)
			grid.append(row)
			grid_n.append(row_n)
			grid_c.append(row_c)
		for i in rings:
			for j in segs:
				quad(grid[i][j], grid[i][j + 1], grid[i + 1][j], grid[i + 1][j + 1],
					grid_n[i][j], grid_n[i][j + 1], grid_n[i + 1][j], grid_n[i + 1][j + 1],
					grid_c[i][j], grid_c[i][j + 1], grid_c[i + 1][j], grid_c[i + 1][j + 1])

	## A mushroom cap: dark dome on top, glowing ribbed gills underneath.
	func cap(center: Vector3, radius: float, height: float, segs: int, rings: int, top_color: Color, gill_color: Color) -> void:
		var top: Array = []
		for i in rings + 1:
			var v := float(i) / rings
			var r := radius * sin(v * PI * 0.5)
			var y := height * cos(v * PI * 0.5) - height * 0.25 * v * v
			var row: Array[Vector3] = []
			for j in segs + 1:
				var a := float(j) / segs * TAU
				var wobble := 1.0 + 0.06 * sin(a * 5.0)
				row.append(center + Vector3(cos(a) * r * wobble, y, sin(a) * r * wobble))
			top.append(row)
		for i in rings:
			var v := float(i) / rings
			for j in segs:
				var n: Vector3 = (top[i][j + 1] - top[i][j]).cross(top[i + 1][j] - top[i][j]).normalized()
				if n.y < 0.0:
					n = -n
				var c0 := top_color.lightened(0.15 * v)
				var c1 := top_color.lightened(0.15 * (v + 1.0 / rings))
				c0.a = 0.0
				c1.a = 0.0
				if i == rings - 1:
					c1 = gill_color
					c1.a = 0.9
				quad(top[i][j], top[i][j + 1], top[i + 1][j], top[i + 1][j + 1], n, n, n, n, c0, c0, c1, c1)
		# Underside: a shallow cone from the rim up to the stalk, striped like gills.
		var hub := center + Vector3.DOWN * height * 0.1
		var rim: Array = top[rings]
		for j in segs:
			var gill := 0.4 + 0.6 * absf(sin(float(j) / segs * PI * 6.0))
			var col := gill_color.darkened(0.2 * (1.0 - gill))
			col.a = gill
			var hub_col := gill_color.darkened(0.6)
			hub_col.a = 0.3
			triangle(hub, rim[j + 1], rim[j], Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, hub_col, col, col)

	## A curved leaf blade with a glowing midrib.
	func leaf(base: Vector3, dir: Vector3, length: float, width: float, rise: float, color: Color, rib: Color) -> void:
		var side := dir.cross(Vector3.UP).normalized()
		var segments := 6
		var prev: Array[Vector3] = []
		var prev_c: Array[Color] = []
		for s in segments + 1:
			var t := float(s) / segments
			var center := base + dir * length * t + Vector3.UP * (sin(t * PI * 0.75) * rise - t * t * rise * 0.4)
			var w := width * sin(t * PI) * (1.0 - t * 0.3)
			var droop := Vector3.DOWN * w * 0.3
			var row: Array[Vector3] = [center - side * w + droop, center, center + side * w + droop]
			var edge := color.lerp(rib, t * 0.3)
			edge.a = t * 0.15
			var mid := rib
			mid.a = 0.3 + 0.6 * t
			var row_c: Array[Color] = [edge, mid, edge]
			if s > 0:
				for k in 2:
					var n := (row[k] - prev[k]).cross(prev[k + 1] - prev[k]).normalized()
					if n.y < 0.0:
						n = -n
					quad(prev[k], prev[k + 1], row[k], row[k + 1], n, n, n, n, prev_c[k], prev_c[k + 1], row_c[k], row_c[k + 1])
			prev = row
			prev_c = row_c

	## A six-sided pointed prism.
	func crystal(base: Vector3, dir: Vector3, length: float, radius: float, base_color: Color, tip_color: Color) -> void:
		var side := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized()
		var other := dir.cross(side)
		var shoulder := base + dir * length * 0.75
		var tip := base + dir * length
		var bc := base_color
		bc.a = 0.35
		var sc := tip_color.lerp(base_color, 0.3)
		sc.a = 0.8
		var tc := tip_color
		tc.a = 1.0
		for i in 6:
			var a0 := float(i) / 6.0 * TAU
			var a1 := float(i + 1) / 6.0 * TAU
			var d0 := side * cos(a0) + other * sin(a0)
			var d1 := side * cos(a1) + other * sin(a1)
			var n := (d0 + d1).normalized()
			quad(base + d0 * radius, base + d1 * radius, shoulder + d0 * radius, shoulder + d1 * radius, n, n, n, n, bc, bc, sc, sc)
			var tn := (n + dir * 0.6).normalized()
			triangle(shoulder + d0 * radius, shoulder + d1 * radius, tip, tn, tn, tn, sc, sc, tc)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
