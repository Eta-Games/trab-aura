extends Node
# ============================================================
#  FATALITY MANAGER  (autoload - registrato in project.godot)
# ============================================================
#  Come funziona, in breve:
#
#  1) Quando un player sta per andare a 0 HP, invece di morire si
#     ferma a `settings.downed_health` HP (default 1) ed entra in
#     stato "downed" -> player.gd chiama FatalityManager.mark_downed().
#
#  2) Da quel momento, la vittima puo' essere finita in due modi:
#       a) un QUALSIASI altro colpo (se settings.any_hit_finishes)
#          -> player.gd chiama FatalityManager.downed_player_hit()
#          -> e' un K.O. normale: NIENTE camera/slowmo/letterbox/animazione
#             speciale, solo una breve pausa (fallback_freeze_duration) e poi
#             "died" come sempre.
#       b) l'avversario esegue la COMBO specifica del proprio
#          personaggio, letta dalla sezione [fatality] nel suo file
#          .cfg (es. data/fighters/iacopo.cfg):
#
#              [fatality]
#              combo = "down,down,attack,secondary"
#              combo_window = 1.4
#
#          I nomi validi per i passi della combo sono i suffissi delle
#          action di Input Map gia' presenti nel progetto: down, left,
#          right, jump, run, attack (= tasto/pulsante "quadrato"),
#          secondary (= tasto/pulsante "cerchio").
#          -> SOLO questo percorso fa scattare la cinematica completa
#             (slowmo, camera che zooma sulla vittima, letterbox,
#             animazione "<vittima>_<killer>"): e' la vera "fatality",
#             riservata a chi indovina la combo giusta.
#
#  3) Con la combo parte _run_sequence() in modalita' completa: slowmo
#     breve, camera che si sposta/zooma sulla vittima (letterbox nera),
#     viene cercata e riprodotta l'animazione "<vittima>_<killer>" (es.
#     "iacopo_trab" se Trab uccide Iacopo) dentro lo SpriteFrames del
#     personaggio -- basta aggiungerla come una normalissima sezione
#     [anim_iacopo_trab] nel .cfg, esattamente come [anim_idle] ecc.,
#     il caricamento e' automatico (vedi player.gd _build_dynamic_sprite).
#     Se l'animazione non esiste, resta un fermo immagine per
#     settings.fallback_freeze_duration secondi.
#
#  4) A fine cinematica viene ripristinata la camera, sbloccati i
#     player, ed emesso il segnale ORIGINALE `died` sulla vittima —
#     quindi tutta la logica di fine round che avevi gia' (in
#     level.gd o dove lo ascolti) continua a funzionare come prima,
#     semplicemente arriva un po' piu' tardi (dopo la cinematica).
#
#  TUTTI I PARAMETRI regolabili sono in fatality_settings.gd / nella
#  risorsa .tres assegnata a `settings_path` qui sotto.
# ============================================================

const FIGHTERS_DIR := "res://data/fighters/"

## Percorso della risorsa FatalityCombatSettings. Se non esiste, si usano i default.
@export var settings_path: String = "res://data/fatality_settings.tres"

var settings: FatalityCombatSettings

var _fatality_active: bool = false
# player_id (0/1) -> array di {action:String, time:float}
var _input_buffer: Dictionary = {}
# player_id del player "downed" attualmente in attesa del colpo di grazia -> {victim, last_source}
var _downed_players: Dictionary = {}

# elenco delle action da ascoltare per il riconoscimento combo
const _COMBO_SUFFIXES := ["down", "left", "right", "jump", "run", "attack", "secondary"]

var _letterbox: CanvasLayer
var _top_bar: ColorRect
var _bottom_bar: ColorRect

# stato camera nativo salvato durante la cinematica, cosi' _force_recover()
# (watchdog) puo' ripristinarlo anche se _run_sequence si e' inceppato
var _camera_smoothing_was_enabled: bool = true
var _camera_drag_h_was_enabled: bool = false
var _camera_drag_v_was_enabled: bool = false

