extends SceneTree
## Rebuild the editable scene with Godot --headless --path <project> --script res://greybox/build_scale_scene.gd.
## Nominal dimensions live in scale_spec.gd. This script is not used when playing the scene.

const Spec = preload("res://greybox/scale_spec.gd")
const OUTPUT := "res://greybox/scale_validation.tscn"
const INK := Color("263b49")
const WHITE := Color("f2f1e8")
const TEAL := Color("167b77")
const GOLD := Color("d89d35")
const BLUE := Color("6597b5")
const METAL := Color("a9b7ba")
const TIRE := Color("263139")
const BOX := Color("bd8b52")
const BARREL := Color("cb7652")
const HEAVY := Color("797194")

var scene := Node3D.new()
var font := SystemFont.new()
var materials: Dictionary = {}

func _initialize() -> void:
	scene.name = "ScaleValidation"
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	_environment()
	_site()
	_truck()
	_person("PersonA", Spec.person_position(0, 0), false, GOLD, PI / 2.0)
	_person("PersonB", Spec.person_position(1, 0), false, TEAL, PI)
	_person("PersonC", Spec.person_position(2, 0), false, BLUE, -PI / 2.0)
	_person("PersonD", Spec.person_position(3, 0), false, HEAVY, PI / 2.0)
	_person("PersonE", Spec.person_position(4, 0), false, BARREL, 0.0)
	var width_sample := scene.get_node("PersonE") as StaticBody3D
	width_sample.set_meta("sizing_only", true)
	width_sample.visible = false
	width_sample.collision_layer = 0
	_cargo()
	_observer()
	scene.set_script(load("res://greybox/scale_viewer.gd"))
	_set_owner(scene)
	var packed := PackedScene.new()
	var result := packed.pack(scene)
	if result == OK:
		result = ResourceSaver.save(packed, OUTPUT)
	if result != OK:
		push_error("Could not save scale scene: %s" % error_string(result))
		quit(1)
		return
	print("Saved editable meter-scale scene to ", OUTPUT)
	scene.free()
	quit()

func _set_owner(parent: Node) -> void:
	for child in parent.get_children():
		child.owner = scene
		_set_owner(child)

