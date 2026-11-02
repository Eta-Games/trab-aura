extends CanvasLayer

var _overlay: Control
var _resume_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_menu()


func open_menu() -> void:
	_overlay.visible = true
	get_tree().paused = true
	_resume_button.grab_focus()


func resume_game() -> void:
	_overlay.visible = false
	get_tree().paused = false


func _input(event: InputEvent) -> void:
	if _overlay.visible and _is_pause_event(event):
		resume_game()
		get_viewport().set_input_as_handled()


func _is_pause_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	if event is InputEventJoypadButton:
		return event.pressed and event.button_index == JOY_BUTTON_START
	return false


func _build_menu() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.02, 0.03, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(shade)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500.0, 410.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.055, 0.065, 0.085, 0.98)
	panel_style.border_color = Color(0.949, 0.784, 0.184, 1.0)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 46)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_right", 46)
	margin.add_theme_constant_override("margin_bottom", 34)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	margin.add_child(stack)

	var title := Label.new()
	title.text = "PAUSA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _menu_font())
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.949, 0.784, 0.184, 1.0))
	stack.add_child(title)

	var hint := Label.new()
	hint.text = "Esc / Start per riprendere"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_override("font", _menu_font())
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(0.78, 0.8, 0.83, 1.0))
	stack.add_child(hint)

	_resume_button = _make_button("Riprendi", resume_game)
	stack.add_child(_resume_button)
	stack.add_child(_make_button("Torna al menu", _return_to_menu))
	stack.add_child(_make_button("Esci dal gioco", _quit_game))


func _make_button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(400.0, 58.0)
	button.add_theme_font_override("font", _menu_font())
	button.add_theme_font_size_override("font_size", 26)
	button.pressed.connect(action)
	return button


func _menu_font() -> Font:
	return load("res://font/kreaturekombatcond.ttf") as Font


func _return_to_menu() -> void:
	get_tree().paused = false
	Network.stop()
	get_tree().change_scene_to_file("res://ui_unificata.tscn")


func _quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()
