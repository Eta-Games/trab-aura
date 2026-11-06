extends "res://SCRIPT/powers/fighter_power.gd"

var _active := false


func default_params() -> Dictionary:
	return {
		"cooldown": 5.0,
		"stamina_min": 200.0,
		"stamina_cost": 200.0,
		"charge_time": 1.0,
		"plane_texture": "res://sprite/Player/IlMencu/Secondary/plane_nobg.png",
		"bomb_texture": "res://sprite/Player/IlMencu/Secondary/bomb_nobg.png",
		"camera_pan_offset": Vector2(0.0, -200.0),
		"camera_pan_time": 1.0,
		"plane_scale": 0.7,
		"bomb_scale": 0.16,
		"plane_flight_time": 2.0,
		"bomb_fall_speed": 650.0,
		"white_hold_time": 1.5,
		"fade_time": 1.0,
	}


func has_charged_attack() -> bool:
	return true


func charge_time() -> float:
	return float(params["charge_time"])


func use() -> void:
	# Un tocco breve non attiva il bombardamento: serve la carica completa.
	pass


func is_busy() -> bool:
	return _active


func release_charge() -> void:
	if _active or not _has_stamina(float(params["stamina_cost"])):
		return
	_active = true
	_spend_stamina(float(params["stamina_cost"]))
	cooldown_left = float(params["cooldown"])
	_run_airstrike()


func _run_airstrike() -> void:
	var scene: Node = player.get_tree().current_scene
	if scene == null:
		_active = false
		return
	var opponent: Player = null
	for candidate: Node in player.get_tree().get_nodes_in_group("players"):
		if candidate is Player and candidate != player and candidate.current_health > 0:
			opponent = candidate
			break
	if opponent == null:
		_active = false
		return

	var camera: Camera2D = player.get_viewport().get_camera_2d()
	var original_offset := Vector2.ZERO
	var camera_was_processing := false
	if camera != null:
		original_offset = camera.offset
		camera_was_processing = camera.is_processing()
		camera.set_cinematic_focus(player, camera.zoom.x, Vector2(params["camera_pan_offset"]))

	var saved_locks: Dictionary = {}
	for fighter: Player in [player, opponent]:
		saved_locks[fighter] = fighter.combat_locked
		fighter.combat_locked = true

	var plane_tex: Texture2D = load(str(params["plane_texture"])) as Texture2D
	var bomb_tex: Texture2D = load(str(params["bomb_texture"])) as Texture2D
	if plane_tex == null or bomb_tex == null:
		push_warning("Mencu airstrike: immagine aereo o bomba non trovata")
		_finish(scene, camera, original_offset, camera_was_processing, saved_locks, null)
		return

	var plane: Sprite2D = Sprite2D.new()
	plane.texture = plane_tex
	plane.scale = Vector2.ONE * float(params["plane_scale"])
	scene.add_child(plane)
	var viewport_size: Vector2 = player.get_viewport().get_visible_rect().size
	var screen_width_world: float = viewport_size.x / maxf(camera.zoom.x if camera != null else 1.0, 0.1)
	var screen_height_world: float = viewport_size.y / maxf(camera.zoom.y if camera != null else 1.0, 0.1)
	var cam_pos: Vector2 = camera.global_position if camera != null else player.global_position
	var flight_y: float = cam_pos.y - screen_height_world * 0.28
	plane.global_position = Vector2(cam_pos.x - screen_width_world * 0.65, flight_y)
	if camera != null:
		# The cinematic focus is smoothed by camera_2d.gd; hold while it pans.
		await player.get_tree().create_timer(float(params["camera_pan_time"])).timeout
		cam_pos = camera.global_position
		flight_y = cam_pos.y - screen_height_world * 0.28
		plane.global_position.y = flight_y

	var bomb: Sprite2D = Sprite2D.new()
	bomb.texture = bomb_tex
	bomb.scale = Vector2.ONE * float(params["bomb_scale"])
	bomb.rotation_degrees = 90.0
	scene.add_child(bomb)
	bomb.visible = false
	var flight: Tween = player.get_tree().create_tween()
	flight.tween_property(plane, "global_position:x", cam_pos.x, float(params["plane_flight_time"]) * 0.5)
	await flight.finished
	bomb.global_position = plane.global_position + Vector2(0.0, plane_tex.get_height() * 0.2 * plane.scale.y)
	bomb.visible = true
	if camera != null:
		camera.set_cinematic_focus(bomb, camera.zoom.x, Vector2.ZERO)
	var remaining_flight: Tween = player.get_tree().create_tween()
	remaining_flight.tween_property(plane, "global_position:x", cam_pos.x + screen_width_world * 0.75, float(params["plane_flight_time"]) * 0.5)
	var ground_y: float = player.global_position.y
	var fall_distance: float = maxf(ground_y - bomb.global_position.y, 0.0)
	var fall: Tween = player.get_tree().create_tween()
	fall.tween_property(bomb, "global_position:y", ground_y, fall_distance / maxf(float(params["bomb_fall_speed"]), 1.0))
	await fall.finished
	remaining_flight.kill()
	plane.queue_free()

	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 40
	scene.add_child(layer)
	var white: ColorRect = ColorRect.new()
	white.color = Color.WHITE
	white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(white)

	var music: AudioStreamPlayer = scene.get_node_or_null("AudioStreamPlayer") as AudioStreamPlayer
	if music != null:
		music.stop()
	opponent.current_health = 1
	opponent.health_changed.emit()
	await player.get_tree().create_timer(float(params["white_hold_time"])).timeout
	var fade: Tween = player.get_tree().create_tween()
	fade.tween_property(white, "color:a", 0.0, float(params["fade_time"]))
	await fade.finished
	_finish(scene, camera, original_offset, camera_was_processing, saved_locks, layer)
	if is_instance_valid(bomb):
		bomb.queue_free()


func _finish(_scene: Node, camera: Camera2D, original_offset: Vector2, camera_was_processing: bool, saved_locks: Dictionary, overlay: Node) -> void:
	if camera != null:
		camera.clear_cinematic_focus()
		camera.offset = original_offset
		camera.set_process(camera_was_processing)
	for fighter: Player in saved_locks.keys():
		if is_instance_valid(fighter):
			fighter.combat_locked = saved_locks[fighter]
	if is_instance_valid(overlay):
		overlay.queue_free()
	_active = false
