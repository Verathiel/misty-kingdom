extends Node2D

const MAP_TEXTURE: Texture2D = preload("res://assets/canyon_map.png")
const SAVE_PATH := "user://misty_kingdom_canyon_buildings.json"
const MAP_SIZE := Vector2(1536.0, 1024.0)
const MIN_ZOOM := 0.65
const MAX_ZOOM := 2.8
const ZOOM_STEP := 1.18

var selected_building := "house"
var buildings: Array[Dictionary] = []
var status_label: Label
var selected_buttons: Dictionary = {}
var ui_panel: PanelContainer
var menu_toggle: Button
var zoom_label: Label

# Camera transform. zoom_level is relative to the viewport-fit scale.
var zoom_level: float = 1.0
var camera_offset := Vector2.ZERO
var mouse_pan_active := false
var last_mouse_position := Vector2.ZERO
var touch_positions: Dictionary = {}
var touch_moved: Dictionary = {}
var pinch_active := false
var pinch_distance: float = 0.0

# Broad buildable plateau, intentionally expanded to give the player much more room.
var build_area := PackedVector2Array([
	Vector2(500, 105), Vector2(760, 72), Vector2(980, 105),
	Vector2(1160, 210), Vector2(1260, 340), Vector2(1300, 475),
	Vector2(1250, 605), Vector2(1160, 735), Vector2(1015, 835),
	Vector2(820, 900), Vector2(635, 835), Vector2(500, 740),
	Vector2(420, 620), Vector2(400, 480), Vector2(425, 340),
	Vector2(450, 220)
])

func _ready() -> void:
	_build_ui()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_center_map()
	_update_ui_layout()
	queue_redraw()

func _on_viewport_resized() -> void:
	_center_map()
	_update_ui_layout()
	queue_redraw()

func _fit_scale() -> float:
	var view_size: Vector2 = get_viewport_rect().size
	return minf(view_size.x / MAP_SIZE.x, view_size.y / MAP_SIZE.y) * 0.96

func _effective_scale() -> float:
	return _fit_scale() * zoom_level

func _center_map() -> void:
	var view_size: Vector2 = get_viewport_rect().size
	var fit := _fit_scale()
	camera_offset = (view_size - MAP_SIZE * fit) * 0.5

func _screen_to_map(screen_pos: Vector2) -> Vector2:
	return (screen_pos - camera_offset) / _effective_scale()

func _draw() -> void:
	draw_set_transform(camera_offset, 0.0, Vector2.ONE * _effective_scale())
	draw_texture_rect(MAP_TEXTURE, Rect2(Vector2.ZERO, MAP_SIZE), false)

	# Only a subtle boundary; no grid is drawn over the artwork.
	if selected_building != "":
		for i in range(build_area.size()):
			draw_line(
				build_area[i], build_area[(i + 1) % build_area.size()],
				Color(0.98, 0.86, 0.54, 0.38), 2.0, true
			)

	for item in buildings:
		_draw_building(Vector2(float(item["x"]), float(item["y"])), str(item["type"]))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	menu_toggle = Button.new()
	menu_toggle.text = "☰ Stavění"
	menu_toggle.position = Vector2(14, 14)
	menu_toggle.custom_minimum_size = Vector2(118, 42)
	menu_toggle.pressed.connect(_toggle_menu)
	layer.add_child(menu_toggle)

	ui_panel = PanelContainer.new()
	ui_panel.position = Vector2(18, 18)
	ui_panel.custom_minimum_size = Vector2(320, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.11, 0.09, 0.94)
	style.border_color = Color("c6a66b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	ui_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(ui_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	ui_panel.add_child(col)

	var title := Label.new()
	title.text = "MISTY KINGDOM · KAŇON A MOSTY"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("f6e8c8"))
	col.add_child(title)

	var desc := Label.new()
	desc.text = "Tvoř volně na velké horské plošině"
	desc.add_theme_color_override("font_color", Color("d8d9bd"))
	col.add_child(desc)
	col.add_child(HSeparator.new())

	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 5)
	row.add_theme_constant_override("v_separation", 5)
	col.add_child(row)
	_add_build_button(row, "Dům", "house")
	_add_build_button(row, "Věž", "tower")
	_add_build_button(row, "Radnice", "hall")
	_add_build_button(row, "Zahrada", "garden")
	_add_build_button(row, "Smazat", "erase")

	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 5)
	col.add_child(zoom_row)
	var zoom_out := Button.new()
	zoom_out.text = "−"
	zoom_out.custom_minimum_size = Vector2(44, 36)
	zoom_out.pressed.connect(_zoom_out)
	zoom_row.add_child(zoom_out)
	var zoom_in := Button.new()
	zoom_in.text = "+"
	zoom_in.custom_minimum_size = Vector2(44, 36)
	zoom_in.pressed.connect(_zoom_in)
	zoom_row.add_child(zoom_in)
	var reset_view := Button.new()
	reset_view.text = "Vycentrovat mapu"
	reset_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_view.pressed.connect(_reset_view)
	zoom_row.add_child(reset_view)
	zoom_label = Label.new()
	zoom_label.text = "100 %"
	zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	zoom_row.add_child(zoom_label)

	var actions := HBoxContainer.new()
	col.add_child(actions)
	var save := Button.new()
	save.text = "Uložit"
	save.pressed.connect(_save_game)
	actions.add_child(save)
	var load := Button.new()
	load.text = "Načíst"
	load.pressed.connect(_load_game)
	actions.add_child(load)
	var clear := Button.new()
	clear.text = "Vyčistit stavby"
	clear.pressed.connect(_clear_buildings)
	col.add_child(clear)

	var help := Label.new()
	help.text = "PC: kolečko = zoom, pravé tlačítko = posun. Mobil: dva prsty = zoom, tažení = posun, klepnutí = stavba."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color("f0dfb5"))
	col.add_child(help)

	status_label = Label.new()
	status_label.text = "Vybráno: Dům"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color("c7e6a1"))
	col.add_child(status_label)

