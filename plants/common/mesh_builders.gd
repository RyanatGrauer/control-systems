# mesh_builders.gd
#
# PURPOSE
#   Procedural meshes that Godot has no primitive for: a coil spring (helix
#   tube) and an arrow. Built from math, so no downloaded assets (README 4.4).
#
# HOW IT FITS
#   Plant visuals call these once in _ready() and then only move/scale the
#   resulting MeshInstance3D nodes each frame.
class_name MeshBuilders
extends RefCounted


# A coil spring lying along +X from x = 0 to x = 1. Stretch it by setting the
# node's scale.x to the wanted length (the coils spread out, like a real spring).
#   turns         number of coils
#   coil_radius   radius of the coil (m)
#   wire_radius   thickness of the wire (m)
static func build_spring_mesh(turns: float, coil_radius: float, wire_radius: float) -> ArrayMesh:
	const SEGMENTS_PER_TURN: int = 24
	const SIDES: int = 6  # corners on the wire's cross-section
	var ring_count := int(turns * SEGMENTS_PER_TURN) + 1
	var angular_rate := TAU * turns  # coil angle per unit of length

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	# One ring of vertices around the wire at each point along the helix.
	for ring in ring_count:
		var t := float(ring) / (ring_count - 1)
		var angle := angular_rate * t
		var center := Vector3(t, coil_radius * cos(angle), coil_radius * sin(angle))
		# Local frame: tangent along the wire, "outward" points away from the axis.
		var tangent := Vector3(1.0, -coil_radius * angular_rate * sin(angle),
				coil_radius * angular_rate * cos(angle)).normalized()
		var outward := Vector3(0.0, cos(angle), sin(angle))
		var binormal := tangent.cross(outward)
		for side in SIDES:
			var phi := TAU * side / SIDES
			var direction := outward * cos(phi) + binormal * sin(phi)
			tool.set_normal(direction)
			tool.add_vertex(center + direction * wire_radius)

	# Connect each ring to the next with two triangles per side.
	for ring in ring_count - 1:
		for side in SIDES:
			var a := ring * SIDES + side
			var b := ring * SIDES + (side + 1) % SIDES
			var c := a + SIDES
			var d := b + SIDES
			tool.add_index(a)
			tool.add_index(c)
			tool.add_index(b)
			tool.add_index(b)
			tool.add_index(c)
			tool.add_index(d)
	return tool.commit()


# An arrow pointing along +X with total length 1 (shaft + head). Scale x to
# change its length. Returns a Node3D holding the two parts.
static func build_arrow(color: Color, shaft_radius: float, head_radius: float) -> Node3D:
	const HEAD_LENGTH: float = 0.3  # fraction of the total length
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.4

	var arrow := Node3D.new()

	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = shaft_radius
	shaft_mesh.bottom_radius = shaft_radius
	shaft_mesh.height = 1.0 - HEAD_LENGTH
	var shaft := MeshInstance3D.new()
	shaft.mesh = shaft_mesh
	shaft.material_override = material
	shaft.rotation_degrees = Vector3(0.0, 0.0, -90.0)  # cylinder Y axis -> +X
	shaft.position = Vector3((1.0 - HEAD_LENGTH) * 0.5, 0.0, 0.0)
	arrow.add_child(shaft)

	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0  # a cone
	head_mesh.bottom_radius = head_radius
	head_mesh.height = HEAD_LENGTH
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.material_override = material
	head.rotation_degrees = Vector3(0.0, 0.0, -90.0)
	head.position = Vector3(1.0 - HEAD_LENGTH * 0.5, 0.0, 0.0)
	arrow.add_child(head)
	return arrow