# vittima della fatality in corso: usata da _force_recover() (watchdog) per
# completare comunque la "morte" (died) se _run_sequence si e' inceppato,
# invece di lasciare tutto a meta' senza che il round finisca mai.
var _current_victim: Player = null
var _fatality_remnants: Dictionary = {} # instance_id vittima -> sprite sostitutivo


func _ready() -> void:
	if ResourceLoader.exists(settings_path):
		settings = ResourceLoader.load(settings_path) as FatalityCombatSettings
	if settings == null:
		settings = FatalityCombatSettings.new()
	print("[Fatality] settings caricati da '%s' (esiste: %s) - camera_zoom_multiplier = %s" % [settings_path, ResourceLoader.exists(settings_path), settings.camera_zoom_multiplier])
	_build_letterbox()


func _build_letterbox() -> void:
	_letterbox = CanvasLayer.new()
	_letterbox.layer = 100
	_letterbox.visible = false

	_top_bar = ColorRect.new()
	_bottom_bar = ColorRect.new()
	for bar in [_top_bar, _bottom_bar]:
		bar.color = settings.letterbox_color
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_letterbox.add_child(bar)

	call_deferred("_attach_letterbox")


func _attach_letterbox() -> void:
	get_tree().root.add_child(_letterbox)
	_reset_letterbox_hidden()


# Posiziona le barre appena fuori schermo (nascoste), da chiamare una sola
# volta all'avvio: _show_letterbox() poi le anima SOLO da qui in poi,
# senza mai piu' "teletrasportarle" a meta' animazione.
func _reset_letterbox_hidden() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_top_bar.size = Vector2(vp_size.x, settings.letterbox_height)
	_bottom_bar.size = Vector2(vp_size.x, settings.letterbox_height)
	_top_bar.position = Vector2(0, -settings.letterbox_height)
	_bottom_bar.position = Vector2(0, vp_size.y)


# ============================================================
#  API chiamata da player.gd
# ============================================================

# Un player e' appena passato a "downed" (ultimo HP) invece di morire.
func mark_downed(victim: Player, source: Node) -> void:
	if _fatality_active:
		return
	_downed_players[victim.player_id] = {"victim": victim, "last_source": source}
	_input_buffer[victim.player_id] = []
	_input_buffer[1 - victim.player_id] = []


# Il player downed ha appena subito un altro colpo qualsiasi -> lo finisce.
func downed_player_hit(victim: Player, source: Node) -> void:
	if _fatality_active or not _downed_players.has(victim.player_id):
		return
	if not settings.any_hit_finishes:
		return
	_trigger(source, victim, false)


# True se questo player_id e' *davvero* registrato come "downed" qui dentro
# (fonte di verita'). Usata da player.gd per non fidarsi ciecamente del suo
# flag locale is_downed, che puo' restare "agganciato" da un round precedente
# se e' finito (es. per timeout) mentre il player era downed ma non ancora
# finito: vedi clear_downed().
func is_player_downed(pid: int) -> bool:
	return _downed_players.has(pid)


# Da chiamare quando un player viene "rimesso in piedi" per un nuovo round
# (player.gd lo fa in _load_stats()): dimentica qualunque stato "downed"
# residuo per questo player_id, cosi' non resta bloccato in quello stato
# se il round precedente e' finito prima del colpo di grazia.
func clear_downed(pid: int) -> void:
	_downed_players.erase(pid)
	_input_buffer.erase(pid)


# ============================================================
#  Riconoscimento combo
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	if _fatality_active or _downed_players.is_empty():
		return
	for pid in [0, 1]:
		var downed_info = _downed_players.get(1 - pid, null)
		if downed_info == null:
			continue  # l'avversario di "pid" non e' downed, quindi "pid" non puo' fare la combo ora
		var action_suffix: String = _match_action(pid, event)
		if action_suffix == "":
			continue
		_push_input(pid, action_suffix)
		_check_combo(pid, downed_info["victim"])


func _match_action(pid: int, event: InputEvent) -> String:
	var prefix: String = "p1_" if pid == 0 else "p2_"
	for suffix in _COMBO_SUFFIXES:
		var action: String = prefix + suffix
		if InputMap.has_action(action) and event.is_action_pressed(action):
			return suffix
	return _match_pad_action(pid, event)


