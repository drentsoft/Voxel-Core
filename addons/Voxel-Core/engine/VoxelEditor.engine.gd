tool
extends "res://addons/Voxel-Core/src/VoxelEditor.gd"



# Refrences
const VoxelCursor := preload('res://addons/Voxel-Core/engine/VoxelCursor.gd')



# Declarations
var StartingVersion : int
signal modified(Modified)
var Modified : bool = false setget set_modified
func set_modified(modified := !Modified, emit := true) -> void:
	Modified = modified
	if emit: emit_signal('modified', modified)
var undo_redo := UndoRedo.new()
export(bool) var on_commit_clear_history := false
export(bool) var on_cancel_clear_history := false


signal set_lock(lock)
export(bool) var Lock := true setget set_lock
func set_lock(lock := !Lock, emit := true) -> void:
	Lock = lock
	if emit: emit_signal('set_lock', Lock)


signal set_tool(_tool)
enum Tools { PAN, SELECT, ADD, SUB, PICK, FILL }
export(Tools) var Tool := Tools.PAN setget set_tool
func set_tool(_tool : int, emit := true) -> void:
	Tool = _tool
	if emit: emit_signal('set_tool', Tool)

signal set_tool_mode(tool_mode)
enum ToolModes { INDIVIDUAL, AREA }
export(ToolModes) var ToolMode := ToolModes.INDIVIDUAL setget set_tool_mode
func set_tool_mode(toolmode : int, emit := true) -> void:
	ToolMode = toolmode
	if emit: emit_signal('set_tool_mode', ToolMode)


signal set_primary(voxel)
var Primary = null setget set_primary
func get_primary() -> Dictionary:
	var primary = get_rprimary()
	if typeof(primary) == TYPE_INT:
		VoxelObject.VoxelSet.get_voxel(primary)
	return primary

func get_rprimary():
	return Voxel.colored(PrimaryColor) if typeof(Primary) == TYPE_NIL else Primary

func set_primary(voxel, emit := true) -> void:
	Primary = voxel
	if emit: emit_signal('set_primary', Primary)

signal set_primary_color(color)
export(Color) var PrimaryColor := Color.white setget set_primary_color
func set_primary_color(color : Color, emit := true) -> void:
	PrimaryColor = color
	if emit: emit_signal('set_primary_color', PrimaryColor)

signal set_secondary(voxel)
var Secondary = null setget set_secondary
func get_secondary() -> Dictionary:
	var secondary = get_rsecondary()
	if typeof(secondary) == TYPE_INT:
		VoxelObject.VoxelSet.get_voxel(secondary)
	return secondary

func get_rsecondary():
	return Voxel.colored(PrimaryColor) if typeof(Secondary) == TYPE_NIL else Secondary

func set_secondary(voxel, emit := true) -> void:
	Secondary = voxel
	if emit: emit_signal('set_secondary', Secondary)

signal set_secondary_color(color)
export(Color) var SecondaryColor := Color.black setget set_secondary_color
func set_secondary_color(color : Color, emit := true) -> void:
	SecondaryColor = color
	if emit: emit_signal('set_secondary_color', SecondaryColor)


signal set_mirror_x(mirror_x)
export(bool) var MirrorX := false setget set_mirror_x
func set_mirror_x(mirrorx := !MirrorX, emit := true) -> void:
	MirrorX = mirrorx
	if emit: emit_signal('set_mirror_x', MirrorX)

signal set_mirror_y(mirror_y)
export(bool) var MirrorY := false setget set_mirror_y
func set_mirror_y(mirrory := !MirrorY, emit := true) -> void:
	MirrorY = mirrory
	if emit: emit_signal('set_mirror_y', MirrorY)

signal set_mirror_z(mirror_z)
export(bool) var MirrorZ := false setget set_mirror_z
func set_mirror_z(mirrorz := !MirrorZ, emit := true) -> void:
	MirrorZ = mirrorz
	if emit: emit_signal('set_mirror_z', MirrorZ)


