tool
extends Control
# 2D / 3D preview of a voxel, that allows for selection and editing of faces.



## Signals
# Emitted when a voxel face has been selected
signal selected_face(face)
# Emitted when a voxel face has been unselected
signal unselected_face(face)



## Enums
# View modes available
enum ViewModes { VIEW_2D, VIEW_3D }



## Exported Variables
# Number of uv positions that can be selected at any one time
export(int, 0, 6) var selection_max := 0 setget set_selection_max

# Flag indicating whether edits are allowed
export var allow_edit := false setget set_allow_edit

# Current view being shown
export(ViewModes) var view_mode := ViewModes.VIEW_3D setget set_view_mode

# View sensitivity for the 3D view
export(int, 0, 100) var camera_sensitivity := 8

# ID of voxel to represented
export var voxel_id : int setget set_voxel_id

# VoxelSet beings used
export(Resource) var voxel_set = null setget set_voxel_set



## Public Variables
# UndoRedo used to commit operations
var undo_redo : UndoRedo



## Private Variables
# Selected voxel ids
var _selections := []

# VoxelTool used for Mesh generation
var _voxel_tool := VoxelTool.new()

# Internal flag used to know whether user is dragging in 3D view
var _is_dragging := false

# Internal flag used to know the last face the user hovered
var _last_hovered_face := Vector3.ZERO

# Internal value used to revert to old versions of voxel data
var _unedited_voxel := {}

# Internal flag used to indicate the operation being committed
var _editing_action := -1

# Internal flag used to indicate the face being edited
var _editing_face := Vector3.ZERO

# Internal flag used to indicate whether multiple faces are being edited
var _editing_multiple := false



## OnReady Variables
onready var View2D := get_node("View2D")

onready var View3D := get_node("View3D")

onready var CameraPivot := get_node("View3D/Viewport/CameraPivot")

onready var CameraRef := get_node("View3D/Viewport/CameraPivot/Camera")

onready var VoxelPreview := get_node("View3D/Viewport/VoxelPreview")

onready var Select := get_node("View3D/Viewport/Select")

onready var ViewModeRef := get_node("ToolBar/ViewMode")

onready var ViewerHint := get_node("ToolBar/Hint")

onready var ContextMenu := get_node("ContextMenu")

onready var ColorMenu := get_node("ColorMenu")

onready var VoxelColor := get_node("ColorMenu/VBoxContainer/VoxelColor")

onready var TextureMenu := get_node("TextureMenu")

onready var VoxelTexture := get_node("TextureMenu/VBoxContainer/ScrollContainer/VoxelTexture")

onready var MaterialMenu := get_node("MaterialMenu")

onready var MaterialRef := get_node("MaterialMenu/VBoxContainer/VBoxContainer/HBoxContainer6/Material")

onready var Metallic := get_node("MaterialMenu/VBoxContainer/VBoxContainer/HBoxContainer/Metallic")

onready var Specular := get_node("MaterialMenu/VBoxContainer/VBoxContainer/HBoxContainer2/Specular")

onready var Roughness := get_node("MaterialMenu/VBoxContainer/VBoxContainer/HBoxContainer3/Roughness")

onready var Energy := get_node("MaterialMenu/VBoxContainer/VBoxContainer/HBoxContainer4/Energy")

onready var EnergyColor := get_node("MaterialMenu/VBoxContainer/VBoxContainer/HBoxContainer5/EnergyColor")



## Built-In Virtual Methods
func _ready():
	set_view_mode(view_mode)
	set_voxel_set(voxel_set)
	
	if not is_instance_valid(undo_redo):
		undo_redo = UndoRedo.new()



## Public Methods
func set_selection_max(value : int, update := true) -> void:
	selection_max = clamp(value, 0, 6)
	unselect_shrink()
	if update:
		self.update()


# Sets allow_edit
func set_allow_edit(value : bool) -> void:
	allow_edit = value


# Sets view_mode
func set_view_mode(value : int) -> void:
	_last_hovered_face = Vector3.ZERO
	view_mode = int(clamp(value, 0, ViewModes.size()))
	
	if is_instance_valid(ViewModeRef):
		ViewModeRef.selected = view_mode
	if is_instance_valid(View2D):
		View2D.visible = view_mode == ViewModes.VIEW_2D
	if is_instance_valid(View3D):
		View3D.visible = view_mode == ViewModes.VIEW_3D