# NUOVO: la tastiera passa dall'Input Map (sopra), ma i pulsanti del PAD no:
# project.godot non ha NESSUN evento joypad assegnato a p1_attack/p2_attack/
# p1_secondary/p2_secondary (voluto: un'azione con device "qualsiasi"
# scatterebbe per entrambi i pad se ce ne sono 2 collegati). Prima di questa
# funzione, quindi, un input da pad non finiva MAI nel buffer della combo:
# non solo Quadrato, nessun pulsante, R1 incluso. Qui leggiamo l'evento
# joypad grezzo e lo confrontiamo col device_id REALMENTE assegnato a questo
# player_id, con la STESSA mappatura tasti usata in player.gd (attacco =
# R1 o Quadrato, "secondary"/blocco = Cerchio, salto = Croce, run = L1).
func _match_pad_action(pid: int, event: InputEvent) -> String:
	var p: Player = _find_player(pid)
	if p == null or p.device_id < 0:
		return ""  # player su tastiera: gia' gestito da _match_action sopra
	if event is InputEventJoypadButton:
		if event.device != p.device_id or not event.pressed:
			return ""
		match event.button_index:
			JOY_BUTTON_A:
				return "jump"
			JOY_BUTTON_LEFT_SHOULDER:
				return "run"
			JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_X:
				return "attack"     # R1 o Quadrato: stessa coppia usata in player.gd
			JOY_BUTTON_B:
				return "secondary"  # Cerchio
			JOY_BUTTON_DPAD_DOWN:
				return "down"
			JOY_BUTTON_DPAD_LEFT:
				return "left"
			JOY_BUTTON_DPAD_RIGHT:
				return "right"
	elif event is InputEventJoypadMotion and event.device == p.device_id:
		# soglia alta apposta: qui serve un movimento deciso dello stick, non
		# il rumore/drift a riposo (vedi il fix della deadzone in player.gd)
		const AXIS_DEADZONE := 0.5
		if event.axis == JOY_AXIS_LEFT_X:
			if event.axis_value > AXIS_DEADZONE:
				return "right"
			elif event.axis_value < -AXIS_DEADZONE:
				return "left"
		elif event.axis == JOY_AXIS_LEFT_Y and event.axis_value > AXIS_DEADZONE:
			return "down"
	return ""


func _push_input(pid: int, action: String) -> void:
	var buf: Array = _input_buffer.get(pid, [])
	buf.append({"action": action, "time": Time.get_ticks_msec() / 1000.0})
	_input_buffer[pid] = buf


func _check_combo(pid: int, victim: Player) -> void:
	var attacker: Player = _find_player(pid)
	if attacker == null:
		return
	var combo: Array = _get_combo(attacker.fighter_name)
	if combo.is_empty():
		return  # questo personaggio non ha una combo fatality definita nel .cfg

	var window: float = _get_combo_window(attacker.fighter_name)
	var buf: Array = _input_buffer.get(pid, [])
	var now: float = Time.get_ticks_msec() / 1000.0
	while buf.size() > 0 and now - buf[0]["time"] > window:
		buf.pop_front()
	_input_buffer[pid] = buf

	if buf.size() < combo.size():
		return
	var tail: Array = buf.slice(buf.size() - combo.size(), buf.size())
	for i in range(combo.size()):
		if tail[i]["action"] != combo[i]:
			return

	_input_buffer[pid] = []
	_trigger(attacker, victim, true)


func _get_combo(fighter: String) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(FIGHTERS_DIR + fighter + ".cfg") != OK:
		return []
	if not cfg.has_section_key("fatality", "combo"):
		return []
	var raw: String = str(cfg.get_value("fatality", "combo", ""))
	var parts: Array = []
	for p in raw.split(",", false):
		parts.append(p.strip_edges())
	return parts