# Contains a refrence to each Cursor
var Cursors := {
	Vector3(0, 0, 0): VoxelCursor.new(),
	Vector3(1, 0, 0): VoxelCursor.new(),
	Vector3(1, 1, 0): VoxelCursor.new(),
	Vector3(1, 1, 1): VoxelCursor.new(),
	Vector3(0, 1, 1): VoxelCursor.new(),
	Vector3(0, 1, 0): VoxelCursor.new(),
	Vector3(0, 0, 1): VoxelCursor.new(),
	Vector3(1, 0, 1): VoxelCursor.new()
} setget set_cursors
func set_cursors(cursor : Dictionary) -> void: return   #   Cursors shouldn't be settable externally

func setup_cursors() -> void:
	for cursor in Cursors.values():
		cursor.set_cursor_color(CursorColor)

func set_cursors_parent(parent : Node) -> void:
	unset_cursors_parent()
	for cursor in Cursors.values():
		if cursor:
			parent.add_child(cursor)

func unset_cursors_parent() -> void:
	for cursor in Cursors.values():
		if cursor and cursor.get_parent():
			cursor.get_parent().remove_child(cursor)

func set_cursors_visible(visible : bool) -> void:
	for cursor in Cursors.values():
		cursor.visible = visible

var cursors_started_area := false
var cursors_are_selecting_area := false
func update_cursors(mirrors : Dictionary) -> void:
	var all_mirrors = grid_to_mirrors(mirrors[Vector3(0, 0, 0)], true, true, true)
	for cursor_key in Cursors:
		Cursors[cursor_key].visible = CursorVisible and mirrors.has(cursor_key)
		
		if ToolMode == ToolModes.AREA:
			if cursors_are_selecting_area:
				Cursors[cursor_key].set_target_position(all_mirrors[cursor_key])
				continue
			elif cursors_started_area:
				cursors_are_selecting_area = true
		
		Cursors[cursor_key].set_cursor_position(all_mirrors[cursor_key])
		Cursors[cursor_key].set_target_position(all_mirrors[cursor_key])

signal set_cursor_visible(visible)
export(bool) var CursorVisible := true setget set_cursor_visible
func set_cursor_visible(visible := !CursorVisible, emit := true) -> void:
	CursorVisible = visible
	
	if not CursorVisible: set_cursors_visible(false)
	
	if emit: emit_signal('set_cursor_visible', CursorVisible)

signal set_cursor_color(color)
export(Color) var CursorColor := Color(1, 0, 0, 0.3) setget set_cursor_color
func set_cursor_color(color : Color, emit := true) -> void:
	CursorColor = color
	
	for cursor in Cursors.values():
		cursor.set_cursor_color(CursorColor)
	
	if emit: emit_signal('set_cursor_color', CursorColor)

signal set_cursor_type(cursortype)
export(VoxelCursor.CursorTypes) var CursorType := VoxelCursor.CursorTypes.SOLID setget set_cursor_type
func set_cursor_type(cursortype : int, emit := true) -> void:
	CursorType = cursortype
	
	for cursor in Cursors.values():
		cursor.set_cursor_type(CursorType)
	
	if emit: emit_signal('set_cursor_type', CursorType)


var Floor : MeshInstance = MeshInstance.new() setget set_floor
func set_floor(_floor : MeshInstance) -> void: return   #   Floor shouldn't be settable externally

func setup_floor() -> void: update_floor()