# Sets voxel_id, calls on update_view by defalut
func set_voxel_id(value : int, update := true) -> void:
	voxel_id = value
	if update:
		update_view()


# Sets voxel_set, and calls on update by default
func set_voxel_set(value : Resource, update := true) -> void:
	if not (typeof(value) == TYPE_NIL or value is VoxelSet):
		printerr("Invalid Resource given expected VoxelSet")
		return
	
	if is_instance_valid(voxel_set):
		if voxel_set.is_connected("requested_refresh", self, "update_view"):
			voxel_set.disconnect("requested_refresh", self, "update_view") 
	
	voxel_set = value
	if is_instance_valid(voxel_set):
		if not voxel_set.is_connected("requested_refresh", self, "update_view"):
			voxel_set.connect("requested_refresh", self, "update_view")
	if is_instance_valid(VoxelTexture):
		VoxelTexture.voxel_set = voxel_set
	
	if update:
		update_view()


# Return normal associated with given name
func string_to_face(string : String) -> Vector3:
	string = string.to_upper()
	var normal := Vector3.ZERO
	match string:
		"RIGHT":
			normal = Vector3.RIGHT
		"LEFT":
			normal = Vector3.LEFT
		"TOP":
			normal = Vector3.UP
		"BOTTOM":
			normal = Vector3.DOWN
		"FRONT":
			normal = Vector3.FORWARD
		"BACK":
			normal = Vector3.BACK
	return normal

# Return name associated with given face
func face_to_string(face : Vector3) -> String:
	var string := ""
	match face:
		Vector3.RIGHT:
			string = "RIGHT"
		Vector3.LEFT:
			string = "LEFT"
		Vector3.UP:
			string = "TOP"
		Vector3.DOWN:
			string = "BOTTOM"
		Vector3.FORWARD:
			string = "FRONT"
		Vector3.BACK:
			string = "BACK"
	return string


# Quick setup of voxel_set, voxel_id; calls on update_view and update_hint
func setup(voxel_set : VoxelSet, voxel_set_id : int) -> void:
	set_voxel_set(voxel_set, false)
	set_voxel_id(voxel_set_id, false)
	update_view()
	update_hint()


# Returns the voxel data of current voxel, returns a empty Dictionary if not set
func get_viewing_voxel() -> Dictionary:
	return voxel_set.get_voxel(voxel_id) if is_instance_valid(voxel_set) else {}


# Returns the VoxelButton associated with face normal
func get_voxle_button(face_normal : Vector3):
	return View2D.find_node(face_to_string(face_normal).capitalize())


# Selects given face, and emits selected_face
func select(face : Vector3, emit := true) -> void:
	if selection_max != 0:
		unselect_shrink(selection_max - 1)
		_selections.append(face)
		var voxel_button = get_voxle_button(face)
		if is_instance_valid(voxel_button):
			voxel_button.pressed = true
		if emit:
			emit_signal("selected_face", face)


# Unselects given face, and emits unselected_face
func unselect(face : Vector3, emit := true) -> void:
	if _selections.has(face):
		_selections.erase(face)
		var voxel_button = get_voxle_button(face)
		if is_instance_valid(voxel_button):
			voxel_button.pressed = false
		if emit:
			emit_signal("unselected_face", face)


# Unselects all the faces
func unselect_all() -> void:
	while not _selections.empty():
		unselect(_selections.back())


# Unselects all faces until given size is met
func unselect_shrink(size := selection_max, emit := true) -> void:
	if size >= 0:
		while _selections.size() > size:
			unselect(_selections.back(), emit)


# Updates the hint message
func update_hint() -> void:
	if is_instance_valid(ViewerHint):
		ViewerHint.text = ""
		
		if not _selections.empty():
			for i in range(len(_selections)):
				if i > 0:
					ViewerHint.text += ", "
				ViewerHint.text += face_to_string(_selections[i]).to_upper()
		
		if _last_hovered_face != Vector3.ZERO:
			if not ViewerHint.text.empty():
				ViewerHint.text += " | "
			ViewerHint.text += face_to_string(_last_hovered_face).to_upper()