func _get_combo_window(fighter: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(FIGHTERS_DIR + fighter + ".cfg") != OK:
		return settings.combo_input_window
	return float(cfg.get_value("fatality", "combo_window", settings.combo_input_window))


func _find_player(pid: int) -> Player:
	for p in get_tree().get_nodes_in_group("players"):
		if p.player_id == pid:
			return p
	return null


# Legge la sezione [anim_<anim_name>] dal .cfg della VITTIMA e, se non è già
# presente, la costruisce e la aggiunge allo SpriteFrames che il personaggio
# sta gia' usando in questo momento — sia che provenga da un nodo disegnato
# a mano in scena (Trab, Iacopo, Naka: in quel caso player.gd NON legge MAI
# le sezioni [anim_*] del .cfg, perche' _get_or_build_sprite() trova il nodo
# gia' in scena e si ferma li'), sia che provenga da uno sprite costruito
# dinamicamente dal .cfg (Andrix). Ritorna true se l'animazione e' pronta.
func _ensure_fatality_animation(victim: Player, anim_name: String) -> bool:
	var frames: SpriteFrames = victim.current_sprite.sprite_frames
	if frames == null:
		return false
	if frames.has_animation(anim_name):
		return true

	var cfg := ConfigFile.new()
	if cfg.load(FIGHTERS_DIR + victim.fighter_name + ".cfg") != OK:
		return false
	var section: String = "anim_" + anim_name
	if not cfg.has_section(section):
		return false

	var sheet_path: String = str(cfg.get_value(section, "sheet", ""))
	if sheet_path == "":
		return false
	var texture: Texture2D = load(sheet_path)
	if texture == null:
		push_warning("[Fatality] foglio '%s' non trovato (sezione [%s] di %s.cfg)" % [sheet_path, section, victim.fighter_name])
		return false

	var default_size: int = int(cfg.get_value("model", "frame_size", 256))
	var hframes: int = int(cfg.get_value(section, "hframes", 1))
	var vframes: int = int(cfg.get_value(section, "vframes", 1))
	var frame_count: int = int(cfg.get_value(section, "frames", hframes * vframes))
	var fw: int = int(cfg.get_value(section, "frame_width", cfg.get_value(section, "frame_size", default_size)))
	var fh: int = int(cfg.get_value(section, "frame_height", cfg.get_value(section, "frame_size", default_size)))

	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, bool(cfg.get_value(section, "loop", false)))
	frames.set_animation_speed(anim_name, float(cfg.get_value(section, "fps", 10.0)))

	var added: int = 0
	for row in range(vframes):
		for col in range(hframes):
			if added >= frame_count:
				break
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * fw, row * fh, fw, fh)
			frames.add_frame(anim_name, atlas)
			added += 1

	if added == 0:
		push_warning("[Fatality] la sezione [%s] di %s.cfg non ha prodotto nessun fotogramma (controlla hframes/vframes/frames)" % [section, victim.fighter_name])
		frames.remove_animation(anim_name)
		return false

	return true


# ============================================================
#  Cinematica
# ============================================================

func trigger_fatality(killer: Node, victim: Player) -> void:
	_trigger(killer, victim, true)


func _trigger(killer: Node, victim: Player, via_combo: bool) -> void:
	if _fatality_active:
		return
	_fatality_active = true
	_current_victim = victim
	_downed_players.clear()
	_input_buffer.clear()
	_run_sequence(killer, victim, via_combo)
	_watchdog()


# Rete di sicurezza: se _run_sequence si inceppa da qualche parte (un errore
# a runtime interrompe silenziosamente la coroutine), dopo watchdog_timeout
# secondi REALI si sblocca tutto comunque, invece di restare "inchiodato".
func _watchdog() -> void:
	var timeout: float = settings.watchdog_timeout if settings else 8.0
	await get_tree().create_timer(timeout, true, false, true).timeout
	if _fatality_active:
		push_warning("[Fatality] la cinematica ha superato %ss senza completarsi: sblocco forzato. Controlla il pannello Debugger > Errors per capire cosa si e' inceppato." % timeout)
		_force_recover()