func update_floor() -> void:
	pass
	if Floor:
		for child in Floor.get_children():
			Floor.remove_child(child)
			child.queue_free()
		
		Floor.set_name('VEFloor')
		Floor.visible = FloorVisible
		
		match FloorType:
			FloorTypes.SOLID:
				Floor.mesh = PlaneMesh.new()
				Floor.scale = Vector3.ONE * 16 * Voxel.GridStep
				Floor.create_trimesh_collision()
				Floor.material_override = SpatialMaterial.new()
				Floor.material_override.set_cull_mode(2)
				Floor.material_override.albedo_color = FloorColor
			FloorTypes.WIRED:
				Floor.scale = Vector3.ONE
				var dimensions = Vector3.ONE * 16
				
				var ST = SurfaceTool.new()
				ST.begin(Mesh.PRIMITIVE_LINES)
				ST.add_color(FloorColor)
				
				var material = SpatialMaterial.new()
				material.roughness = 1
				material.vertex_color_is_srgb = true
				material.vertex_color_use_as_albedo = true
				material.set_cull_mode(2)
				ST.set_material(material)
				
				var x : int = -dimensions.x
				while x <= dimensions.x:
					ST.add_normal(Vector3.UP)
					ST.add_vertex(Voxel.grid_to_pos(Vector3(x, 0, -abs(dimensions.z))))
					ST.add_vertex(Voxel.grid_to_pos(Vector3(x, 0, abs(dimensions.z))))
					
					x += 1
				
				var z : int = -dimensions.z
				while z <= dimensions.z:
					ST.add_normal(Vector3.UP)
					ST.add_vertex(Voxel.grid_to_pos(Vector3(-abs(dimensions.x), 0, z)))
					ST.add_vertex(Voxel.grid_to_pos(Vector3(abs(dimensions.x), 0, z)))
					
					z += 1
				
				ST.index()
				
				Floor.mesh = ST.commit()
				Floor.create_convex_collision()
		
		if Floor.has_node('VEFloor_col'):
			Floor.get_node('VEFloor_col').get_children()[0].disabled = !FloorVisible

func set_floor_parent(parent : Node) -> void:
	unset_floor_parent()
	if Floor:
		parent.add_child(Floor)

func unset_floor_parent() -> void:
	if Floor and Floor.get_parent():
		Floor.get_parent().remove_child(Floor)

signal set_floor_visible(visible)
export(bool) var FloorVisible := true setget set_floor_visible
func set_floor_visible(visible := !FloorVisible, emit := true) -> void:
	FloorVisible = FloorConstant or visible
	if Floor:
		Floor.visible = FloorVisible
		if Floor.has_node('VEFloor_col'):
			Floor.get_node('VEFloor_col').get_children()[0].disabled = !visible
	if emit: emit_signal('set_floor_visible', FloorVisible)

signal set_floor_constant(constant)
export(bool) var FloorConstant := false setget set_floor_constant
func set_floor_constant(constant := !FloorConstant, emit := true) -> void:
	FloorConstant = constant
	
	set_floor_visible(FloorConstant or (VoxelObject and not VoxelObject.mesh))
	
	if emit: emit_signal('set_floor_constant', FloorConstant)

signal set_floor_color(color)
export(Color) var FloorColor := Color.purple setget set_floor_color
func set_floor_color(color : Color, emit := true) -> void:
	FloorColor = color
	if Floor and Floor.material_override and Floor.material_override.albedo_color: 
		Floor.material_override.albedo_color = FloorColor
	if emit: emit_signal('set_floor_color', FloorColor)

signal set_floor_type(floortype)
enum FloorTypes { SOLID, WIRED }
export(FloorTypes) var FloorType := FloorTypes.WIRED setget set_floor_type
func set_floor_type(floortype : int, emit := true) -> void:
	FloorType = floortype
	update_floor()
	if emit: emit_signal('set_floor_type', FloorType)


func set_default_options(defaultoptions := {
		'Lock': true,
		'Tool': Tools.PAN,
		'ToolMode': ToolModes.INDIVIDUAL,
		'Primary': null,
		'PrimaryColor': Color.white,
		'Secondary': null,
		'SecondaryColor': Color.black,
		'MirrorX': false,
		'MirrorY': false,
		'MirrorZ': false
	}, reset := false) -> void:
	.set_default_options(defaultoptions, reset)



# Core
func _init() -> void:
	_load()
	setup_cursors()
	setup_floor()
	set_cursors_visible(false)
func _ready() -> void:
	set_default_options()
	set_options()
	_load()

func attach_editor_components() -> void:
	set_cursors_parent(VoxelObject)
	set_floor_parent(VoxelObject)

func detach_editor_components() -> void:
	unset_cursors_parent()
	unset_floor_parent()


func edit(voxelobject : VoxelObjectClass, options := {}, update := true, emit := true) -> void:
	.edit(voxelobject, options, true, false)
	
	set_lock(true)
	Modified = false
	StartingVersion = undo_redo.get_version()
	VoxelObjectData['voxels'] = voxelobject.get_voxels()
	
	set_cursors_visible(false)
	set_floor_visible(FloorConstant or (VoxelObject and not VoxelObject.mesh))
	attach_editor_components()
	
	if emit: emit_signal('editing')

