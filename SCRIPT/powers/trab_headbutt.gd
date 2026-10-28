extends "res://SCRIPT/powers/fighter_power.gd"

const ANIMATION_NAME := &"secondary_headbutt"
const BALL_SCRIPT := preload("res://SCRIPT/powers/soccer_ball.gd")

var _busy_left := 0.0
var _windup_left := 0.0
var _pending_target: Player


func default_params() -> Dictionary:
	return {
		"cooldown": 5.0,
		"stamina_min": 65.0,
		"stamina_cost": 65.0,
		"damage": 35,
		"animation_fps": 15.0,
		"ball_speed": 1050.0,
		"ball_size": 18.0,
		"ball_spawn_offset": Vector2(48, -45),
	}


func _on_setup() -> void:
	var frames: SpriteFrames = player.current_sprite.sprite_frames
	if frames == null or frames.has_animation(ANIMATION_NAME):
		return
	var sheet: Texture2D = load("res://sprite/Player/WND_trab/testata/mr aura-hurt.png")
	if sheet == null:
		push_warning("Trab: foglio mr aura-hurt non trovato")
		return
	frames.add_animation(ANIMATION_NAME)
	frames.set_animation_loop(ANIMATION_NAME, false)
	frames.set_animation_speed(ANIMATION_NAME, float(params["animation_fps"]))
	# Il foglio contiene 25 fotogrammi da 256x256; la mossa usa il fotogramma 15.
	for index in range(25):
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2((index % 5) * 256, (index / 5) * 256, 256, 256)
		frames.add_frame(ANIMATION_NAME, atlas)


func can_use() -> bool:
	return player.fighter_name.to_lower() == "trab" and super.can_use()


func is_busy() -> bool:
	return _busy_left > 0.0


func use() -> void:
	var target := _find_opponent()
	if target == null:
		return
	super.use()
	_pending_target = target
	var fps := maxf(float(params["animation_fps"]), 1.0)
	_busy_left = 1.7
	# Emesso il pallone quando lo sprite raggiunge il quindicesimo frame.
	_windup_left = 14.0 / fps
	player.velocity = Vector2.ZERO
	player.is_blocking = false
	player._set_facing(target.global_position.x < player.global_position.x)
	player.current_sprite.play(ANIMATION_NAME)
	player.synced_animation = ANIMATION_NAME


func _update_power(delta: float) -> void:
	_busy_left = maxf(_busy_left - delta, 0.0)
	if _pending_target != null:
		_windup_left -= delta
		if _windup_left <= 0.0:
			_launch_ball()
	if _busy_left == 0.0 and player.current_sprite.animation == ANIMATION_NAME:
		player.current_sprite.play("idle")
		player.synced_animation = "idle"


func _launch_ball() -> void:
	var target := _pending_target
	_pending_target = null
	if not is_instance_valid(target) or target.is_dead or target.current_health <= 0:
		return
	var direction := 1.0 if target.global_position.x >= player.global_position.x else -1.0
	var ball: Node2D = BALL_SCRIPT.new()
	player.get_parent().add_child(ball)
	ball.global_position = player.global_position + Vector2(float(params["ball_spawn_offset"].x) * direction, float(params["ball_spawn_offset"].y))
	ball.setup(direction, float(params["ball_speed"]), float(params["ball_size"]), target, player, int(params["damage"]))


func _find_opponent() -> Player:
	var closest: Player
	var closest_distance := INF
	for node in player.get_parent().get_children():
		if node is Player and node != player and not node.is_dead and node.current_health > 0:
			var distance: float = player.global_position.distance_squared_to(node.global_position)
			if distance < closest_distance:
				closest = node
				closest_distance = distance
	return closest