func _force_recover() -> void:
	Engine.time_scale = 1.0
	if _letterbox:
		_letterbox.visible = false
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera:
		camera.position_smoothing_enabled = _camera_smoothing_was_enabled
		camera.drag_horizontal_enabled = _camera_drag_h_was_enabled
		camera.drag_vertical_enabled = _camera_drag_v_was_enabled
		camera.set_process(true)
		camera.set_physics_process(true)
	for p in get_tree().get_nodes_in_group("players"):
		p.combat_locked = false
		p.is_downed = false
	_fatality_active = false
	# La cinematica si e' inceppata: se avevamo gia' una vittima designata,
	# completiamo comunque la "morte" (died) invece di lasciare il round
	# bloccato per sempre senza che nessuno muoia mai.
	if _current_victim != null:
		_current_victim.current_health = 0
		_current_victim.is_dead = true
		_current_victim.health_changed.emit()
		_current_victim.died.emit(_current_victim)
		_current_victim = null


func _run_sequence(killer: Node, victim: Player, via_combo: bool) -> void:
	if settings.lock_input_during_cinematic:
		for p in get_tree().get_nodes_in_group("players"):
			p.combat_locked = true

	if not via_combo or not GameState.gore_enabled:
		# Finito con un colpo QUALSIASI (settings.any_hit_finishes), non con
		# la combo specifica, oppure gore disattivato: niente scenografia e
		# animazioni fatality. In entrambi i casi resta un K.O. normale.
		if settings.fallback_freeze_duration > 0.0:
			await get_tree().create_timer(settings.fallback_freeze_duration, true, false, true).timeout
		for p in get_tree().get_nodes_in_group("players"):
			p.combat_locked = false
		_fatality_active = false
		victim.is_downed = false
		victim.current_health = 0
		victim.is_dead = true
		victim.health_changed.emit()
		victim.died.emit(victim)
		_current_victim = null
		return

	var use_iacopo_fatality: bool = killer is Player and killer.fighter_name == "iacopo"

	_play_oneshot(settings.trigger_sound)

	if settings.use_slowmo_on_trigger and not use_iacopo_fatality:
		Engine.time_scale = settings.slowmo_time_scale
		await get_tree().create_timer(settings.slowmo_duration, true, false, true).timeout
		Engine.time_scale = 1.0

	var camera: Camera2D = get_viewport().get_camera_2d()
	var camera_was_processing: bool = false
	var camera_original_zoom: Vector2 = Vector2.ONE
	var camera_original_position: Vector2 = Vector2.ZERO
	var camera_smoothing_was_enabled: bool = false
	var camera_drag_h_was_enabled: bool = false
	var camera_drag_v_was_enabled: bool = false
	if camera:
		camera_was_processing = camera.is_processing() or camera.is_physics_processing()
		camera_original_zoom = camera.zoom          # per tornare esattamente allo zoom di gioco normale
		camera_original_position = camera.global_position
		camera_smoothing_was_enabled = camera.position_smoothing_enabled
		camera_drag_h_was_enabled = camera.drag_horizontal_enabled
		camera_drag_v_was_enabled = camera.drag_vertical_enabled
		_camera_smoothing_was_enabled = camera_smoothing_was_enabled
		_camera_drag_h_was_enabled = camera_drag_h_was_enabled
		_camera_drag_v_was_enabled = camera_drag_v_was_enabled
		camera.set_process(false)
		camera.set_physics_process(false)
		# IMPORTANTE: lo smoothing/drag NATIVI di Camera2D (position_smoothing_enabled,
		# drag_horizontal/vertical_enabled) sono applicati dal motore ad ogni frame
		# INDIPENDENTEMENTE dallo script della camera: set_process()/set_physics_process()
		# NON li disattiva. Se la tua camera_2d.gd li usa per seguire i due lottatori,
		# continuerebbero a "tirare" la camera verso di loro durante il nostro tween,
		# vanificandolo e facendo sembrare che la camera "torni indietro" invece di
		# restare ferma sullo zoom/posizione della vittima. Li spegniamo qui e li
		# ripristiniamo esattamente come erano a fine cinematica.
		camera.position_smoothing_enabled = false
		camera.drag_horizontal_enabled = false
		camera.drag_vertical_enabled = false

	if settings.use_letterbox:
		_show_letterbox(true)

	if camera:
		var target: Vector2 = victim.global_position + settings.camera_offset
		var target_zoom: Vector2 = camera_original_zoom * settings.camera_zoom_multiplier
		var pan_duration: float = minf(settings.camera_pan_time, 0.22) if use_iacopo_fatality else settings.camera_pan_time
		print("[Fatality] zoom camera: da %s a %s (moltiplicatore %s) in %ss" % [camera_original_zoom, target_zoom, settings.camera_zoom_multiplier, pan_duration])
		var tw := create_tween()
		tw.set_parallel(true)
		tw.set_trans(settings.camera_pan_trans)
		tw.set_ease(settings.camera_pan_ease)
		tw.tween_property(camera, "global_position", target, pan_duration)
		tw.tween_property(camera, "zoom", target_zoom, pan_duration)
		await tw.finished

	var killer_name: String = killer.fighter_name if (killer is Player) else "unknown"
	var anim_name: String = "%s_%s" % [victim.fighter_name, killer_name]
	# La fatality di Iacopo usa effetti generici: non carica la spritesheet beta
	# trab_iacopo, così funziona con qualunque personaggio come vittima.
	var has_anim: bool = false
	if not use_iacopo_fatality:
		has_anim = _ensure_fatality_animation(victim, anim_name)

	if use_iacopo_fatality:
		var sprite: AnimatedSprite2D = victim.current_sprite
		var has_hurt: bool = _ensure_fatality_animation(victim, "hurt")
		if has_hurt:
			sprite.stop()
			sprite.play("hurt")
			var hurt_frames: int = sprite.sprite_frames.get_frame_count("hurt")
			var impact_frame: int = maxi(0, int(hurt_frames * 0.08))
			await _await_animation_frame(sprite, "hurt", impact_frame, settings.max_animation_duration)
		else:
			# I personaggi senza posa hurt restano sulla propria posa corrente.
			sprite.stop()
			await get_tree().create_timer(0.08).timeout
		await _play_iacopo_impact(victim)
		if has_hurt and sprite.is_playing():
			await _await_first(sprite.animation_finished, get_tree().create_timer(settings.max_animation_duration).timeout)
	elif has_anim:
		var frames: SpriteFrames = victim.current_sprite.sprite_frames
		if settings.animation_fps_override > 0.0:
			frames.set_animation_speed(anim_name, settings.animation_fps_override)
		# forzato a false: se il .cfg non scrive "loop = false" esplicitamente, di default
		# le animazioni diverse da hit/hurt vengono costruite in loop, e un'animazione in
		# loop non emette mai "animation_finished".
		frames.set_animation_loop(anim_name, false)
		victim.current_sprite.stop()
		victim.current_sprite.play(anim_name)
		await _await_first(victim.current_sprite.animation_finished, get_tree().create_timer(settings.max_animation_duration).timeout)
	else:
		push_warning("[Fatality] Nessuna animazione '%s' trovata: aggiungi una sezione [anim_%s] nel .cfg di %s per personalizzarla. Uso un fermo immagine." % [anim_name, anim_name, victim.fighter_name])
		await get_tree().create_timer(settings.fallback_freeze_duration).timeout

	_play_oneshot(settings.finish_sound)

	if settings.use_letterbox:
		_show_letterbox(false)
		await get_tree().create_timer(settings.letterbox_fade_time).timeout

	if camera:
		var tw2 := create_tween()
		tw2.set_parallel(true)
		tw2.set_trans(settings.camera_pan_trans)
		tw2.set_ease(settings.camera_pan_ease)
		tw2.tween_property(camera, "zoom", camera_original_zoom, settings.camera_return_time)
		tw2.tween_property(camera, "global_position", camera_original_position, settings.camera_return_time)
		await tw2.finished
		camera.position_smoothing_enabled = camera_smoothing_was_enabled
		camera.drag_horizontal_enabled = camera_drag_h_was_enabled
		camera.drag_vertical_enabled = camera_drag_v_was_enabled
		camera.set_process(camera_was_processing)
		camera.set_physics_process(camera_was_processing)

	for p in get_tree().get_nodes_in_group("players"):
		p.combat_locked = false

	_fatality_active = false
	victim.is_downed = false
	victim.current_health = 0
	victim.is_dead = true  # resta fermo nella posa finale finche' level.gd non resetta il round (_load_stats())
	victim.health_changed.emit()
	victim.died.emit(victim)
	_current_victim = null