func _update_ui_layout() -> void:
	if not is_instance_valid(ui_panel) or not is_instance_valid(menu_toggle):
		return
	var width := get_viewport_rect().size.x
	if width < 760.0:
		ui_panel.position = Vector2(12, 62)
		ui_panel.custom_minimum_size = Vector2(minf(width - 24.0, 330.0), 0)
		ui_panel.scale = Vector2.ONE * 0.88
		menu_toggle.visible = true
		ui_panel.visible = false
	else:
		ui_panel.position = Vector2(18, 18)
		ui_panel.custom_minimum_size = Vector2(320, 0)
		ui_panel.scale = Vector2.ONE
		menu_toggle.visible = false
		ui_panel.visible = true

func _toggle_menu() -> void:
	ui_panel.visible = not ui_panel.visible

func _add_build_button(parent: HFlowContainer, label_text: String, id: String) -> void:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(88, 36)
	button.pressed.connect(_select_building.bind(id))
	parent.add_child(button)
	selected_buttons[id] = button
	if id == selected_building:
		button.modulate = Color("c7e6a1")

func _select_building(id: String) -> void:
	selected_building = id
	for key_name in selected_buttons:
		selected_buttons[key_name].modulate = Color.WHITE
	if selected_buttons.has(id):
		selected_buttons[id].modulate = Color("c7e6a1")
	if is_instance_valid(status_label):
		status_label.text = "Vybráno: " + id

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(ZOOM_STEP, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(1.0 / ZOOM_STEP, event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			mouse_pan_active = event.pressed
			last_mouse_position = event.position
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_place(_screen_to_map(event.position))

	elif event is InputEventMouseMotion and mouse_pan_active:
		camera_offset += event.relative
		last_mouse_position = event.position
		queue_redraw()

	elif event is InputEventScreenTouch:
		if event.pressed:
			touch_positions[event.index] = event.position
			touch_moved[event.index] = false
			if touch_positions.size() >= 2:
				pinch_active = true
				var positions: Array = touch_positions.values()
				pinch_distance = Vector2(positions[0]).distance_to(Vector2(positions[1]))
				for touch_id in touch_moved:
					touch_moved[touch_id] = true
		else:
			var was_moved: bool = bool(touch_moved.get(event.index, false))
			var was_pinching := pinch_active
			if not was_moved and not was_pinching:
				_handle_place(_screen_to_map(event.position))
			touch_positions.erase(event.index)
			touch_moved.erase(event.index)
			if touch_positions.size() < 2:
				pinch_active = false
				pinch_distance = 0.0

	elif event is InputEventScreenDrag:
		if touch_positions.has(event.index):
			touch_positions[event.index] = event.position
			touch_moved[event.index] = true
		if touch_positions.size() >= 2:
			var positions: Array = touch_positions.values()
			var new_distance := Vector2(positions[0]).distance_to(Vector2(positions[1]))
			var midpoint := (Vector2(positions[0]) + Vector2(positions[1])) * 0.5
			if pinch_distance > 1.0 and new_distance > 1.0:
				_zoom_at(new_distance / pinch_distance, midpoint)
			pinch_distance = new_distance
			pinch_active = true
		else:
			camera_offset += event.screen_relative
			queue_redraw()

func _handle_place(p: Vector2) -> void:
	if not Geometry2D.is_point_in_polygon(p, build_area):
		if is_instance_valid(status_label):
			status_label.text = "Klikni na otevřenou travnatou plošinu."
		return

	if selected_building == "erase":
		_remove_nearest(p)
	else:
		buildings.append({"x": p.x, "y": p.y, "type": selected_building})
		status_label.text = "Postaveno: " + selected_building
	queue_redraw()

func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	var old_scale := _effective_scale()
	var map_anchor := (screen_pos - camera_offset) / old_scale
	zoom_level = clampf(zoom_level * factor, MIN_ZOOM, MAX_ZOOM)
	var new_scale := _effective_scale()
	camera_offset = screen_pos - map_anchor * new_scale
	if is_instance_valid(zoom_label):
		zoom_label.text = "%d %%" % roundi(zoom_level * 100.0)
	queue_redraw()

func _zoom_in() -> void:
	_zoom_at(ZOOM_STEP, get_viewport_rect().size * 0.5)

func _zoom_out() -> void:
	_zoom_at(1.0 / ZOOM_STEP, get_viewport_rect().size * 0.5)

func _reset_view() -> void:
	zoom_level = 1.0
	_center_map()
	if is_instance_valid(zoom_label):
		zoom_label.text = "100 %"
	queue_redraw()

func _remove_nearest(p: Vector2) -> void:
	var best_index := -1
	var best_distance := 55.0
	for i in range(buildings.size()):
		var b := buildings[i]
		var distance := p.distance_to(Vector2(float(b["x"]), float(b["y"])))
		if distance < best_distance:
			best_distance = distance
			best_index = i
	if best_index >= 0:
		buildings.remove_at(best_index)
		status_label.text = "Stavba odstraněna."
	else:
		status_label.text = "V blízkosti není stavba k odstranění."

func _draw_building(p: Vector2, kind: String) -> void:
	_draw_ellipse_shadow(p + Vector2(0, 7), Vector2(25, 10), Color(0.08, 0.10, 0.07, 0.55))
	match kind:
		"house":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-18, -1), p + Vector2(0, -12), p + Vector2(18, -1), p + Vector2(0, 8)]), Color("b7a17c"))
			draw_colored_polygon(PackedVector2Array([p + Vector2(-15, -3), p + Vector2(-13, -17), p + Vector2(0, -25), p + Vector2(14, -16), p + Vector2(15, -3), p + Vector2(0, 5)]), Color("dbc69b"))
			draw_colored_polygon(PackedVector2Array([p + Vector2(-16, -17), p + Vector2(0, -32), p + Vector2(17, -17), p + Vector2(0, -10)]), Color("784d38"))
			draw_rect(Rect2(p + Vector2(-3, -12), Vector2(6, 12)), Color("5a4633"))
		"tower":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-13, 2), p + Vector2(-10, -28), p + Vector2(10, -28), p + Vector2(13, 2)]), Color("b7ad96"))
			draw_colored_polygon(PackedVector2Array([p + Vector2(-15, -28), p + Vector2(0, -39), p + Vector2(15, -28)]), Color("6f5540"))
			draw_rect(Rect2(p + Vector2(-3, -18), Vector2(6, 8)), Color("4b4b3b"))
		"hall":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-25, 0), p + Vector2(-22, -22), p + Vector2(15, -22), p + Vector2(22, 0)]), Color("c6b18c"))
			draw_colored_polygon(PackedVector2Array([p + Vector2(-26, -22), p + Vector2(-3, -36), p + Vector2(19, -22)]), Color("80513b"))
			draw_rect(Rect2(p + Vector2(-4, -15), Vector2(8, 15)), Color("594735"))
		"garden":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-22, 0), p + Vector2(0, -11), p + Vector2(22, 0), p + Vector2(0, 11)]), Color("6f8747"))
			for i in range(5):
				draw_circle(p + Vector2(-12 + i * 6, -2 + (i % 2) * 3), 3.0, Color("d6b66b"))

func _draw_ellipse_shadow(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(20):
		var a := TAU * float(i) / 20.0
		points.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(points, color)

func _save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		status_label.text = "Uložení se nezdařilo."
		return
	file.store_string(JSON.stringify(buildings))
	file.close()
	status_label.text = "Rozestavěná osada uložena."

func _load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		status_label.text = "Zatím nemáš uloženou osadu."
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		status_label.text = "Uložený soubor nelze otevřít."
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array:
		buildings.clear()
		for item in parsed:
			if item is Dictionary:
				buildings.append(item)
		queue_redraw()
		status_label.text = "Osada načtena."
	else:
		status_label.text = "Uložená data nejsou platná."

func _clear_buildings() -> void:
	buildings.clear()
	queue_redraw()
	status_label.text = "Stavby odstraněny."