func commit(update := true, emit := true) -> void:
	if VoxelObject and VoxelObject is VoxelObjectClass:
		.commit(update, false)
		
		
		Modified = false
		StartingVersion = -1
		if on_commit_clear_history: undo_redo.clear_history()
		
		detach_editor_components()
		
		if emit: emit_signal('committed')

signal canceled
func cancel(update := true, emit := true) -> void:
	if VoxelObject and VoxelObject is VoxelObjectClass:
		VoxelObject.set_voxels(VoxelObjectData['voxels'], false)
		
		VoxelObject.set_editing(false, false)
		if update: VoxelObject.update()
		
		
		VoxelObject = null
		VoxelObjectData = {}
		
		Modified = false
		StartingVersion = -1
		if on_cancel_clear_history: undo_redo.clear_history()
		
		detach_editor_components()
		
		if emit: emit_signal('canceled')


# Helper function for easy Raycasting
# event      :   InputEventMouse       -   MouseEvent to Raycast for
# camera     :   Camera                -   Camera from which to Raycast
# @returns   :   Raycast[Dictionary]   -   Dictionary containing all Raycast info
#
# Example:
#   raycast([InputEventMouse], [Camera]) -> [Raycast]
#
func raycast(event : InputEventMouse, camera : Camera = get_viewport().get_camera()) -> Dictionary:
	var from = camera.project_ray_origin(event.position)
	var to = from + camera.project_ray_normal(event.position) * 1000
	return camera.get_world().direct_space_state.intersect_ray(from, to)

# Helper function for easy Raycasting to a VoxelObject
# event         :   InputEventMouse       -   MouseEvent to Raycast for
# camera        :   Camera                -   Camera from which to Raycast
# exclude       :   Array                 -   Collision shapes to exclude from raycast
# @returns      :   Raycast[Dictionary]   -   Dictionary containing all Raycast info
#
# Example:
#   raycast_for_voxelobject([InputEventMouse], [Camera], [VoxelObject], [ ... ]) -> [Raycast]
#
func raycast_for_voxelobject(event : InputEventMouse, camera : Camera = get_viewport().get_camera(), exclude : Array = []) -> Dictionary:
	var hit : Dictionary
	var from = camera.project_ray_origin(event.position)
	var to = from + camera.project_ray_normal(event.position) * 1000
	while true:
		hit = camera.get_world().direct_space_state.intersect_ray(from, to, exclude)
		if hit:
			if VoxelObject.is_a_parent_of(hit.collider): break
			else: exclude.append(hit.collider)
		else: break
	
	return hit

# Helper function for getting mirrors
# grid       :   Vector3                        -   Grid position to mirror according to Mirror options
# mirrorx    :   Vector3                        -   Whether to mirror over x axis
# mirrory    :   Vector3                        -   Whether to mirror over y axis
# mirrorz    :   Vector3                        -   Whether to mirror over z axis
# @returns   :   Dictionary<Vector3, Vector3>   -   Array containing original position and all mirrored position
#
# Example:
#   grid_to_mirrors(Vector(3, 1, -3)) -> [ Vector(3, 1, -3), ... ]
#
func grid_to_mirrors(grid : Vector3, mirrorx := MirrorX, mirrory := MirrorY, mirrorz := MirrorZ) -> Dictionary:
	var mirrors = { Vector3(0,0,0): grid }
	
	if mirrorx:
		mirrors[Vector3(1, 0, 0)] = Vector3(grid.x, grid.y, (grid.z + 1) * -1)
		if mirrorz:
			mirrors[Vector3(1, 0, 1)] = Vector3((grid.x + 1) * -1, grid.y, (grid.z + 1) * -1)
	if mirrory:
		mirrors[Vector3(0, 1, 0)] = Vector3(grid.x, (grid.y + 1) * -1, grid.z)
		if mirrorx:
			mirrors[Vector3(1, 1, 0)] = Vector3(grid.x, (grid.y + 1) * -1, (grid.z + 1) * -1)
		if mirrorz:
			mirrors[Vector3(0, 1, 1)] = Vector3((grid.x + 1) * -1, (grid.y + 1) * -1, grid.z)
		if mirrorx && mirrorz:
			mirrors[Vector3(1, 1, 1)] = Vector3((grid.x + 1) * -1, (grid.y + 1) * -1, (grid.z + 1) * -1)
	if mirrorz:
		mirrors[Vector3(0, 0, 1)] = Vector3((grid.x + 1) * -1, grid.y, grid.z)
	
	return mirrors