func _await_animation_frame(sprite: AnimatedSprite2D, anim_name: String, target_frame: int, timeout: float) -> void:
	var deadline: float = Time.get_ticks_msec() / 1000.0 + timeout
	while is_instance_valid(sprite) and sprite.animation == anim_name \
			and sprite.frame < target_frame and Time.get_ticks_msec() / 1000.0 < deadline:
		await get_tree().process_frame


func _play_iacopo_impact(victim: Player) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(FIGHTERS_DIR + "iacopo.cfg") != OK:
		return
	var impact_section := "fatality"
	var chain_path: String = str(cfg.get_value(impact_section, "impact_sheet", ""))
	var scream_path: String = str(cfg.get_value(impact_section, "impact_sound", ""))
	if chain_path == "" or not ResourceLoader.exists(chain_path):
		push_warning("[Fatality] foglio catene non configurato o non trovato: '%s'" % chain_path)
		return

	var chain_texture: Texture2D = load(chain_path)
	if chain_texture == null:
		return
	var layer := CanvasLayer.new()
	layer.name = "IacopoFatalityImpact"
	layer.layer = 110
	get_tree().root.add_child(layer)

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var target_screen_position: Vector2 = get_viewport().get_canvas_transform() * victim.global_position
	var soft_texture: Texture2D = _make_soft_circle_texture()
	var blood_cloud := Sprite2D.new()
	blood_cloud.name = "BloodCloud"
	blood_cloud.texture = soft_texture
	blood_cloud.position = target_screen_position
	blood_cloud.scale = Vector2(0.35, 0.28)
	blood_cloud.modulate = Color(0.82, 0.008, 0.02, 0.72)
	layer.add_child(blood_cloud)
	var cloud_tween := create_tween()
	cloud_tween.set_parallel(true)
	cloud_tween.tween_property(blood_cloud, "scale", Vector2(2.2, 1.65), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	cloud_tween.tween_property(blood_cloud, "modulate:a", 0.0, 0.95).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var particles := CPUParticles2D.new()
	particles.name = "RedBloodParticles"
	particles.position = target_screen_position
	particles.texture = soft_texture
	particles.amount = 64
	particles.lifetime = 0.72
	particles.one_shot = true
	particles.explosiveness = 0.72
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(28.0, 20.0)
	particles.direction = Vector2(0.0, -1.0)
	particles.spread = 180.0
	particles.gravity = Vector2(0.0, 42.0)
	particles.initial_velocity_min = 35.0
	particles.initial_velocity_max = 155.0
	particles.scale_amount_min = 0.12
	particles.scale_amount_max = 0.34
	particles.color = Color(0.9, 0.012, 0.025, 0.8)
	var particle_gradient := Gradient.new()
	particle_gradient.set_color(0, Color(0.95, 0.02, 0.035, 0.82))
	particle_gradient.add_point(0.55, Color(0.65, 0.008, 0.02, 0.55))
	particle_gradient.set_color(1, Color(0.4, 0.0, 0.01, 0.0))
	particles.color_ramp = particle_gradient
	layer.add_child(particles)
	particles.emitting = true

	var burst_frames := SpriteFrames.new()
	burst_frames.remove_animation("default")
	burst_frames.add_animation("burst")
	burst_frames.set_animation_loop("burst", false)
	burst_frames.set_animation_speed("burst", float(cfg.get_value(impact_section, "impact_fps", 20.0)))
	var hframes := 4
	var vframes := 4
	var fw := chain_texture.get_width() / hframes
	var fh := chain_texture.get_height() / vframes
	for row in range(vframes):
		for col in range(hframes):
			var frame := AtlasTexture.new()
			frame.atlas = chain_texture
			frame.region = Rect2(col * fw, row * fh, fw, fh)
			burst_frames.add_frame("burst", frame)
	var burst := AnimatedSprite2D.new()
	burst.name = "ReturningChains"
	burst.sprite_frames = burst_frames
	burst.animation = "burst"
	burst.centered = true
	var fit_scale: float = minf(viewport_size.x * 0.42 / fw, viewport_size.y * 0.42 / fh)
	burst.scale = Vector2.ONE * fit_scale
	burst.position = target_screen_position
	layer.add_child(burst)
	burst.play("burst")
	await get_tree().process_frame
	if scream_path != "" and ResourceLoader.exists(scream_path):
		var scream := AudioStreamPlayer.new()
		scream.name = "FatalityScream"
		scream.stream = load(scream_path)
		scream.volume_db = 6.0
		add_child(scream)
		scream.play()
		scream.finished.connect(scream.queue_free)
	await burst.animation_finished

	_replace_victim_with_remnant(victim)
	await get_tree().create_timer(0.18).timeout
	layer.queue_free()


func _make_soft_circle_texture(size: int = 64) -> Texture2D:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center: float = (size - 1) * 0.5
	var radius: float = center
	for y in range(size):
		for x in range(size):
			var distance: float = Vector2(x - center, y - center).length() / radius
			var alpha: float = pow(maxf(1.0 - distance, 0.0), 2.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _replace_victim_with_remnant(victim: Player) -> void:
	if not is_instance_valid(victim.current_sprite):
		return
	var source: AnimatedSprite2D = victim.current_sprite
	if source.sprite_frames == null or not source.sprite_frames.has_animation(source.animation) \
			or source.sprite_frames.get_frame_count(source.animation) == 0:
		return
	var remnant := Sprite2D.new()
	remnant.name = "FatalityRemnant"
	var frame_index: int = clampi(source.frame, 0, source.sprite_frames.get_frame_count(source.animation) - 1)
	remnant.texture = source.sprite_frames.get_frame_texture(source.animation, frame_index)
	remnant.centered = source.centered
	remnant.offset = source.offset
	remnant.position = source.position
	remnant.rotation = source.rotation
	remnant.scale = source.scale
	remnant.flip_h = source.flip_h
	remnant.z_index = source.z_index
	remnant.modulate = Color(0.68, 0.25, 0.25, 1.0)
	source.get_parent().add_child(remnant)
	source.visible = false
	_fatality_remnants[victim.get_instance_id()] = remnant


func restore_player_visual(player: Player) -> void:
	if player == null:
		return
	var key: int = player.get_instance_id()
	var remnant: Node = _fatality_remnants.get(key, null)
	if is_instance_valid(remnant):
		remnant.queue_free()
	_fatality_remnants.erase(key)
	if is_instance_valid(player.current_sprite):
		player.current_sprite.visible = true


func _play_oneshot(stream: AudioStream) -> void:
	if stream == null:
		return
	var sfx := AudioStreamPlayer.new()
	sfx.stream = stream
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)


func _await_first(sig_a: Signal, sig_b: Signal) -> void:
	var done := false
	var mark := func(): done = true
	sig_a.connect(mark, CONNECT_ONE_SHOT)
	sig_b.connect(mark, CONNECT_ONE_SHOT)
	while not done:
		await get_tree().process_frame


func _show_letterbox(show_bars: bool) -> void:
	_letterbox.visible = true
	var vp_size: Vector2 = get_viewport().get_visible_rect().size

	var tw := create_tween()
	tw.set_parallel(true)
	if show_bars:
		tw.tween_property(_top_bar, "position:y", 0.0, settings.letterbox_fade_time)
		tw.tween_property(_bottom_bar, "position:y", vp_size.y - settings.letterbox_height, settings.letterbox_fade_time)
	else:
		tw.tween_property(_top_bar, "position:y", -settings.letterbox_height, settings.letterbox_fade_time)
		tw.tween_property(_bottom_bar, "position:y", vp_size.y, settings.letterbox_fade_time)
		tw.finished.connect(func(): _letterbox.visible = false)