# Updates the view
func update_view() -> void:
	if not is_instance_valid(voxel_set):
		return
	
	if is_instance_valid(View2D):
		for voxel_button in View2D.get_children():
			voxel_button.setup(voxel_set, voxel_id, string_to_face(voxel_button.name))
			voxel_button.hint_tooltip = voxel_button.name
	
	if is_instance_valid(VoxelPreview):
		_voxel_tool.begin(voxel_set, true)
		for face in Voxel.Faces:
			_voxel_tool.add_face(
				get_viewing_voxel(),
				face,
				-Vector3.ONE / 2
			)
		VoxelPreview.mesh = _voxel_tool.commit()
		
		_voxel_tool.begin(voxel_set, true)
		for selection in _selections:
			_voxel_tool.add_face(
				Voxel.colored(Color(0, 0, 0, 0.75)),
				selection,
				-Vector3.ONE / 2
			)
		Select.mesh = _voxel_tool.commit()


# Shows the context menu and options according to context
func show_context_menu(global_position : Vector2, face := _last_hovered_face) -> void:
	_editing_face = face
	_editing_multiple = false
	var selected_hovered := _selections.has(_editing_face)
	if is_instance_valid(ContextMenu) and is_instance_valid(voxel_set):
		ContextMenu.clear()
		
		if _selections.size() < 6:
			ContextMenu.add_item("Select all", 13)
		if _selections.size() > 0:
			ContextMenu.add_item("Unselect all", 11)
		
		if _selections.size() == 0 or not selected_hovered:
			ContextMenu.add_separator()
			ContextMenu.add_item("Color side", 0)
			if Voxel.has_face_color(get_viewing_voxel(), _editing_face):
				ContextMenu.add_item("Remove side color", 1)
			
			if voxel_set.uv_ready():
				ContextMenu.add_item("Texture side", 2)
			if Voxel.has_face_uv(get_viewing_voxel(), _editing_face):
				ContextMenu.add_item("Remove side uv", 3)
		
		if selected_hovered and _selections.size() >= 1:
			ContextMenu.add_separator()
			ContextMenu.add_item("Color side(s)", 7)
			if Voxel.has_face_color(get_viewing_voxel(), _editing_face):
				ContextMenu.add_item("Remove side color(s)", 8)
			
			if voxel_set.uv_ready():
				ContextMenu.add_item("Texture side(s)", 9)
			if Voxel.has_face_uv(get_viewing_voxel(), _editing_face):
				ContextMenu.add_item("Remove side uv(s)", 10)
		
		ContextMenu.add_separator()
		ContextMenu.add_item("Color voxel", 4)
		
		ContextMenu.add_item("Modify material", 12)
		
		if voxel_set.uv_ready():
			ContextMenu.add_item("Texture voxel", 5)
		if Voxel.has_uv(get_viewing_voxel()):
			ContextMenu.add_item("Remove voxel uv", 6)
		ContextMenu.set_as_minsize()
		
		ContextMenu.popup(Rect2(
				global_position,
				ContextMenu.rect_size))


# Shows the color menu centered with given color
func show_color_menu(color : Color) -> void:
	if is_instance_valid(ColorMenu):
		VoxelColor.color = color
		ColorMenu.popup_centered()


# Closes the color menu
func close_color_menu() -> void:
	if is_instance_valid(ColorMenu):
		ColorMenu.hide()
	update_view()


# Shows the texture menu centered with given color
func show_texture_menu(uv : Vector2) -> void:
	if is_instance_valid(TextureMenu):
		VoxelTexture.unselect_all()
		VoxelTexture.select(uv)
		TextureMenu.popup_centered()


# Closes the texture menu
func close_texture_menu() -> void:
	if is_instance_valid(TextureMenu):
		TextureMenu.hide()
	update_view()


# Shows the material menu with given voxel data
func show_material_menu(voxel := get_viewing_voxel()) -> void:
	if is_instance_valid(MaterialMenu):
		Metallic.value = Voxel.get_metallic(voxel)
		Specular.value = Voxel.get_specular(voxel)
		Roughness.value = Voxel.get_roughness(voxel)
		Energy.value = Voxel.get_energy(voxel)
		EnergyColor.color = Voxel.get_energy_color(voxel)
		MaterialMenu.popup_centered()


# Closes the material menu
func close_material_menu() -> void:
	if is_instance_valid(MaterialMenu):
		MaterialMenu.hide()
	update_view()



## Private Methods
func _set_last_hovered_face(face : Vector3):
	_last_hovered_face = face


