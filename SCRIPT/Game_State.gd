extends Node

# Emesso quando cambia il player che sta scegliendo il personaggio
signal selection_changed

# Emesso quando entrambi i player hanno scelto il personaggio
signal selection_finished

const PLAYER_COUNT: int = 2

# --- Impostazioni di gioco salvate su disco ---
const SETTINGS_PATH: String = "user://settings.cfg"
var master_volume: float = 1.0  # 0.0 - 1.0
var fullscreen: bool = false
var window_resolution: Vector2i = Vector2i(1280, 720)
var visual_effects: bool = true
var gore_enabled: bool = true
const DEFAULT_KEY_BINDINGS := {
	"p1_left": KEY_A, "p1_right": KEY_D, "p1_down": KEY_S,
	"p1_jump": KEY_SPACE, "p1_run": KEY_SHIFT, "p1_attack": KEY_J,
	"p1_secondary": KEY_K, "p1_reload": KEY_E,
	"p2_left": KEY_LEFT, "p2_right": KEY_RIGHT, "p2_down": KEY_DOWN,
	"p2_jump": KEY_UP, "p2_run": KEY_KP_0, "p2_attack": KEY_KP_1,
	"p2_secondary": KEY_KP_2, "p2_reload": KEY_KP_ENTER,
}
var key_bindings: Dictionary = DEFAULT_KEY_BINDINGS.duplicate()


func _ready() -> void:
	_load_settings()
	_apply_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		master_volume = cfg.get_value("audio", "master_volume", 1.0)
		fullscreen = cfg.get_value("display", "fullscreen", false)
		window_resolution = Vector2i(
			int(cfg.get_value("display", "window_width", 1280)),
			int(cfg.get_value("display", "window_height", 720))
		)
		visual_effects = cfg.get_value("graphics", "visual_effects", true)
		gore_enabled = cfg.get_value("graphics", "gore_enabled", true)
		for action in DEFAULT_KEY_BINDINGS:
			key_bindings[action] = int(cfg.get_value("controls", action, DEFAULT_KEY_BINDINGS[action]))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "window_width", window_resolution.x)
	cfg.set_value("display", "window_height", window_resolution.y)
	cfg.set_value("graphics", "visual_effects", visual_effects)
	cfg.set_value("graphics", "gore_enabled", gore_enabled)
	for action in key_bindings:
		cfg.set_value("controls", action, key_bindings[action])
	cfg.save(SETTINGS_PATH)


func _apply_settings() -> void:
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index != -1:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(clampf(master_volume, 0.0, 1.0)))
	if not Engine.is_embedded_in_editor():
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		)
		if not fullscreen:
			DisplayServer.window_set_size(window_resolution)
	_apply_key_bindings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index != -1:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(master_volume))
	save_settings()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	if not Engine.is_embedded_in_editor():
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		)
		if not fullscreen:
			DisplayServer.window_set_size(window_resolution)
	save_settings()


func set_window_resolution(value: Vector2i) -> void:
	window_resolution = value
	if not fullscreen and not Engine.is_embedded_in_editor():
		DisplayServer.window_set_size(window_resolution)
	save_settings()


func set_visual_effects(value: bool) -> void:
	visual_effects = value
	save_settings()


func set_gore_enabled(value: bool) -> void:
	gore_enabled = value
	save_settings()


func set_key_binding(action: String, physical_keycode: int) -> bool:
	if not DEFAULT_KEY_BINDINGS.has(action) or physical_keycode <= 0:
		return false
	for other_action in key_bindings:
		if other_action != action and int(key_bindings[other_action]) == physical_keycode:
			return false
	key_bindings[action] = physical_keycode
	_apply_key_bindings()
	save_settings()
	return true


func reset_key_bindings() -> void:
	key_bindings = DEFAULT_KEY_BINDINGS.duplicate()
	_apply_key_bindings()
	save_settings()


func key_name(action: String) -> String:
	var event := InputEventKey.new()
	event.physical_keycode = int(key_bindings.get(action, DEFAULT_KEY_BINDINGS.get(action, KEY_NONE)))
	return event.as_text_physical_keycode()


func _apply_key_bindings() -> void:
	for action in key_bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event := InputEventKey.new()
		event.physical_keycode = int(key_bindings[action])
		InputMap.action_add_event(action, event)

# Configurazione multiplayer: una entry per player, letta da player.gd tramite player_id
# device_id: -1 = tastiera P1, -2 = tastiera P2, >=0 = indice pad
var player_configs: Array = [
	{"skin": 0, "device_id": -1, "is_bot": false},  # player 1: default trab, tastiera schema 1
	{"skin": 1, "device_id": -2, "is_bot": false},  # player 2: default iacopo, tastiera schema 2
]

var bot_enabled: bool = false
var bot_player_uses_pad: bool = false

# Mantenuta solo come fallback in player.gd (non viene più scritta dai pulsanti)
var selected_skin: int = 0

# Quale player sta scegliendo adesso nella schermata di selezione (0 = P1, 1 = P2)
var selecting_player: int = 0

# --- Punteggio della partita (al meglio di 3 round) ---
const ROUNDS_TO_WIN: int = 2
var round_wins: Array = [0, 0]


# Azzera il punteggio: da chiamare a inizio partita
func reset_match() -> void:
	round_wins = [0, 0]


# Registra la vittoria di un round per player_id. Ritorna true se con
# questo round il player ha vinto la partita (2 round su 3).
func register_round_win(player_id: int) -> bool:
	round_wins[player_id] += 1
	return round_wins[player_id] >= ROUNDS_TO_WIN


func get_skin_for(player_id: int) -> int:
	if player_id < player_configs.size():
		return player_configs[player_id]["skin"]
	return 0


func get_device_for(player_id: int) -> int:
	if player_id < player_configs.size():
		return player_configs[player_id]["device_id"]
	return -1


func is_bot_for(player_id: int) -> bool:
	return player_id < player_configs.size() and bool(player_configs[player_id].get("is_bot", false))


func set_player_config(player_id: int, skin: int, device_id: int, is_bot: bool = false) -> void:
	while player_configs.size() <= player_id:
		player_configs.append({"skin": 0, "device_id": -1, "is_bot": false})
	player_configs[player_id] = {"skin": skin, "device_id": device_id, "is_bot": is_bot}


# Da chiamare quando si entra nella schermata di selezione
func start_selection() -> void:
	reset_match()
	for i in range(player_configs.size()):
		player_configs[i]["is_bot"] = false
	selecting_player = 0
	selection_changed.emit()


# Chiamata dai pulsanti: assegna la skin al player di turno, poi passa al successivo
func choose_skin(skin: int) -> void:
	set_player_config(selecting_player, skin, get_device_for(selecting_player))
	if bot_enabled and selecting_player == 0:
		var available_skins: Array[int] = [0, 1, 2, 3, 4, 5]
		available_skins.erase(skin)
		var bot_skin: int = available_skins.pick_random()
		set_player_config(1, bot_skin, -2, true)
		selecting_player = PLAYER_COUNT
		selection_finished.emit()
		return
	selecting_player += 1
	if selecting_player >= PLAYER_COUNT:
		selection_finished.emit()
	else:
		selection_changed.emit()