func _group(parent: Node, node_name: String, position := Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = position
	parent.add_child(node, true)
	return node

func _material(color: Color, unshaded := false) -> StandardMaterial3D:
	var key := str(color) + str(unshaded)
	if not materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.88
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		if unshaded:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		materials[key] = material
	return materials[key]

func _mesh(parent: Node, node_name: String, mesh: Mesh, position: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = position
	node.material_override = _material(color)
	parent.add_child(node, true)
	return node

func _box(parent: Node, node_name: String, size: Vector3, position: Vector3, color: Color, solid := false) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	if not solid:
		return _mesh(parent, node_name, mesh, position, color)
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	parent.add_child(body, true)
	_mesh(body, "Mesh", mesh, Vector3.ZERO, color)
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	return body

func _cylinder(parent: Node, node_name: String, radius: float, height: float, position: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 32
	return _mesh(parent, node_name, mesh, position, color)

func _line(parent: Node, a: Vector3, b: Vector3, color: Color, radius := 0.009) -> void:
	var line := _cylinder(parent, "Line", radius, a.distance_to(b), (a + b) / 2.0, color)
	line.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _label(parent: Node, text: String, position: Vector3, pixel_size := 0.0035) -> Label3D:
	var label := Label3D.new()
	label.name = "Label"
	label.text = text
	label.font = font
	label.font_size = 40
	label.pixel_size = pixel_size
	label.position = position
	label.modulate = INK
	label.outline_modulate = WHITE
	label.outline_size = 7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.set_meta("base_pixel_size", pixel_size)
	label.add_to_group("scale_labels", true)
	parent.add_child(label, true)
	return label

func _rulers(parent: Node) -> Node3D:
	var rulers := _group(parent, "Dimensions")
	rulers.add_to_group("scale_rulers", true)
	return rulers

func _dimension(parent: Node, a: Vector3, b: Vector3, text: String, label_offset := Vector3(0, 0.16, 0)) -> Node3D:
	var measure := _group(parent, "Measure")
	_line(measure, a, b, TEAL)
	var tick := Vector3.RIGHT * 0.12
	if absf(a.y - b.y) < 0.01:
		tick = (b - a).normalized().cross(Vector3.UP) * 0.12
	_line(measure, a - tick, a + tick, TEAL)
	_line(measure, b - tick, b + tick, TEAL)
	var label := _label(measure, text, (a + b) / 2.0 + label_offset)
	label.no_depth_test = true
	return measure

func _frame(parent: Node, center: Vector3, width: float, length: float, color: Color) -> void:
	var half := Vector3(width / 2.0, 0, length / 2.0)
	var corners := [center + Vector3(-half.x, 0, -half.z), center + Vector3(half.x, 0, -half.z),
		center + Vector3(half.x, 0, half.z), center + Vector3(-half.x, 0, half.z)]
	for i in 4:
		_line(parent, corners[i], corners[(i + 1) % 4], color, 0.016)

func _environment() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	var resource := Environment.new()
	resource.background_mode = Environment.BG_COLOR
	resource.background_color = Color("ced9dd")
	resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	resource.ambient_light_color = Color("dbe7ec")
	resource.ambient_light_energy = 0.5
	resource.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = resource
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_color = Color("fff1db")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100
	scene.add_child(sun)

func _site() -> void:
	var site := _group(scene, "Site")
	site.set_meta("size_m", Spec.SITE_SIZE)
	var floor_body := _box(site, "Ground_100x80", Vector3(Spec.SITE_SIZE.x, 0.2, Spec.SITE_SIZE.y), Vector3(0, -0.1, 0), Color("bfc4bd"), true) as StaticBody3D
	floor_body.physics_material_override = PhysicsMaterial.new()
	floor_body.physics_material_override.friction = 0.6
	_grid(site)
	var bounds := _group(site, "Boundary")
	_frame(bounds, Vector3(0, 0.04, 0), Spec.SITE_SIZE.x, Spec.SITE_SIZE.y, INK)
	for x in [-Spec.SITE_SIZE.x / 2.0 + 0.09, Spec.SITE_SIZE.x / 2.0 - 0.09]:
		for z in [-Spec.SITE_SIZE.y / 2.0 + 0.09, Spec.SITE_SIZE.y / 2.0 - 0.09]:
			_box(bounds, "Corner", Vector3(0.18, 0.8, 0.18), Vector3(x, 0.4, z), INK)
	_zone(site, "LoadingZone", Spec.LOAD_CENTER, Color("739a8d"), "装载区  %.0f × %.0f m" % [Spec.ZONE_SIZE, Spec.ZONE_SIZE])
	_zone(site, "UnloadingZone", Spec.UNLOAD_CENTER, Color("b79d67"), "卸货区  %.0f × %.0f m" % [Spec.ZONE_SIZE, Spec.ZONE_SIZE])
	var route := _group(site, "Route")
	var half_straight: float = Spec.STRAIGHT_LENGTH / 2.0
	var half_road: float = Spec.ROAD_WIDTH / 2.0
	var right_center := Vector3(-half_straight, 0, Spec.TURN_CENTER_RADIUS)
	var left_center := -right_center
	_box(route, "Straight_30x12", Vector3(Spec.STRAIGHT_LENGTH, 0.012, Spec.ROAD_WIDTH), Vector3(0, 0.006, 0), Color("525e65"))
	_road_curve(route, "RightTurn_R20", right_center, PI, 1.5 * PI)
	_road_curve(route, "LeftTurn_R20", left_center, 0.5 * PI, 0.0)
	for x in range(-14, 15, 3):
		_box(route, "CenterDash", Vector3(1.2, 0.008, 0.07), Vector3(x, 0.02, 0), GOLD)
	for z in [-half_road + 0.08, half_road - 0.08]:
		_box(route, "EdgeLine", Vector3(Spec.STRAIGHT_LENGTH, 0.008, 0.06), Vector3(0, 0.02, z), WHITE)
	_bump(route)
	var road_rulers := _rulers(route)
	_dimension(road_rulers, Vector3(-half_straight, 0.04, half_road + 1), Vector3(half_straight, 0.04, half_road + 1), "直线段 %.1f m" % Spec.STRAIGHT_LENGTH, Vector3(0, 0.4, 0))
	_dimension(road_rulers, Vector3(9, 0.04, -half_road), Vector3(9, 0.04, half_road), "总宽 %.1f m / 单道 %.1f m" % [Spec.ROAD_WIDTH, Spec.LANE_WIDTH], Vector3(4, 0.25, 0))
	for lane in [-1, 1]:
		var reference := _group(route, "VehicleFootprint", Vector3(-8 * lane, 0.04, lane * Spec.LANE_WIDTH / 2.0))
		reference.rotation.y = -lane * PI / 2.0
		reference.set_meta("lane", lane)
		_frame(reference, Vector3.ZERO, Spec.TRUCK_SIZE.x, Spec.TRUCK_SIZE.z, GOLD if lane > 0 else TEAL)
	_label(route, "车身 %.1f × %.1f m / 单侧余宽 %.2f m" % [Spec.TRUCK_SIZE.z, Spec.TRUCK_SIZE.x, (Spec.LANE_WIDTH - Spec.TRUCK_SIZE.x) / 2.0], Vector3(0, 0.2, -half_road - 1.2), 0.005)
	for center in [right_center, left_center]:
		for lane in [-1, 1]:
			for i in 2:
				var angle: float = PI + (i + 0.5) * PI / 4.0 if center == right_center else (i + 0.5) * PI / 4.0
				var radius: float = Spec.TURN_CENTER_RADIUS + lane * Spec.LANE_WIDTH / 2.0
				var ghost := _group(route, "TurnFootprint", center + Vector3(cos(angle), 0, sin(angle)) * radius + Vector3(0, 0.05, 0))
				ghost.rotation.y = PI - angle
				ghost.set_meta("turn_center", center)
				ghost.set_meta("lane_radius_m", radius)
				_frame(ghost, Vector3.ZERO, Spec.TRUCK_SIZE.x, Spec.TRUCK_SIZE.z, GOLD if lane > 0 else TEAL)
	_label(route, "右弯 / 中线 R%.0f m" % Spec.TURN_CENTER_RADIUS, right_center + Vector3(0, 0.2, -1), 0.006)
	_label(route, "左弯 / 中线 R%.0f m" % Spec.TURN_CENTER_RADIUS, left_center + Vector3(0, 0.2, 1), 0.006)
	var rulers := _rulers(site)
	var half_site := Spec.SITE_SIZE / 2.0
	_dimension(rulers, Vector3(-half_site.x, 0.08, half_site.y - 1), Vector3(half_site.x, 0.08, half_site.y - 1), "场地宽 %.1f m" % Spec.SITE_SIZE.x, Vector3(0, 0.4, 0))
	_dimension(rulers, Vector3(half_site.x - 1, 0.08, -half_site.y), Vector3(half_site.x - 1, 0.08, half_site.y), "场地深 %.1f m" % Spec.SITE_SIZE.y, Vector3(-2, 0.4, 0))
	var arrow_z := -half_site.y + 3
	_label(site, "-Z  场景前向", Vector3(0, 0.1, arrow_z), 0.009)
	_line(site, Vector3(0, 0.05, arrow_z + 1), Vector3(0, 0.05, arrow_z - 2), INK, 0.035)
	_line(site, Vector3(0, 0.05, arrow_z - 2), Vector3(-0.4, 0.05, arrow_z - 1.4), INK, 0.035)
	_line(site, Vector3(0, 0.05, arrow_z - 2), Vector3(0.4, 0.05, arrow_z - 1.4), INK, 0.035)
	_label(site, "+X", Vector3(4, 0.2, arrow_z), 0.007)
	_line(site, Vector3(2, 0.05, arrow_z - 1), Vector3(5, 0.05, arrow_z - 1), INK, 0.035)

func _grid(parent: Node) -> void:
	var grid := _group(parent, "MeterGrid")
	var half_x: int = int(Spec.SITE_SIZE.x / 2.0)
	var half_z: int = int(Spec.SITE_SIZE.y / 2.0)
	for major in [false, true]:
		var vertices := PackedVector3Array()
		for x in range(-half_x, half_x + 1):
			if (x % 5 == 0) == major:
				vertices.append_array(PackedVector3Array([Vector3(x, 0.003, -half_z), Vector3(x, 0.003, half_z)]))
		for z in range(-half_z, half_z + 1):
			if (z % 5 == 0) == major:
				vertices.append_array(PackedVector3Array([Vector3(-half_x, 0.003, z), Vector3(half_x, 0.003, z)]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		var node := _mesh(grid, "FiveMeterGrid" if major else "OneMeterGrid", mesh, Vector3.ZERO, INK)
		node.material_override = _material(Color("8e9d99") if major else Color("adb7af"), true)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _zone(parent: Node, node_name: String, center: Vector3, color: Color, text: String) -> void:
	var zone := _group(parent, node_name, center)
	zone.set_meta("size_m", Vector2.ONE * Spec.ZONE_SIZE)
	var half: float = Spec.ZONE_SIZE / 2.0
	_box(zone, "Paint_14x14", Vector3(Spec.ZONE_SIZE, 0.008, Spec.ZONE_SIZE), Vector3(0, 0.006, 0), color)
	_frame(zone, Vector3(0, 0.025, 0), Spec.ZONE_SIZE, Spec.ZONE_SIZE, WHITE)
	_label(zone, text, Vector3(0, 0.2, half + 0.5), 0.007)
	var rulers := _rulers(zone)
	_dimension(rulers, Vector3(-half, 0.04, half - 0.2), Vector3(half, 0.04, half - 0.2), "%.1f m" % Spec.ZONE_SIZE, Vector3(0, 0.2, -1.3))
	_dimension(rulers, Vector3(-half + 0.2, 0.04, -half), Vector3(-half + 0.2, 0.04, half), "%.1f m" % Spec.ZONE_SIZE, Vector3(-1.2, 0.2, 0))
	# The two safety positions are scale markers for the environment layout.
	_cylinder(zone, "SafetyMarker", 0.3, 0.012, Vector3(half - 0.7, 0.018, half - 0.7), WHITE)
	_label(zone, "安全点", Vector3(half + 1.5, 0.2, half - 0.7), 0.003)

func _road_curve(parent: Node, node_name: String, center: Vector3, angle_from: float, angle_to: float) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var curve := _group(parent, node_name, center)
	curve.set_meta("center_radius_m", Spec.TURN_CENTER_RADIUS)
	curve.set_meta("width_m", Spec.ROAD_WIDTH)
	for i in 65:
		var angle := lerpf(angle_from, angle_to, i / 64.0)
		for radius in [Spec.TURN_CENTER_RADIUS - Spec.ROAD_WIDTH / 2.0, Spec.TURN_CENTER_RADIUS + Spec.ROAD_WIDTH / 2.0]:
			vertices.append(Vector3(cos(angle) * radius, 0.012, sin(angle) * radius))
			normals.append(Vector3.UP)
		if i < 64:
			var a := i * 2
			if angle_to > angle_from:
				indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
			else:
				indices.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
		if i % 4 == 0 and i < 64:
			var next := lerpf(angle_from, angle_to, (i + 2) / 64.0)
			_line(curve, Vector3(cos(angle), 0, sin(angle)) * Spec.TURN_CENTER_RADIUS + Vector3(0, 0.025, 0),
				Vector3(cos(next), 0, sin(next)) * Spec.TURN_CENTER_RADIUS + Vector3(0, 0.025, 0), GOLD, 0.025)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh(curve, "RoadSurface", mesh, Vector3.ZERO, Color("525e65"))

func _bump(parent: Node) -> void:
	var bump := CSGPolygon3D.new()
	bump.name = "Bump_0_12m"
	var half_length: float = Spec.BUMP_LENGTH / 2.0
	bump.polygon = PackedVector2Array([Vector2(-half_length, 0), Vector2(-0.3, Spec.BUMP_HEIGHT), Vector2(0.3, Spec.BUMP_HEIGHT), Vector2(half_length, 0), Vector2(half_length, -0.02), Vector2(-half_length, -0.02)])
	bump.depth = Spec.ROAD_WIDTH
	bump.position.z = Spec.ROAD_WIDTH / 2.0
	bump.material = _material(GOLD)
	bump.use_collision = true
	bump.set_meta("rise_m", Spec.BUMP_HEIGHT)
	parent.add_child(bump)
	_label(parent, "凸起 +0.12 m / 构造长 2.4 m", Vector3(0, 0.4, -Spec.ROAD_WIDTH / 2.0 - 3), 0.005)

func _truck() -> void:
	var truck := _group(scene, "Truck", Spec.TRUCK_POSITION)
	truck.set_meta("outer_size_m", Spec.TRUCK_SIZE)
	truck.set_meta("bed_inner_size_m", Spec.BED_SIZE)
	truck.set_meta("bed_clear_height_m", Spec.BED_CLEAR_HEIGHT)
	truck.set_meta("roof_thickness_conflict", true)
	var width: float = Spec.TRUCK_SIZE.x
	var length: float = Spec.TRUCK_SIZE.z
	var wall_height: float = Spec.BED_CLEAR_HEIGHT
	var wall_y: float = Spec.BED_FLOOR + wall_height / 2.0
	var geometry := _group(truck, "Geometry")
	_box(geometry, "Chassis", Vector3(width - 0.5, 0.24, length - 0.2), Vector3(0, 0.4, 0), TIRE, true)
	_box(geometry, "Floor", Vector3(width, Spec.FLOOR_THICKNESS, length),
		Vector3(0, Spec.BED_FLOOR - Spec.FLOOR_THICKNESS / 2.0, 0), METAL, true)
	for side in [-1, 1]:
		_box(geometry, "SideLeft" if side < 0 else "SideRight",
			Vector3(Spec.SIDE_WALL_THICKNESS, wall_height, length),
			Vector3(side * (width / 2.0 - Spec.SIDE_WALL_THICKNESS / 2.0), wall_y, 0), BLUE, true)
	_box(geometry, "FrontWall", Vector3(width, wall_height, Spec.WALL_THICKNESS),
		Vector3(0, wall_y, -length / 2.0 + Spec.WALL_THICKNESS / 2.0), BLUE, true)
	_portal(geometry, "PartitionPortal", Spec.BED_SIZE.x, Spec.PARTITION_DOOR_SIZE, Spec.PARTITION_Z, METAL)
	_portal(geometry, "RearPortal", width, Spec.REAR_DOOR_SIZE, length / 2.0 - Spec.WALL_THICKNESS / 2.0, BLUE)
	# A zero-thickness reference preserves both supplied heights. A real roof needs a design change.
	var roof := StaticBody3D.new()
	roof.name = "RoofReference"
	roof.position.y = Spec.TRUCK_SIZE.y
	roof.set_meta("reference_thickness_m", 0.0)
	geometry.add_child(roof)
	var roof_mesh := PlaneMesh.new()
	roof_mesh.size = Vector2(width, length)
	_mesh(roof, "Mesh", roof_mesh, Vector3.ZERO, METAL)
	var roof_collision := CollisionShape3D.new()
	roof_collision.name = "Collision"
	var roof_shape := roof_mesh.create_trimesh_shape()
	roof_shape.backface_collision = true
	roof_collision.shape = roof_shape
	roof.add_child(roof_collision)
	_box(geometry, "DrivingArea", Vector3(Spec.BED_SIZE.x, 0.004, Spec.CABIN_LENGTH),
		Vector3(0, Spec.BED_FLOOR + 0.003, (Spec.CABIN_FRONT + Spec.CABIN_REAR) / 2.0), GOLD)
	for z in [Spec.FRONT_AXLE_Z, Spec.FRONT_AXLE_Z + Spec.WHEELBASE]:
		for x in [-Spec.TRACK / 2.0, Spec.TRACK / 2.0]:
			var wheel := StaticBody3D.new()
			wheel.name = "Wheel%s%s" % ["Front" if z < 0 else "Rear", "Left" if x < 0 else "Right"]
			wheel.position = Vector3(x, Spec.WHEEL_RADIUS, z)
			wheel.rotation.z = PI / 2.0
			geometry.add_child(wheel)
			_cylinder(wheel, "Tire", Spec.WHEEL_RADIUS, Spec.TIRE_WIDTH, Vector3.ZERO, TIRE)
			var collider := CollisionShape3D.new()
			collider.name = "Collision"
			var shape := CylinderShape3D.new()
			shape.radius = Spec.WHEEL_RADIUS
			shape.height = Spec.TIRE_WIDTH
			collider.shape = shape
			wheel.add_child(collider)
	# One tilted box supplies a continuous observation route from ground to the rear floor.
	var ramp_length := Vector2(Spec.BED_FLOOR, Spec.RAMP_RUN).length()
	var ramp_angle := atan2(Spec.BED_FLOOR, Spec.RAMP_RUN)
	var ramp_normal := Vector3(0, cos(ramp_angle), sin(ramp_angle))
	var ramp_top := Vector3(0, Spec.BED_FLOOR / 2.0, length / 2.0 + Spec.RAMP_RUN / 2.0)
	var ramp := _box(geometry, "AccessRamp", Vector3(Spec.REAR_DOOR_SIZE.x, 0.08, ramp_length),
		ramp_top - ramp_normal * 0.04, METAL, true)
	ramp.rotation.x = ramp_angle
	var rulers := _rulers(truck)
	var half_length := length / 2.0
	var half_width := width / 2.0
	var measure := _dimension(rulers, Vector3(half_width + 0.4, Spec.TRUCK_SIZE.y + 0.4, -half_length), Vector3(half_width + 0.4, Spec.TRUCK_SIZE.y + 0.4, half_length), "车长 %.2f m" % length)
	measure.set_meta("views", [1])
	measure = _dimension(rulers, Vector3(-half_width, 0.05, half_length + 0.8), Vector3(half_width, 0.05, half_length + 0.8), "车宽 4.30 m")
	measure.set_meta("views", [2])
	measure.set_meta("width_study", true)
	measure = _dimension(rulers, Vector3(half_width + 0.3, 0, -half_length - 0.5), Vector3(half_width + 0.3, Spec.TRUCK_SIZE.y, -half_length - 0.5), "车高 %.2f m" % Spec.TRUCK_SIZE.y, Vector3(0.4, 0, 0))
	measure.set_meta("views", [1])
	measure = _dimension(rulers, Vector3(half_width + 0.4, Spec.BED_FLOOR, Spec.BED_FRONT),
		Vector3(half_width + 0.4, Spec.BED_FLOOR, Spec.BED_REAR), "净长 %.2f m" % Spec.BED_SIZE.y, Vector3(0.6, 0.15, 0))
	measure.set_meta("views", [3])
	measure = _dimension(rulers, Vector3(-Spec.BED_SIZE.x / 2.0, Spec.TRUCK_SIZE.y + 0.5, half_length + 0.4), Vector3(Spec.BED_SIZE.x / 2.0, Spec.TRUCK_SIZE.y + 0.5, half_length + 0.4), "净宽 4.00 m")
	measure.set_meta("views", [2, 3])
	measure.set_meta("width_study", true)
	measure = _dimension(rulers, Vector3(-half_width - 0.4, Spec.BED_FLOOR, half_length + 0.2),
		Vector3(-half_width - 0.4, Spec.TRUCK_SIZE.y, half_length + 0.2), "净高 %.2f m" % Spec.BED_CLEAR_HEIGHT, Vector3(-0.5, 0, 0))
	measure.set_meta("views", [2])
	measure = _dimension(rulers, Vector3(half_width + 0.4, 0, half_length + 0.2), Vector3(half_width + 0.4, Spec.BED_FLOOR, half_length + 0.2), "地板 0.70 m", Vector3(0.6, 0, 0))
	measure.set_meta("views", [2])
	measure = _dimension(rulers, Vector3(-0.4, Spec.BED_FLOOR + 0.02, Spec.PARTITION_Z),
		Vector3(0.4, Spec.BED_FLOOR + 0.02, Spec.PARTITION_Z), "隔断门 0.80 m", Vector3(0, 0.2, -0.5))
	measure.set_meta("views", [3])
	measure = _dimension(rulers, Vector3(-0.8, Spec.BED_FLOOR + 0.02, half_length + 0.2),
		Vector3(0.8, Spec.BED_FLOOR + 0.02, half_length + 0.2), "后门 1.60 m", Vector3(0, 0.2, 0))
	measure.set_meta("views", [2])
	measure = _dimension(rulers, Vector3(-0.9, Spec.BED_FLOOR, half_length + 0.2),
		Vector3(-0.9, Spec.BED_FLOOR + Spec.REAR_DOOR_SIZE.y, half_length + 0.2), "后门净高 2.00 m", Vector3(-0.5, 0, 0))
	measure.set_meta("views", [2])
	measure = _dimension(rulers, Vector3(-half_width - 0.4, Spec.BED_FLOOR, Spec.CABIN_FRONT),
		Vector3(-half_width - 0.4, Spec.BED_FLOOR, Spec.CABIN_REAR), "驾驶区 %.2f m" % Spec.CABIN_LENGTH, Vector3(-0.4, 0.15, 0))
	measure.set_meta("views", [3])
	var footprint := _group(rulers, "BedFootprint")
	footprint.set_meta("views", [0, 3])
	_frame(footprint, Vector3(0, Spec.BED_FLOOR + 0.01, Spec.BED_CENTER_Z), Spec.BED_SIZE.x, Spec.BED_SIZE.y, TEAL)
	var row := _dimension(rulers, Vector3(-Spec.BED_SIZE.x / 2.0, Spec.BED_FLOOR + 0.02, Spec.BED_CENTER_Z + 0.9),
		Vector3(Spec.BED_SIZE.x / 2.0, Spec.BED_FLOOR + 0.02, Spec.BED_CENTER_Z + 0.9), "5 × 0.80 = 4.00 m", Vector3(0, -0.3, 0.25))
	row.name = "FivePersonWidth"
	row.set_meta("views", [0, 2, 3])
	row.set_meta("width_study", true)
	var work := _rulers(scene)
	var rear_z: float = Spec.TRUCK_POSITION.z + half_length
	var loading_end: float = Spec.LOAD_CENTER.z + Spec.ZONE_SIZE / 2.0
	var work_x: float = Spec.TRUCK_POSITION.x - half_width - 0.6
	_dimension(work, Vector3(work_x, 0.03, rear_z), Vector3(work_x, 0.03, loading_end),
		"标线内车后余深 %.2f m" % (loading_end - rear_z), Vector3(-0.3, 0.2, 0))
	_label(truck, "车头 -Z", Vector3(0, 0.1, -half_length - 0.7))

func _portal(parent: Node, node_name: String, wall_width: float, opening: Vector2, z: float, color: Color) -> void:
	var portal := _group(parent, node_name, Vector3(0, Spec.BED_FLOOR, z))
	portal.set_meta("clear_opening_m", opening)
	var jamb_width: float = (wall_width - opening.x) / 2.0
	for side in [-1, 1]:
		_box(portal, "JambLeft" if side < 0 else "JambRight",
			Vector3(jamb_width, Spec.BED_CLEAR_HEIGHT, Spec.WALL_THICKNESS),
			Vector3(side * (opening.x + jamb_width) / 2.0, Spec.BED_CLEAR_HEIGHT / 2.0, 0), color, true)
	var header_height: float = Spec.BED_CLEAR_HEIGHT - opening.y
	_box(portal, "Header", Vector3(opening.x, header_height, Spec.WALL_THICKNESS),
		Vector3(0, opening.y + header_height / 2.0, 0), color, true)
	_box(portal, "Door", Vector3(opening.x, opening.y, 0.06),
		Vector3(0, opening.y / 2.0, 0), GOLD, true)

func _person(node_name: String, position: Vector3, crouched: bool, color: Color, yaw: float) -> void:
	var person := StaticBody3D.new()
	person.name = node_name
	person.position = position
	person.rotation.y = yaw
	scene.add_child(person)
	var height: float = Spec.CROUCH_HEIGHT if crouched else Spec.PERSON_HEIGHT
	var eye: float = Spec.CROUCHING_EYE if crouched else Spec.STANDING_EYE
	person.set_meta("height_m", height)
	person.set_meta("eye_height_m", eye)
	person.set_meta("visual_width_m", Spec.PERSON_VISUAL_WIDTH)
	person.set_meta("collision_diameter_m", Spec.PERSON_DIAMETER)
	person.set_meta("head_diameter_m", Spec.HEAD_DIAMETER)
	var profile: Dictionary = Spec.person_profile(crouched)
	var capsule := CapsuleMesh.new()
	capsule.resource_local_to_scene = true
	capsule.radius = Spec.BODY_RADIUS
	capsule.height = profile.body_height
	capsule.radial_segments = 16
	capsule.rings = 8
	_mesh(person, "Body", capsule, Vector3(0, profile.body_y, 0), color)
	var sphere := SphereMesh.new()
	sphere.radius = Spec.HEAD_DIAMETER / 2.0
	sphere.height = Spec.HEAD_DIAMETER
	sphere.radial_segments = 16
	sphere.rings = 8
	_mesh(person, "Head", sphere, Vector3(0, profile.head_y, 0), WHITE)
	for side in [-1, 1]:
		var suffix := "Left" if side < 0 else "Right"
		var arm := CapsuleMesh.new()
		arm.resource_local_to_scene = true
		arm.radius = Spec.ARM_RADIUS
		arm.height = profile.arm_height
		arm.radial_segments = 16
		arm.rings = 6
		_mesh(person, "Arm" + suffix, arm, Vector3(side * Spec.ARM_X, profile.arm_y, 0), color)
		var hand := SphereMesh.new()
		hand.radius = Spec.ARM_RADIUS
		hand.height = Spec.ARM_RADIUS * 2.0
		hand.radial_segments = 16
		hand.rings = 6
		_mesh(person, "Hand" + suffix, hand, Vector3(side * Spec.ARM_X, profile.hand_y, 0), WHITE)
		var leg := CapsuleMesh.new()
		leg.resource_local_to_scene = true
		leg.radius = Spec.LEG_RADIUS
		leg.height = profile.leg_height
		leg.radial_segments = 16
		leg.rings = 6
		_mesh(person, "Leg" + suffix, leg, Vector3(side * Spec.LEG_X, profile.leg_y, 0), color)
		_box(person, "Foot" + suffix, Spec.FOOT_SIZE, Vector3(side * Spec.LEG_X, Spec.FOOT_SIZE.y / 2.0, -0.06), TIRE)
	_box(person, "FrontMarker", Vector3(0.12, 0.10, 0.03), Vector3(0, profile.body_y, -Spec.BODY_RADIUS), WHITE)
	var shape := CapsuleShape3D.new()
	shape.resource_local_to_scene = true
	shape.radius = Spec.PERSON_DIAMETER / 2.0
	shape.height = height
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	collider.position.y = height / 2.0
	person.add_child(collider)
	var eye_point := Marker3D.new()
	eye_point.name = "EyePoint"
	eye_point.position.y = eye
	person.add_child(eye_point)
	if node_name in ["PersonA", "PersonB"]:
		var rulers := _rulers(person)
		var height_base := Vector3(0.6, 0, 0) if node_name == "PersonA" else Vector3(0, 0, -0.6)
		var height_offset := Vector3(0.4, 0, 0) if node_name == "PersonA" else Vector3(0, height / 2.0 + 0.15, -0.5)
		var height_measure := _dimension(rulers, height_base, height_base + Vector3.UP * height, "%.2f m" % height, height_offset)
		height_measure.name = "HeightMeasure"
		if node_name == "PersonA":
			var visual_width := _dimension(rulers, Vector3(-Spec.PERSON_VISUAL_WIDTH / 2.0, 0.03, 0.5),
				Vector3(Spec.PERSON_VISUAL_WIDTH / 2.0, 0.03, 0.5), "视觉宽 0.80 m", Vector3(0, -0.25, 0.25))
			visual_width.name = "VisualWidthMeasure"
			var collision_width := _dimension(rulers, Vector3(-Spec.PERSON_DIAMETER / 2.0, 0.03, -0.5),
				Vector3(Spec.PERSON_DIAMETER / 2.0, 0.03, -0.5), "碰撞 Ø0.60 m", Vector3(0, -0.55, -0.25))
			collision_width.name = "CollisionWidthMeasure"
		var eye_measure := _group(rulers, "EyeMeasure", Vector3(0, eye, 0))
		_line(eye_measure, Vector3(-0.27, 0, -0.2), Vector3(0.27, 0, -0.2), TEAL, 0.006)
		var eye_offset := Vector3(-0.65, 0, 0) if node_name == "PersonA" else Vector3(0, 0, 0.8)
		var eye_label := _label(eye_measure, "眼高 %.2f m" % eye, eye_offset)
		eye_label.no_depth_test = true
	var title := _label(person, node_name.trim_prefix("Person"), Vector3(0, height + 0.3, 0))
	title.name = "PersonLabel"

func _cargo() -> void:
	var group := _group(scene, "Cargo")
	for i in 6:
		var kind: String = Spec.CARGO_TYPES[i]
		var size: Vector3 = Spec.CARGO_SIZES[kind]
		var body := StaticBody3D.new()
		body.name = Spec.CARGO_IDS[i]
		body.position = Spec.GROUND_POSITIONS[i]
		body.set_meta("cargo_type", kind)
		body.set_meta("size_m", size)
		body.set_meta("mass_kg", Spec.CARGO_MASSES[kind])
		group.add_child(body)
		var collider := CollisionShape3D.new()
		collider.name = "Collision"
		collider.position.y = size.y / 2.0
		if kind == "barrel":
			_cylinder(body, "Geometry", size.x / 2.0, size.y, Vector3(0, size.y / 2.0, 0), BARREL)
			var shape := CylinderShape3D.new()
			shape.radius = size.x / 2.0
			shape.height = size.y
			collider.shape = shape
		else:
			_box(body, "Geometry", size, Vector3(0, size.y / 2.0, 0), BOX if kind == "box" else HEAVY)
			var shape := BoxShape3D.new()
			shape.size = size
			collider.shape = shape
		body.add_child(collider)
		var cargo_name: String = {"box": "木箱", "barrel": "圆桶", "heavy": "重物"}[kind]
		var text: String = "%s · %s" % [Spec.CARGO_IDS[i], cargo_name]
		var label := _label(body, text, Vector3(0, size.y + 0.18, 0), 0.0045)
		label.name = "CargoLabel"

func _observer() -> void:
	var camera := Camera3D.new()
	camera.name = "ViewCamera"
	camera.current = true
	camera.near = 0.04
	camera.far = 180.0
	camera.fov = 60.0
	camera.look_at_from_position(Spec.TRUCK_POSITION + Vector3(11, 8, 14), Spec.TRUCK_POSITION + Vector3(0, Spec.TRUCK_SIZE.y * 0.45, 0.4))
	scene.add_child(camera)
	var observer := CharacterBody3D.new()
	observer.name = "Observer"
	observer.collision_layer = 0
	observer.collision_mask = 1
	observer.floor_snap_length = 0.15
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	collider.position.y = 0.9
	observer.add_child(collider)
	scene.add_child(observer)