func _on_Face_gui_input(event : InputEvent, normal : Vector3) -> void:
	_last_hovered_face = normal
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == BUTTON_LEFT:
			if selection_max > 0:
				if _selections.has(normal):
					unselect(normal)
				else:
					select(normal)
				accept_event()
			else:
				get_voxle_button(normal).pressed = false
		elif event.button_index == BUTTON_RIGHT:
			if allow_edit:
				show_context_menu(event.global_position, _last_hovered_face)
	update_hint()


func _on_View3D_gui_input(event : InputEvent) -> void:
	if event is InputEventMouse:
		var from = CameraRef.project_ray_origin(event.position)
		var to = from + CameraRef.project_ray_normal(event.position) * 1000
		var hit = CameraRef.get_world().direct_space_state.intersect_ray(from, to)
		if hit.empty():
			_last_hovered_face = Vector3.ZERO
		else:
			hit["normal"] = hit["normal"].round()
			_last_hovered_face = hit["normal"]
		
		if event is InputEventMouseMotion:
			if _is_dragging:
				var motion = event.relative.normalized()
				CameraPivot.rotation_degrees.x += -motion.y * camera_sensitivity
				CameraPivot.rotation_degrees.y += -motion.x * camera_sensitivity
		elif event is InputEventMouseButton:
			if event.button_index == BUTTON_LEFT:
				if event.doubleclick:
					if not hit.empty() and selection_max > 0:
						if _selections.has(hit["normal"]):
							unselect(hit["normal"])
						else:
							select(hit["normal"])
				elif event.is_pressed():
					_is_dragging = true
				else:
					_is_dragging = false
			elif event.button_index == BUTTON_RIGHT and not _last_hovered_face == Vector3.ZERO:
				if allow_edit:
					show_context_menu(event.global_position, _last_hovered_face)
		
		if _is_dragging:
			View3D.set_default_cursor_shape(Control.CURSOR_MOVE)
		elif hit:
			View3D.set_default_cursor_shape(Control.CURSOR_POINTING_HAND)
		else:
			View3D.set_default_cursor_shape(Control.CURSOR_ARROW)
		update_hint()
		update_view()


func _on_ContextMenu_id_pressed(id : int):
	_editing_action = id
	_editing_multiple = false
	_unedited_voxel = get_viewing_voxel().duplicate(true)
	match id:
		0: # Color editing face
			show_color_menu(Voxel.get_face_color(get_viewing_voxel(), _editing_face))
		1: # Remove editing face color
			var voxel = get_viewing_voxel()
			undo_redo.create_action("VoxelViewer : Remove side color")
			undo_redo.add_do_method(Voxel, "remove_face_color", voxel, _editing_face)
			undo_redo.add_undo_method(Voxel, "set_face_color", voxel, _editing_face, Voxel.get_face_color(voxel, _editing_face))
			undo_redo.add_do_method(voxel_set, "request_refresh")
			undo_redo.add_undo_method(voxel_set, "request_refresh")
			undo_redo.commit_action()
		2: # Texture editing face
			show_texture_menu(Voxel.get_face_uv(get_viewing_voxel(), _editing_face))
		3: # Remove editing face uv
			var voxel := get_viewing_voxel()
			undo_redo.create_action("VoxelViewer : Remove side uv")
			undo_redo.add_do_method(Voxel, "remove_face_uv", voxel, _editing_face)
			undo_redo.add_undo_method(Voxel, "set_face_uv", voxel, _editing_face, Voxel.get_face_uv(voxel, _editing_face))
			undo_redo.add_do_method(voxel_set, "request_refresh")
			undo_redo.add_undo_method(voxel_set, "request_refresh")
			undo_redo.commit_action()
		7: # Color selected faces
			_editing_multiple = true
			show_color_menu(Voxel.get_face_color(get_viewing_voxel(), _editing_face))
		8: # Remove selected faces color
			_editing_multiple = true
			var voxel = get_viewing_voxel()
			undo_redo.create_action("VoxelViewer : Remove side colors")
			for selection in _selections:
				undo_redo.add_do_method(Voxel, "remove_face_color", voxel, selection)
				undo_redo.add_undo_method(Voxel, "set_face_color", voxel, selection, Voxel.get_face_color(voxel, selection))
			undo_redo.add_do_method(voxel_set, "request_refresh")
			undo_redo.add_undo_method(voxel_set, "request_refresh")
			undo_redo.commit_action()
		9: # Texture selected face
			_editing_multiple = true
			show_texture_menu(Voxel.get_face_uv(get_viewing_voxel(), _editing_face))
		10: # Remove selected face uv
			_editing_multiple = true
			var voxel := get_viewing_voxel()
			undo_redo.create_action("VoxelViewer : Remove side uvs")
			for selection in _selections:
				undo_redo.add_do_method(Voxel, "remove_face_uv", voxel, selection)
				undo_redo.add_undo_method(Voxel, "set_face_uv", voxel, selection, Voxel.get_face_uv(voxel, selection))
			undo_redo.add_do_method(voxel_set, "request_refresh")
			undo_redo.add_undo_method(voxel_set, "request_refresh")
			undo_redo.commit_action()
		4: # Set voxel color
			show_color_menu(Voxel.get_color(get_viewing_voxel()))
		5: # Set voxel uv
			show_texture_menu(Voxel.get_uv(get_viewing_voxel()))
		6: # Remove voxel uv
			var voxel = voxel_set.get_voxel(voxel_id)
			undo_redo.create_action("VoxelViewer : Remove uv")
			undo_redo.add_do_method(Voxel, "remove_uv", voxel)
			undo_redo.add_undo_method(Voxel, "set_uv", voxel, Voxel.get_uv(voxel))
			undo_redo.add_do_method(voxel_set, "request_refresh")
			undo_redo.add_undo_method(voxel_set, "request_refresh")
			undo_redo.commit_action()
		13: # Select all
			unselect_all()
			for face in Voxel.Faces:
				select(face)
		11: # Unselect all
			unselect_all()
		12: # Modify material
			show_material_menu()