func __input(event : InputEvent, camera := get_viewport().get_camera()) -> bool:
	if not Lock and VoxelObject and VoxelObject is VoxelObjectClass:
		if event is InputEventMouse and Tool > Tools.PAN:
			var hit = raycast_for_voxelobject(event, camera)
			if hit:
				if not Tool == Tools.ADD: hit.normal *= -1
				hit.position += hit.normal  * (Voxel.VoxelSize / 2)
				var grid_pos = Voxel.abs_to_grid(VoxelObject.to_local(hit.position))
				var mirrors = grid_to_mirrors(grid_pos)
				if event.button_mask == BUTTON_MASK_RIGHT: pass
				elif event is InputEventMouseMotion and not event.is_pressed():
					update_cursors(mirrors)
					return true
				elif event is InputEventMouseButton:
					if event.button_index == BUTTON_LEFT:
						if event.is_pressed():
							if ToolMode == ToolModes.INDIVIDUAL:
								undo_redo.create_action('VoxelEditor ' + str(Tools.keys()[Tool]))
								
								for mirror in mirrors.values():
									match Tool:
										Tools.ADD:
											undo_redo.add_do_method(VoxelObject, 'set_voxel', mirror, get_rprimary(), false)
											undo_redo.add_undo_method(VoxelObject, 'erase_voxel', mirror, false)
										Tools.SUB:
											undo_redo.add_do_method(VoxelObject, 'erase_voxel', mirror, false)
											undo_redo.add_undo_method(VoxelObject, 'set_voxel', mirror, VoxelObject.get_rvoxel(mirror), false)
								undo_redo.add_do_method(VoxelObject, 'update')
								undo_redo.add_undo_method(VoxelObject, 'update')
								
								undo_redo.commit_action()
							elif ToolMode == ToolModes.AREA:
								cursors_started_area = true
							else: return false
						else:
							if ToolMode == ToolModes.AREA:
								cursors_started_area = false
								cursors_are_selecting_area = false
								
								for mirror_index in mirrors:
#									var cursor : VoxelMesh = Cursors[mirror_index]
#									var dimensions : Vector3 = (cursor.TargetPosition - cursor.CursorPosition).abs() + Vector3.ONE
#									if dimensions.x == 0: dimensions.x += 1
#									if dimensions.y == 0: dimensions.y += 1
#									if dimensions.z == 0: dimensions.z += 1
#
#									var position = Vector3(
#										cursor.CursorPosition.x if cursor.CursorPosition.x < cursor.TargetPosition.x else cursor.TargetPosition.x,
#										cursor.CursorPosition.y if cursor.CursorPosition.y < cursor.TargetPosition.y else cursor.TargetPosition.y,
#										cursor.CursorPosition.z if cursor.CursorPosition.z < cursor.TargetPosition.z else cursor.TargetPosition.z
#									)
									
									
#									var points = []
									var position = Cursors[mirror_index].grid_position()
									var dimensions = Cursors[mirror_index].get_dimensions()
									for x in range(dimensions.x):
										for y in range(dimensions.y):
											for z in range(dimensions.z):
												VoxelObject.set_voxel(position + Vector3(x, y, z), get_rprimary(), false)
#												var point = position + Vector3(x, y, z)
#												points.append(point)
#												VoxelObject.set_voxel(point, get_rprimary(), false)
								VoxelObject.update()
							else: return false
						
						update_cursors(mirrors)
						set_floor_visible(FloorConstant or (VoxelObject and not VoxelObject.mesh))
						return true
	if not event is InputEventKey: set_cursors_visible(false)
	set_floor_visible(FloorConstant or (VoxelObject and not VoxelObject.mesh))
	return false