func _on_ColorPicker_color_changed(color : Color):
	match _editing_action:
		0, 7:
			for selection in (_selections if _editing_multiple else [_editing_face]):
				Voxel.set_face_color(get_viewing_voxel(), selection, color)
		4: Voxel.set_color(get_viewing_voxel(), color)
	update_view()


func _on_ColorMenu_Cancel_pressed():
	voxel_set.set_voxel(_unedited_voxel, voxel_id)
	
	close_color_menu()


func _on_ColorMenu_Confirm_pressed():
	match _editing_action:
		0, 7:
			var voxel = get_viewing_voxel()
			undo_redo.create_action("VoxelViewer : Set side color(s)")
			for selection in (_selections if _editing_multiple else [_editing_face]):
				var color = Voxel.get_face_color(voxel, selection)
				undo_redo.add_do_method(Voxel, "set_face_color", voxel, selection, Voxel.get_face_color(get_viewing_voxel(), selection))
				if color == Color.transparent:
					undo_redo.add_undo_method(Voxel, "remove_face_color", voxel, selection)
				else:
					undo_redo.add_undo_method(Voxel, "set_face_color", voxel, selection, color)
			undo_redo.add_do_method(voxel_set, "request_refresh")
			undo_redo.add_undo_method(voxel_set, "request_refresh")
			undo_redo.commit_action()
		4:
			var voxel = get_viewing_voxel()
			var color = Voxel.get_color(voxel)
			undo_redo.create_action("VoxelViewer : Set color")
			undo_redo.add_do_method(Voxel, "set_color", voxel, Voxel.get_color(get_viewing_voxel()))
			if color.a == 0:
				undo_redo.add_undo_method(Voxel, "remove_color", voxel)
			else:
				undo_redo.add_undo_method(Voxel, "set_color", voxel, color)
			undo_redo.add_do_method(voxel_set, "request_refresh")
			undo_redo.add_undo_method(voxel_set, "request_refresh")
			undo_redo.commit_action()
	close_color_menu()


func _on_VoxelTexture_selected_uv(uv : Vector2):
	match _editing_action:
		2, 9: 
			for selection in (_selections if _editing_multiple else [_editing_face]):
				Voxel.set_face_uv(get_viewing_voxel(), selection, uv)
		5: Voxel.set_uv(get_viewing_voxel(), uv)
	update_view()


func _on_TextureMenu_Cancel_pressed():
	voxel_set.set_voxel(_unedited_voxel, voxel_id)
	
	close_texture_menu()


func _on_TextureMenu_Confirm_pressed():
	match _editing_action:
		2, 9:
			var voxel = get_viewing_voxel()
			undo_redo.create_action("VoxelViewer : Set side uv(s)")
			for selection in (_selections if _editing_multiple else [_editing_face]):
				var uv = Voxel.get_face_uv(voxel, selection)
				undo_redo.add_do_method(Voxel, "set_face_uv", voxel, selection, Voxel.get_face_uv(voxel, selection))
				if uv == -Vector2.ONE:
					undo_redo.add_undo_method(Voxel, "remove_face_uv", voxel, selection)
				else:
					undo_redo.add_undo_method(Voxel, "set_face_uv", voxel, selection, uv)
			undo_redo.add_do_method(voxel_set, "request_refresh")
			undo_redo.add_undo_method(voxel_set, "request_refresh")
			undo_redo.commit_action()
		5:
			var voxel = get_viewing_voxel()
			var uv = Voxel.get_uv(voxel)
			undo_redo.create_action("VoxelViewer : Set uv")
			undo_redo.add_do_method(Voxel, "set_uv", voxel, Voxel.get_uv(voxel))
			if uv == -Vector2.ONE:
				undo_redo.add_undo_method(Voxel, "remove_uv", voxel)
			else:
				undo_redo.add_undo_method(Voxel, "set_uv", voxel, uv)
			undo_redo.add_do_method(voxel_set, "request_refresh")
			undo_redo.add_undo_method(voxel_set, "request_refresh")
			undo_redo.commit_action()
	close_texture_menu()


func _on_Metallic_value_changed(metallic : float):
	Voxel.set_metallic(get_viewing_voxel(), metallic)
	update_view()


func _on_Specular_value_changed(specular : float):
	Voxel.set_specular(get_viewing_voxel(), specular)
	update_view()


func _on_Roughness_value_changed(roughness : float):
	Voxel.set_roughness(get_viewing_voxel(), roughness)
	update_view()


func _on_Energy_value_changed(emergy : float):
	Voxel.set_energy(get_viewing_voxel(), emergy)
	update_view()


func _on_EnergyColor_changed(color : Color):
	Voxel.set_energy_color(get_viewing_voxel(), color)
	update_view()


func _on_MaterialMenu_Cancel_pressed():
	voxel_set.set_voxel(_unedited_voxel, voxel_id)
	
	close_material_menu()


func _on_MaterialMenu_Confirm_pressed():
	var voxel = get_viewing_voxel()
	undo_redo.create_action("VoxelViewer : Set voxel material")
	var metallic := Voxel.get_metallic(voxel)
	var _metallic := Voxel.get_metallic(_unedited_voxel)
	if metallic != _metallic:
		undo_redo.add_do_method(Voxel, "set_metallic", voxel, metallic)
		undo_redo.add_undo_method(Voxel, "set_metallic", voxel, _metallic)
	var specular := Voxel.get_specular(voxel)
	var _specular := Voxel.get_specular(_unedited_voxel)
	if specular != specular:
		undo_redo.add_do_method(Voxel, "set_specular", voxel, specular)
		undo_redo.add_undo_method(Voxel, "set_specular", voxel, _specular)
	var roughness := Voxel.get_roughness(voxel)
	var _roughness := Voxel.get_roughness(_unedited_voxel)
	if roughness != _roughness:
		undo_redo.add_do_method(Voxel, "set_roughness", voxel, roughness)
		undo_redo.add_undo_method(Voxel, "set_roughness", voxel, _roughness)
	var energy := Voxel.get_energy(voxel)
	var _energy := Voxel.get_energy(_unedited_voxel)
	if energy != _energy:
		undo_redo.add_do_method(Voxel, "set_energy", voxel, energy)
		undo_redo.add_undo_method(Voxel, "set_energy", voxel, _energy)
	var energy_color := Voxel.get_energy_color(voxel)
	var _energy_color := Voxel.get_energy_color(_unedited_voxel)
	if energy_color != _energy_color:
		undo_redo.add_do_method(Voxel, "set_energy_color", voxel, energy_color)
		undo_redo.add_undo_method(Voxel, "set_energy_color", voxel, _energy_color)
	undo_redo.add_do_method(voxel_set, "request_refresh")
	undo_redo.add_undo_method(voxel_set, "request_refresh")
	undo_redo.commit_action()
	
	close_material_menu()
