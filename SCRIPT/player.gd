class_name Player
extends CharacterBody2D

signal health_changed  # <-- serve per healt_bar.gd
signal stamina_changed  # <-- serve per stamina_bar.gd
signal died(player)  # emesso una sola volta quando la vita arriva a 0 (lo ascolta level.gd)

# --- Statistiche: si modificano in res://data/fighters/ (base.cfg + un .cfg per personaggio), NON qui ---
# (i valori scritti qui sono solo il fallback se il file manca o una chiave non c'è)
var max_health: int = 100
var current_health: int = 100
var attack_damage: int = 10
var attack_delay: float = 0.3  # secondi tra la pressione del tasto e il colpo vero e proprio
var speed: float = 100.0
var run_speed: float = 250.0
var attack_move_speed: float = 10.0
var jump_velocity: float = -300.0
var can_run: bool = true

# --- NUOVO: stamina (barra sotto quella della vita) ---
# usata dal potere secondario (ogni potere ha il suo stamina_cost/stamina_min,
# vedi fighter_power.gd): si consuma lanciandolo, si recupera nel tempo (di
# piu' correndo) e colpendo a segno col pugno normale.
var max_stamina: float = 100.0
var current_stamina: float = 100.0
var stamina_reload_rate: float = 40.0    # recuperata al secondo TENENDO premuto E / Triangolo (non c'e' piu' recupero a tempo)
var is_reloading: bool = false           # true mentre il player sta ricaricando la stamina (resta fermo)
var stamina_hit_gain: float = 8.0          # guadagnata quando il pugno normale va a segno

# --- feedback dei colpi (vedi _play_hit_feedback) ---
var hit_knockback: float = 220.0       # rinculo: velocita' orizzontale della spinta subita
var attack_knockback: float = 220.0   # forza della spinta inflitta al bersaglio
var _current_attack_animation: String = "hit"
var attack_dash_speed: float = 0.0
var attack_dash_duration: float = 0.0
var _attack_dash_left: float = 0.0
var hit_stun_duration: float = 0.25    # stordimento: per quanti secondi non si risponde ai comandi
var hit_flash_duration: float = 0.12   # per quanti secondi lo sprite resta colorato dopo il colpo
var hit_flash_color: Color = Color(1.0, 0.35, 0.35, 1.0)  # colore del lampo (default: rossastro)
var hit_sound: AudioStream = null      # caricato da hit_sound nei file .cfg

# --- sangue quando si prende danno (vedi _spawn_blood) ---
var blood_amount: int = 18             # quante particelle per colpo (0 = nessun sangue)
var blood_color: Color = Color(0.75, 0.03, 0.03, 1.0)
var blood_lifetime: float = 0.6        # durata delle particelle (secondi)
var blood_speed_min: float = 60.0
var blood_speed_max: float = 180.0

# --- blocco (guardia): tasti p1_secondary / p2_secondary ---
var aura_loss_on_hit: float = 12.0 # aura persa a ogni colpo subito
var block_damage_reduction: float = 0.3  # % di danno ancora subita mentre si blocca (0 = blocco perfetto)

# --- NUOVO: identità e schema di controllo del player ---
@export var player_id: int = 0
# device_id:
#   -1 = tastiera Player 1 (azioni p1_*)
#   -2 = tastiera Player 2 (azioni p2_*)
#   >=0 = indice del pad (letto via codice, es. Input.get_connected_joypads()[0])
@export var device_id: int = -1
# skin_override: -1 = usa GameState, altrimenti forza la skin per questo player
@export var skin_override: int = -1

var _run_trail_clock: float = 0.0
var _was_on_floor: bool = true
var isHurt: bool = false  # true mentre dura lo stordimento da colpo subito (vedi hurt_stun_left)
var isAttacking: bool = false

# --- FATALITY: vedi FatalityManager (autoload) e fatality_settings.gd ---
# is_downed: true quando il player e' arrivato all'HP minimo (FatalityManager.settings.downed_health)
#   invece di morire subito: resta "in piedi ma finito" finche' non arriva il colpo di grazia
#   (un altro colpo qualsiasi, oppure la combo specifica del suo avversario).
var is_downed: bool = false
# combat_locked: true durante la cinematica della fatality, blocca input/fisica del player.
var combat_locked: bool = false
var intro_locked: bool = false
# is_dead: true DOPO la fatality (quando "died" e' gia' stato emesso). A fine
# cinematica combat_locked torna false per tutti (anche per la vittima, serve
# per far ripartire l'altro player), ma senza questo flag il player a 0 HP
# poteva continuare a camminare/attaccare come se niente fosse (sembrava
# "non morire mai") finche' level.gd non reagiva al segnale "died". Con
# is_dead=true il player resta fermo nella posa finale, qualunque cosa
# level.gd faccia e in qualunque momento lo faccia.
var is_dead: bool = false
var frozen_time_left: float = 0.0  # secondi di immobilita' forzata da un potere
var hitbox_delay_left: float = 0.0  # secondi che mancano all'attivazione della hitbox
var hurt_stun_left: float = 0.0  # secondi di stordimento rimanenti dopo un colpo subito
var is_blocking: bool = false  # true mentre il player tiene premuto il tasto "secondary"
var _suppress_next_hit_knockback: bool = false

# --- NUOVO: multiplayer online (vedi network_manager.gd) ---
var is_networked: bool = false  # true se la partita gira online (deciso da solo in _enter_tree)
var is_local: bool = true       # true se questo Player è quello di QUESTO PC (rilevante solo se is_networked)
var is_bot: bool = false
var synced_animation: String = "idle"  # replicata al client per mostrare l'animazione giusta
var synced_flip_h: bool = false        # replicato al client per il verso giusto
var synced_power_effect: String = ""    # effetto secondario temporaneo da mostrare sul client
# ultimo stato tasti ricevuto dal PC remoto (letto dall'host per simulare il player non suo)
var _remote_input: Dictionary = {"dir": 0.0, "run": false, "jump": false, "attack": false, "block": false, "secondary": false, "reload": false}
var _bot_input: Dictionary = {"dir": 0.0, "run": false, "jump": false, "attack": false, "block": false, "secondary": false, "reload": false}
var _bot_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _bot_think_left: float = 0.0
var _bot_attack_left: float = 0.0
var _bot_jump_left: float = 0.0
var _bot_hit_reaction_left: float = 0.0
var _bot_charge_left: float = 0.0
var _bot_charge_active: bool = false
var _bot_charge_hold_limit: float = 0.05
var _bot_charge_extra_hold: float = 0.0
var _bot_evade_direction: float = 0.0
var _bot_last_target_position: Vector2 = Vector2.ZERO
var _bot_has_target_sample: bool = false
var _bot_last_opponent_power_cooldown: float = -1.0
var _bot_opponent_power_was_busy: bool = false
var _bot_target: Player

# --- NUOVO: attacco caricato del potere secondario (vedi fighter_power.has_charged_attack) ---
var _secondary_hold_time: float = 0.0  # da quanto e' tenuto premuto "secondary"
var _secondary_charging: bool = false  # true mentre la carica e' attiva (dopo la soglia)

@onready var hit_sfx: AudioStreamPlayer = AudioStreamPlayer.new()  # riprodotto a ogni colpo subito

const FIGHTERS_DIR := "res://data/fighters/"
# base.cfg = valori comuni. Ogni altro .cfg della cartella = un personaggio:
# il nome del file e' il nome del personaggio, [character] skin = N il suo
# numero di skin. Per aggiungere un personaggio basta aggiungere un file:
# questo script non va toccato.
static var _base_cfg: ConfigFile
static var _fighter_cfgs: Dictionary = {}   # nome -> ConfigFile
static var _skins: Dictionary = {}          # numero di skin -> nome
static var _fighter_names: Array = []       # ordinati per skin
static var _power_hint_shown: Dictionary = {}

var skin: int = 0
var fighter_name: String = ""  # nome della sezione nei file .cfg per la skin attuale

var chain_sprite: AnimatedSprite2D = null  # effetto del pugno (opzionale): [model] attack_fx_node nel .cfg
@onready var hurtbox: Hurtbox = $Hurtbox

# --- Potere secondario: si collega da [secondary] nel .cfg del personaggio ---
var secondary_power = null  # potere collegato da [secondary].
var deathlift_power = null

# sprite e hitbox di ogni personaggio, indicizzati per nome (vedi _ready):
# se il nodo esiste gia' in scena (personaggio disegnato a mano) viene
# riusato, altrimenti viene costruito a runtime dai dati nei file .cfg
var _sprites: Dictionary = {}
var _hitboxes: Dictionary = {}

var current_sprite: AnimatedSprite2D
var current_hitbox: Hitbox
var chain_base_x: float

# --- dimensioni sprite ---
# scala dello sprite cosi' come e' impostata nella scena (WND_trab.tscn):
# e' il riferimento, model_scale dei file .cfg la moltiplica soltanto
var _base_scale: Vector2 = Vector2.ONE
var _model_scale: float = 1.0
# altezza (px) del fotogramma idle: tutte le altre animazioni vengono
# riscalate per apparire grandi quanto l'idle
var _idle_frame_height: float = 0.0
var current_hitbox_shape: CollisionShape2D  # shape della hitbox attiva (viene specchiata)
var hitbox_base_x: float  # X originale della shape (in editor)


func _enter_tree() -> void:
	# NUOVO: capisce da solo se la partita è online e se questo player_id è
	# quello controllato da QUESTO PC (host = sempre player_id 0)
	# NOTA: has_multiplayer_peer() da solo NON basta. Se il progetto crea un
	# MultiplayerPeer anche in locale (es. l'host viene sempre istanziato per
	# poter riusare la stessa architettura, anche quando in realta' si gioca
	# in 2 sulla stessa tastiera/pad), has_multiplayer_peer() risultava vero
	# per ENTRAMBI i player: player2 (player_id=1) veniva quindi trattato come
	# "remoto" (is_local=false, vedi sotto) e restava in attesa di input dalla
	# rete invece di leggere la tastiera/pad locale. Una partita e' DAVVERO
	# online solo se: (a) siamo un client (non l'host), oppure (b) siamo
	# l'host e c'e' almeno un peer remoto connesso. Se l'host non ha nessuno
	# connesso (caso locale/offline), non e' rete: tutti i player leggono i
	# loro input locali (p1_*/p2_*/pad), com'era prima che esistesse il multiplayer.
	is_networked = multiplayer.has_multiplayer_peer() \
		and (not multiplayer.is_server() or not multiplayer.get_peers().is_empty())
	if is_networked:
		is_local = (player_id == 0) == multiplayer.is_server()

	# skin e statistiche si decidono qui, prima di qualsiasi _ready():
	# così la barra della vita legge già il max_health giusto
	# se skin_override non è impostato, usa la config del GameState per questo player_id
	if skin_override != -1:
		skin = skin_override
	elif GameState.has_method("get_skin_for"):
		skin = GameState.get_skin_for(player_id)
	else:
		skin = GameState.selected_skin  # fallback compatibile col vecchio sistema
	is_bot = GameState.has_method("is_bot_for") and GameState.is_bot_for(player_id)
	_bot_rng.randomize()

	_load_fighters()
	if _skins.is_empty():
		return  # nessun personaggio caricato: l'errore e' gia' stato stampato da _load_fighters
	if not _skins.has(skin):
		push_warning("Skin non valida: %s" % skin)
		skin = int(_skins.keys().min())
	fighter_name = _skins[skin]

	_load_stats()


# --- NUOVO: funzioni di rete ---

# Crea a runtime un MultiplayerSynchronizer che replica dall'host (sempre
# autorevole) a chi si connette: posizione, vita, stamina e le due variabili
# "synced_*" che tengono animazione e verso allineati sul client.
func _setup_networking() -> void:
	if not is_networked:
		return
	set_multiplayer_authority(1)  # l'host (peer 1) simula la fisica per entrambi i player

	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:global_position"))
	config.add_property(NodePath(".:current_health"))
	config.add_property(NodePath(".:current_stamina"))
	config.add_property(NodePath(".:synced_animation"))
	config.add_property(NodePath(".:synced_flip_h"))
	config.add_property(NodePath(".:synced_power_effect"))

	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSynchronizer"
	sync.replication_config = config
	add_child(sync)


# Sul client questo Player non è autorevole: non simula nulla, si limita a
# mostrare l'animazione/il verso arrivati sincronizzati dall'host.
func _process(_delta: float) -> void:
	if not is_networked or is_multiplayer_authority():
		return
	if current_sprite == null:
		return
	if current_sprite.animation != synced_animation and current_sprite.sprite_frames != null \
			and current_sprite.sprite_frames.has_animation(synced_animation):
		current_sprite.play(synced_animation)
	current_sprite.flip_h = synced_flip_h
	if secondary_power != null:
		secondary_power.sync_remote_visual(synced_power_effect)
	if chain_sprite != null:
		chain_sprite.flip_h = synced_flip_h


# Chiamata solo dal PC che controlla davvero questo player (is_local): manda
# all'host (rpc_id(1, ...)) lo stato attuale dei propri tasti. L'host, se è
# lui stesso il player locale, non ne ha bisogno (legge l'Input direttamente).
func _send_local_input() -> void:
	if multiplayer.is_server():
		return
	_receive_input.rpc_id(1, {
		"dir": Input.get_axis("p1_left", "p1_right"),
		"run": Input.is_action_pressed("p1_run"),
		"jump": Input.is_action_just_pressed("p1_jump"),
		"attack": Input.is_action_just_pressed("p1_attack"),
		"block": Input.is_action_pressed("p1_secondary"),
		"secondary": Input.is_action_just_pressed("p1_secondary"),
		"reload": _reload_pressed(),
	})


@rpc("any_peer", "unreliable_ordered")
func _receive_input(input: Dictionary) -> void:
	_remote_input = input


# Legge (e consuma) un tasto "a pressione singola" arrivato dal client: si
# azzera subito dopo la lettura così un solo invio non viene contato più
# volte nei fotogrammi fisici dell'host in cui non arriva un aggiornamento.
func _remote_consume(key: String) -> bool:
	var v: bool = bool(_remote_input.get(key, false))
	if v:
		_remote_input[key] = false
	return v


# --- Lettura di res://data/fighters/ ---
# base.cfg = valori comuni; ogni altro .cfg della cartella = un personaggio.
# Il numero di skin e' la chiave "skin" dentro [character] di ogni file.
static func _load_cfg(path: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(path)
	if err != OK:
		push_warning("%s non caricato (errore %d)" % [path, err])
	return cfg


static func _load_fighters() -> void:
	if not _fighter_names.is_empty():
		return
	if not DirAccess.dir_exists_absolute(FIGHTERS_DIR):
		push_error("Cartella %s non trovata: crea la cartella data/fighters nel progetto e copiaci dentro base.cfg e i .cfg dei personaggi (trab, iacopo, naka, andrix)" % FIGHTERS_DIR)
		_base_cfg = ConfigFile.new()
		return
	_base_cfg = _load_cfg(FIGHTERS_DIR + "base.cfg")

	var entries: Array = []  # [skin, nome]
	for file in DirAccess.get_files_at(FIGHTERS_DIR):
		if file.get_extension() != "cfg" or file == "base.cfg":
			continue
		var fname: String = file.get_basename()
		var cfg: ConfigFile = _load_cfg(FIGHTERS_DIR + file)
		_fighter_cfgs[fname] = cfg
		entries.append([int(cfg.get_value("character", "skin", 9999)), fname])

	entries.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	for e in entries:
		if _skins.has(e[0]):
			push_warning("skin %d assegnata sia a '%s' che a '%s': tengo la prima" % [e[0], _skins[e[0]], e[1]])
			continue
		_skins[e[0]] = e[1]
		_fighter_names.append(e[1])

	if _fighter_names.is_empty():
		push_error("Nessun personaggio trovato in %s (servono file .cfg con [character] skin = N)" % FIGHTERS_DIR)


# Elenco dei personaggi, ordinati per skin. Calcolato una sola volta.
static func _get_fighter_names() -> Array:
	_load_fighters()
	return _fighter_names


# Valore di un personaggio qualsiasi: prima il suo file, poi base.cfg, poi il fallback
static func _stat_of(fighter: String, section: String, key: String, fallback: Variant) -> Variant:
	var cfg: ConfigFile = _fighter_cfgs.get(fighter)
	if cfg != null and cfg.has_section_key(section, key):
		return cfg.get_value(section, key)
	return _base_cfg.get_value(section, key, fallback)


# Come _stat_of, per il personaggio di questa istanza
func _stat(section: String, key: String, fallback: Variant) -> Variant:
	return _stat_of(fighter_name, section, key, fallback)


# Costruisce a runtime un AnimatedSprite2D dalle sezioni [anim_<nome>] del file
# del personaggio (idle, walk, run, hit, hurt...): ogni sezione descrive un
# foglio sprite (sheet, hframes, vframes, frames, fps, loop) che viene affettato.
static func _build_dynamic_sprite(fighter: String, node_name: String) -> AnimatedSprite2D:
	var cfg: ConfigFile = _fighter_cfgs[fighter]
	var sprite := AnimatedSprite2D.new()
	sprite.name = node_name

	var default_size: int = int(_stat_of(fighter, "model", "frame_size", 256))
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for section in cfg.get_sections():
		if not section.begins_with("anim_"):
			continue
		var anim: String = section.trim_prefix("anim_")
		var sheet_path: String = str(cfg.get_value(section, "sheet", ""))
		if sheet_path == "":
			continue
		var texture: Texture2D = load(sheet_path)
		if texture == null:
			push_warning("[%s] %s: foglio '%s' non trovato" % [fighter, section, sheet_path])
			continue

		var hframes: int = int(cfg.get_value(section, "hframes", 1))
		var vframes: int = int(cfg.get_value(section, "vframes", 1))
		var frame_count: int = int(cfg.get_value(section, "frames", hframes * vframes))
		var fw: int = int(cfg.get_value(section, "frame_width", cfg.get_value(section, "frame_size", default_size)))
		var fh: int = int(cfg.get_value(section, "frame_height", cfg.get_value(section, "frame_size", default_size)))

		frames.add_animation(anim)
		frames.set_animation_loop(anim, bool(cfg.get_value(section, "loop", anim != "hit" and anim != "hurt")))
		frames.set_animation_speed(anim, float(cfg.get_value(section, "fps", 10.0)))

		var added: int = 0
		for row in range(vframes):
			for col in range(hframes):
				if added >= frame_count:
					break
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2(col * fw, row * fh, fw, fh)
				frames.add_frame(anim, atlas)
				added += 1

	sprite.sprite_frames = frames
	if frames.has_animation("idle"):
		sprite.animation = "idle"
	return sprite


# Trova lo sprite del personaggio se esiste gia' in scena (personaggio
# disegnato a mano nell'editor); altrimenti lo costruisce dalle sezioni
# [anim_*] del suo file. Un personaggio nuovo non richiede nodi in scena.
func _get_or_build_sprite(fighter: String) -> AnimatedSprite2D:
	var node_name: String = str(_stat_of(fighter, "model", "node", fighter + "_Sprite"))

	var existing: Node = get_node_or_null(node_name)
	if existing is AnimatedSprite2D:
		return existing
	if existing != null:
		push_warning("'%s' esiste ma non e' un AnimatedSprite2D: lo ignoro e ne costruisco uno nuovo per %s" % [node_name, fighter])
	elif get_node_or_null(node_name.to_lower()) != null or get_node_or_null(node_name.to_upper()) != null:
		# i nomi dei nodi distinguono maiuscole/minuscole: probabile refuso in [model] node
		push_warning("[model] node '%s' di %s non trovato per esatta corrispondenza di maiuscole/minuscole: controlla il nome del nodo in scena" % [node_name, fighter])

	var built: AnimatedSprite2D = _build_dynamic_sprite(fighter, node_name)
	add_child(built)  # gli sprite gia' in scena ci sono di default, questi vanno aggiunti a mano
	return built


# Trova la hitbox del pugno se esiste gia' sotto lo sprite; altrimenti la crea
# copiando hitbox_template_node (base.cfg) con gli eventuali hitbox_offset_x/y,
# hitbox_width/height del file del personaggio ([model]).
func _get_or_build_hitbox(fighter: String, sprite: AnimatedSprite2D) -> Hitbox:
	var cfg: ConfigFile = _fighter_cfgs[fighter]
	var hitbox_node_name: String = str(_stat_of(fighter, "model", "hitbox_node", "PunchHitbox"))

	var existing: Node = sprite.get_node_or_null(hitbox_node_name)
	if existing is Hitbox:
		return existing

	var template_path: String = str(_stat_of(fighter, "model", "hitbox_template_node", "TRAB_Sprite2D/PunchHitbox"))
	var template: Node = get_node_or_null(template_path)
	if not (template is Hitbox):
		push_warning("hitbox_template_node '%s' non trovata: %s non avra' una hitbox" % [template_path, fighter])
		return null

	var hitbox: Hitbox = template.duplicate()
	hitbox.name = hitbox_node_name.get_file()  # se hitbox_node e' un percorso tipo "Chain/PunchHitbox"
	sprite.add_child(hitbox)

	var shape_node: CollisionShape2D = hitbox.get_node("CollisionShape2D")
	shape_node.position = Vector2(
		float(cfg.get_value("model", "hitbox_offset_x", shape_node.position.x)),
		float(cfg.get_value("model", "hitbox_offset_y", shape_node.position.y))
	)

	if cfg.has_section_key("model", "hitbox_width") or cfg.has_section_key("model", "hitbox_height"):
		var shape: Shape2D = shape_node.shape
		if shape is RectangleShape2D:
			var new_shape: RectangleShape2D = shape.duplicate()
			new_shape.size = Vector2(
				float(cfg.get_value("model", "hitbox_width", shape.size.x)),
				float(cfg.get_value("model", "hitbox_height", shape.size.y))
			)
			shape_node.shape = new_shape

	return hitbox


func _load_stats() -> void:
	# reset dello stato fatality: importante se lo stesso nodo Player viene
	# riutilizzato per un nuovo round/scontro invece di essere ricreato da zero.
	# Puliamo anche il lato FatalityManager (non solo il flag locale): se il
	# round precedente e' finito (es. timeout) MENTRE questo player era
	# "downed" ma non ancora finito con il colpo di grazia, FatalityManager
	# lo ricorda ancora come downed. Senza questa riga, il primo colpo del
	# round nuovo lo manda dritto in fatality invece di infliggere danno
	# normale: e' la causa piu' probabile del "respawn a 1 vita".
	is_downed = false
	combat_locked = false
	is_dead = false
	frozen_time_left = 0.0
	FatalityManager.clear_downed(player_id)

	max_health = int(_stat("stats", "max_health", max_health))
	current_health = max_health
	attack_damage = int(_stat("stats", "attack_damage", attack_damage))
	attack_delay = float(_stat("stats", "attack_delay", attack_delay))
	speed = float(_stat("stats", "speed", speed))
	run_speed = float(_stat("stats", "run_speed", run_speed))
	attack_move_speed = float(_stat("stats", "attack_move_speed", attack_move_speed))
	jump_velocity = float(_stat("stats", "jump_velocity", jump_velocity))
	can_run = bool(_stat("stats", "can_run", can_run))
	block_damage_reduction = clampf(float(_stat("stats", "block_damage_reduction", block_damage_reduction)), 0.0, 1.0)

	max_stamina = float(_stat("stats", "max_stamina", max_stamina))
	current_stamina = clampf(float(_stat("stats", "starting_stamina", max_stamina)), 0.0, max_stamina)
	stamina_reload_rate = float(_stat("stats", "stamina_reload_rate", stamina_reload_rate))
	stamina_hit_gain = float(_stat("stats", "stamina_hit_gain", stamina_hit_gain))

	hit_knockback = float(_stat("feedback", "hit_knockback", hit_knockback))
	attack_knockback = float(_stat("feedback", "attack_knockback", attack_knockback))
	_current_attack_animation = str(_stat("model", "attack_animation", "hit"))
	attack_dash_speed = maxf(float(_stat("stats", "attack_dash_speed", 0.0)), 0.0)
	attack_dash_duration = maxf(float(_stat("stats", "attack_dash_duration", 0.0)), 0.0)
	hit_stun_duration = float(_stat("feedback", "hit_stun_duration", hit_stun_duration))
	hit_flash_duration = float(_stat("feedback", "hit_flash_duration", hit_flash_duration))
	hit_flash_color = _stat("feedback", "hit_flash_color", hit_flash_color)
	var hit_sound_path: String = str(_stat("feedback", "hit_sound", ""))
	hit_sound = load(hit_sound_path) if hit_sound_path != "" else null

	blood_amount = int(_stat("feedback", "blood_amount", blood_amount))
	blood_color = _stat("feedback", "blood_color", blood_color)
	blood_lifetime = float(_stat("feedback", "blood_lifetime", blood_lifetime))
	blood_speed_min = float(_stat("feedback", "blood_speed_min", blood_speed_min))
	blood_speed_max = float(_stat("feedback", "blood_speed_max", blood_speed_max))


# --- Potere secondario (tasto secondary) ---
# Nel file del personaggio la sezione [secondary] collega uno script con
#     script = "res://SCRIPT/powers/xxx.gd"
# Lo script (che estende fighter_power.gd) elenca i suoi settings con i valori di
# default (default_params); qui vengono uniti a quelli scritti nel file.
# Chiavi sconosciute -> avviso; chiavi mancanti -> in debug la console stampa
# il blocco completo da incollare nel .cfg, con tutti i settings disponibili.
func _setup_secondary_power() -> void:
	var script_path: String = str(_stat("secondary", "script", ""))
	if script_path == "":
		return
	var script: GDScript = load(script_path) as GDScript
	if script == null:
		push_warning("[%s] secondary: script '%s' non trovato" % [fighter_name, script_path])
		return
	var power = script.new()
	if not power.has_method("default_params"):
		push_warning("[%s] secondary: '%s' non estende fighter_power.gd" % [fighter_name, script_path])
		return

	var cfg: ConfigFile = _fighter_cfgs[fighter_name]
	var defaults: Dictionary = power.default_params()
	var params: Dictionary = defaults.duplicate()
	if cfg.has_section("secondary"):
		for key in cfg.get_section_keys("secondary"):
			if key == "script":
				continue
			if defaults.has(key):
				params[key] = cfg.get_value("secondary", key)
			else:
				push_warning("[%s] secondary: chiave sconosciuta '%s' (settings di %s: %s)" % [fighter_name, key, script_path.get_file(), ", ".join(defaults.keys())])
	# Tutte le mosse secondarie hanno la stessa ricarica di cinque secondi.
	params["cooldown"] = 5.0

	if OS.is_debug_build() and not _power_hint_shown.has(fighter_name):
		_power_hint_shown[fighter_name] = true
		var missing: Array = []
		for key in defaults:
			if not cfg.has_section_key("secondary", key):
				missing.append("%s = %s" % [key, var_to_str(defaults[key])])
		if not missing.is_empty():
			print("[%s] settings di %s non scritti nel .cfg (uso i default). Da incollare sotto [secondary]:\n%s" % [fighter_name, script_path.get_file(), "\n".join(missing)])

	power.name = "SecondaryPower"
	add_child(power)
	power.setup(self, params)
	secondary_power = power


func _setup_deathlift_power() -> void:
	var cfg: ConfigFile = _fighter_cfgs.get(fighter_name)
	if cfg == null or not cfg.has_section("deathlift"):
		return
	var script_path := str(cfg.get_value("deathlift", "script", ""))
	var power_script := load(script_path) as GDScript
	if power_script == null:
		push_warning("[%s] deathlift: script '%s' non trovato" % [fighter_name, script_path])
		return
	var power = power_script.new()
	var values: Dictionary = power.default_params()
	for key in cfg.get_section_keys("deathlift"):
		if key != "script" and values.has(key):
			values[key] = cfg.get_value("deathlift", key)
	power.name = "DeathliftPower"
	add_child(power)
	power.setup(self, values)
	deathlift_power = power


func _deathlift_ready() -> bool:
	return deathlift_power != null and deathlift_power.can_use()


func _power_busy() -> bool:
	return (secondary_power != null and secondary_power.is_busy()) or (deathlift_power != null and deathlift_power.is_busy())


# Aggiunge/toglie stamina (clampata tra 0 e max_stamina) ed emette stamina_changed
# per la barra. Usate dal potere secondario per il costo/gate di ogni mossa
# (vedi fighter_power.gd) e da _on_damaged per il recupero sui pugni normali.
func gain_stamina(amount: float) -> void:
	if amount == 0.0:
		return
	current_stamina = clampf(current_stamina + amount, 0.0, max_stamina)
	stamina_changed.emit()


func spend_stamina(amount: float) -> void:
	gain_stamina(-amount)


func apply_poison_damage(amount: int, source: Node, aura_drain: float = 0.0) -> void:
	# Il veleno infligge danno senza spinta e prosciuga aura al primo tick.
	_suppress_next_hit_knockback = true
	hurtbox.take_damage(amount, source)
	_suppress_next_hit_knockback = false
	if aura_drain > 0.0:
		gain_stamina(-aura_drain)


func freeze_for(seconds: float) -> void:
	frozen_time_left = maxf(frozen_time_left, seconds)
	_cancel_attack()


# Altezza visibile del personaggio in pixel di mondo (serve ai poteri per scalarsi)
func get_visual_height() -> float:
	var local_y: float = maxf(absf(current_sprite.scale.y), 0.0001)
	var world_scale: float = absf(current_sprite.global_scale.y) / local_y
	return _idle_frame_height * _base_scale.y * _model_scale * world_scale


# +1 = guarda a destra, -1 = guarda a sinistra
func get_facing_dir() -> float:
	return -1.0 if current_sprite.flip_h else 1.0


func _ready() -> void:
	_setup_networking()

	hurtbox.damaged.connect(_on_damaged)

	hit_sfx.name = "HitSfx"
	hit_sfx.bus = "Master"
	add_child(hit_sfx)

	var fighters: Array = _get_fighter_names()

	for fighter in fighters:
		var sprite: AnimatedSprite2D = _get_or_build_sprite(fighter)
		sprite.visible = false
		_sprites[fighter] = sprite
		sprite.animation_finished.connect(_on_animation_finished)

		var hitbox: Hitbox = _get_or_build_hitbox(fighter, sprite)
		if hitbox:
			_set_hitbox_disabled(hitbox, true)
			hitbox.damage = attack_damage
			hitbox.source = self
		_hitboxes[fighter] = hitbox

	current_sprite = _sprites[fighter_name]
	current_sprite.visible = true

	# effetto del pugno (es. la catena di iacopo): [model] attack_fx_node, percorso relativo al modello
	var fx_path: String = str(_stat("model", "attack_fx_node", ""))
	if fx_path != "":
		chain_sprite = current_sprite.get_node_or_null(fx_path) as AnimatedSprite2D
		if chain_sprite == null:
			push_warning("[%s] attack_fx_node '%s' non trovato sotto il modello" % [fighter_name, fx_path])
		else:
			chain_sprite.visible = false
			chain_base_x = chain_sprite.position.x
			chain_sprite.animation_finished.connect(_on_chain_animation_finished)
	current_hitbox = _hitboxes[fighter_name]

	current_hitbox_shape = current_hitbox.get_node("CollisionShape2D")
	hitbox_base_x = current_hitbox_shape.position.x

	# la scala impostata in scena (es. Naka 0.74 x 0.94, Andrix 1.2 x 1.11) va
	# mantenuta: model_scale nei file .cfg la moltiplica (1.0 = misura della scena).
	# In piu' ogni animazione viene portata alla stessa dimensione dell'idle.
	_base_scale = current_sprite.scale
	_model_scale = float(_stat("model", "scale", 1.0))
	_idle_frame_height = _get_frame_height(current_sprite, &"idle", 0)
	current_sprite.animation_changed.connect(_update_sprite_scale)
	current_sprite.frame_changed.connect(_update_sprite_scale)
	_update_sprite_scale()

	# il player 2 parte specchiato: guarda a sinistra, verso il player 1
	_set_facing(player_id == 1)
	_was_on_floor = is_on_floor()

	_setup_secondary_power()
	_setup_deathlift_power()


# Altezza in pixel di un fotogramma di un'animazione (0.0 se non esiste)
func _get_frame_height(sprite: AnimatedSprite2D, anim: StringName, frame: int) -> float:
	var frames: SpriteFrames = sprite.sprite_frames
	if frames == null or not frames.has_animation(anim):
		return 0.0
	if frame < 0 or frame >= frames.get_frame_count(anim):
		return 0.0
	var tex: Texture2D = frames.get_frame_texture(anim, frame)
	return tex.get_size().y if tex != null else 0.0


# Scala dello sprite = scala della scena * model_scale * (altezza idle / altezza
# del fotogramma attuale): cosi' walk, run, hit... hanno la stessa grandezza dell'idle
func _update_sprite_scale() -> void:
	var factor: float = 1.0
	var frame_h: float = _get_frame_height(current_sprite, current_sprite.animation, current_sprite.frame)
	if frame_h > 0.0 and _idle_frame_height > 0.0:
		factor = _idle_frame_height / frame_h
	current_sprite.scale = _base_scale * _model_scale * factor
	# la hitbox e' figlia dello sprite: compensa il fattore cosi' la portata del
	# pugno non cambia quando cambia il fotogramma
	if current_hitbox != null:
		current_hitbox.scale = Vector2.ONE / factor


func _set_hitbox_disabled(hitbox: Hitbox, value: bool) -> void:
	var shape: CollisionShape2D = hitbox.get_node("CollisionShape2D")
	shape.disabled = value


# Gira il personaggio: sprite, Chain di Iacopo e hitbox del pugno
func _set_facing(left: bool) -> void:
	synced_flip_h = left
	current_sprite.flip_h = left
	if chain_sprite != null:
		chain_sprite.flip_h = left
		chain_sprite.position.x = -abs(chain_base_x) if left else abs(chain_base_x)
	current_hitbox_shape.position.x = -abs(hitbox_base_x) if left else abs(hitbox_base_x)


# --- NUOVO: helper di input, isolati per device_id (o per rete se is_networked) ---
# In rete ogni PC usa sempre lo schema "p1_*" (WASD/spazio/click) sulla
# propria tastiera: non serve più dividere la tastiera in due, ognuno ha la
# sua. Il player non locale (quello dell'altro PC, simulato dall'host) legge
# invece l'ultimo stato ricevuto via RPC (_remote_input).
func _get_direction() -> float:
	if is_bot:
		return float(_bot_input.get("dir", 0.0))
	if is_networked:
		return Input.get_axis("p1_left", "p1_right") if is_local else float(_remote_input.get("dir", 0.0))
	match device_id:
		-1:
			return Input.get_axis("p1_left", "p1_right")
		-2:
			return Input.get_axis("p2_left", "p2_right")
		_:
			# get_joy_axis() legge il valore GREZZO dello stick, senza la deadzone
			# che invece Godot applica automaticamente alle azioni (p1_left/p1_right):
			# a riposo lo stick manda comunque un po' di rumore/drift (es. 0.01-0.06,
			# a volte anche di segno opposto da un frame all'altro). Senza deadzone
			# quel rumore veniva letto come "direzione" valida: il personaggio si
			# muoveva a scatti e si girava (flip_h) ogni volta che il segno cambiava
			# ("spasmi"). Sotto JOY_DEADZONE consideriamo lo stick fermo (0.0).
			const JOY_DEADZONE := 0.25
			var v: float = Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X)
			if absf(v) < JOY_DEADZONE:
				v = 0.0
			if Engine.get_physics_frames() % 30 == 0:
				print("[DEBUG] ", name, " device_id=", device_id, " joy_axis=", v, " joypads connessi=", Input.get_connected_joypads())
			return v


func _jump_just_pressed() -> bool:
	if is_bot:
		return _bot_consume("jump")
	if is_networked:
		return Input.is_action_just_pressed("p1_jump") if is_local else _remote_consume("jump")
	match device_id:
		-1:
			return Input.is_action_just_pressed("p1_jump")
		-2:
			return Input.is_action_just_pressed("p2_jump")
		_:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)


func _attack_just_pressed() -> bool:
	if is_bot:
		return _bot_consume("attack")
	if is_networked:
		return Input.is_action_just_pressed("p1_attack") if is_local else _remote_consume("attack")
	match device_id:
		-1:
			return Input.is_action_just_pressed("p1_attack")
		-2:
			return Input.is_action_just_pressed("p2_attack")
		_:
			# Attacco da pad: sia R1 che Quadrato (JOY_BUTTON_X) devono funzionare.
			# Prima c'era solo il dorsale (R1): il Quadrato non veniva letto affatto,
			# quindi non attivava ne' l'attacco ne' (di conseguenza) la fatality,
			# che scatta sullo stesso colpo quando l'avversario e' "downed".
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_RIGHT_SHOULDER) \
				or Input.is_joy_button_pressed(device_id, JOY_BUTTON_X)


# pressione singola del tasto "secondary" (K per P1 / tastierino 2 per P2,
# p2_secondary): usata per lanciare il potere secondario, a
# differenza di _block_pressed() che invece lo legge "tenuto premuto"
func _secondary_just_pressed() -> bool:
	if is_bot:
		return _bot_consume("secondary")
	if is_networked:
		return Input.is_action_just_pressed("p1_secondary") if is_local else _remote_consume("secondary")
	match device_id:
		-1:
			return Input.is_action_just_pressed("p1_secondary")
		-2:
			return Input.is_action_just_pressed("p2_secondary")
		_:
			return false  # non ancora supportato da joypad


# ricarica stamina: tenere premuto E (P1/rete), Invio numerico (P2) o Triangolo
# (JOY_BUTTON_Y) sul pad.
func _reload_pressed() -> bool:
	if is_bot:
		return bool(_bot_input.get("reload", false))
	if is_networked:
		return (Input.is_action_pressed("p1_reload") or _any_pad_triangle()) if is_local else bool(_remote_input.get("reload", false))
	match device_id:
		-1:
			return Input.is_action_pressed("p1_reload")
		-2:
			return Input.is_action_pressed("p2_reload")
		_:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_Y)


func _any_pad_triangle() -> bool:
	for pad in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_Y):
			return true
	return false


func _is_running() -> bool:
	if is_bot:
		return bool(_bot_input.get("run", false))
	if is_networked:
		return Input.is_action_pressed("p1_run") if is_local else bool(_remote_input.get("run", false))
	match device_id:
		-1:
			return Input.is_action_pressed("p1_run")
		-2:
			return Input.is_action_pressed("p2_run")
		_:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_LEFT_SHOULDER)


# tasto "secondary" (p1_secondary / p2_secondary in project.godot): tenuto
# premuto attiva il blocco (vedi is_blocking in _physics_process)
func _block_pressed() -> bool:
	if is_bot:
		return bool(_bot_input.get("block", false))
	if is_networked:
		return Input.is_action_pressed("p1_secondary") if is_local else bool(_remote_input.get("block", false))
	match device_id:
		-1:
			return Input.is_action_pressed("p1_secondary")
		-2:
			return Input.is_action_pressed("p2_secondary")
		_:
			# Cerchio (JOY_BUTTON_B), come "parata" nello schema di Controlli
			# (controlli_manager.gd). Prima era su Quadrato (JOY_BUTTON_X), in
			# conflitto col nuovo uso di Quadrato per l'attacco pesante.
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_B)


func _bot_consume(action: String) -> bool:
	var pressed: bool = bool(_bot_input.get(action, false))
	if pressed:
		_bot_input[action] = false
	return pressed


func _bot_face_target() -> void:
	if not is_instance_valid(_bot_target) or current_sprite == null:
		return
	var offset_x: float = _bot_target.global_position.x - global_position.x
	# Una zona morta evita inversioni destra/sinistra quando i due corpi si
	# sovrappongono o si incrociano di pochi pixel.
	if absf(offset_x) > 55.0:
		_set_facing(offset_x < 0.0)


func _bot_shape_half_extents(collision: CollisionShape2D) -> Vector2:
	if collision == null or collision.shape == null:
		return Vector2.ZERO
	var scale_abs: Vector2 = collision.global_scale.abs()
	if collision.shape is RectangleShape2D:
		return (collision.shape as RectangleShape2D).size * scale_abs * 0.5
	if collision.shape is CircleShape2D:
		var radius: float = (collision.shape as CircleShape2D).radius
		return Vector2(radius * scale_abs.x, radius * scale_abs.y)
	if collision.shape is CapsuleShape2D:
		var capsule: CapsuleShape2D = collision.shape as CapsuleShape2D
		return Vector2(capsule.radius * scale_abs.x, capsule.height * scale_abs.y * 0.5)
	return Vector2.ZERO


func _bot_can_land_basic_attack(target: Player) -> bool:
	if current_hitbox_shape == null or target.hurtbox == null:
		return false
	var target_shape: CollisionShape2D = target.hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if target_shape == null:
		return false
	var attack_half: Vector2 = _bot_shape_half_extents(current_hitbox_shape)
	var target_half: Vector2 = _bot_shape_half_extents(target_shape)
	if attack_half == Vector2.ZERO or target_half == Vector2.ZERO:
		return false

	# Valuta dove saranno le hitbox quando finisce il windup, non solo la
	# distanza tra i centri dei personaggi al momento della decisione.
	var windup: float = clampf(attack_delay, 0.0, 0.7)
	var dash_time: float = minf(windup, attack_dash_duration)
	var forward_travel: float = attack_dash_speed * dash_time \
			+ attack_move_speed * maxf(windup - dash_time, 0.0)
	var attack_center: Vector2 = current_hitbox_shape.global_position \
			+ Vector2(get_facing_dir() * forward_travel, velocity.y * windup)
	var target_motion_scale: float = 0.45 if target.hurt_stun_left > 0.0 else 1.0
	var predicted_target_velocity := Vector2(
		clampf(target.velocity.x * target_motion_scale, -350.0, 350.0),
		clampf(target.velocity.y, -500.0, 500.0)
	)
	var target_center: Vector2 = target_shape.global_position + predicted_target_velocity * windup
	var combined_half: Vector2 = attack_half + target_half + Vector2(8.0, 8.0)
	return absf(attack_center.x - target_center.x) <= combined_half.x \
			and absf(attack_center.y - target_center.y) <= combined_half.y


func _bot_incoming_melee_threat(opponent: Player) -> bool:
	if not opponent.isAttacking or opponent.current_hitbox_shape == null:
		return false
	var close_enough: bool = absf(opponent.global_position.x - global_position.x) < 225.0 \
			and absf(opponent.global_position.y - global_position.y) < 175.0
	if not close_enough:
		return false
	# isAttacking copre anche windup e recupero. Schiva solo quando la hitbox
	# è già attiva o sta per attivarsi, non per tutta la durata dell'animazione.
	return not opponent.current_hitbox_shape.disabled \
			or (opponent.hitbox_delay_left > 0.0 and opponent.hitbox_delay_left <= 0.12)


func _bot_notice_opponent_action(opponent: Player) -> void:
	var turned_or_teleported: bool = _bot_has_target_sample \
			and opponent.global_position.distance_to(_bot_last_target_position) > 75.0
	_bot_last_target_position = opponent.global_position
	_bot_has_target_sample = true
	var power_busy: bool = opponent.secondary_power != null and opponent.secondary_power.is_busy()
	var power_cooldown: float = -1.0
	if opponent.secondary_power != null:
		power_cooldown = float(opponent.secondary_power.cooldown_left)
	var power_started: bool = (power_busy and not _bot_opponent_power_was_busy) \
			or (power_cooldown >= 0.0 and _bot_last_opponent_power_cooldown >= 0.0 \
			and power_cooldown > _bot_last_opponent_power_cooldown + 0.15)
	if turned_or_teleported or power_started:
		# Reagisce alla posizione nuova (teletrasporti inclusi) e interrompe
		# l'attesa passiva per provare a punire l'avvio di una secondaria.
		_set_facing(opponent.global_position.x < global_position.x)
		_bot_attack_left = minf(_bot_attack_left, 0.08)
	_bot_opponent_power_was_busy = power_busy
	_bot_last_opponent_power_cooldown = power_cooldown


func _bot_projectile_source(projectile: Node) -> Node:
	for property: Dictionary in projectile.get_property_list():
		var property_name: String = str(property.get("name", ""))
		if property_name == "source" or property_name == "owner_player":
			return projectile.get(property_name) as Node
	return null


func _bot_projectile_velocity(projectile: Node2D) -> Vector2:
	if projectile.has_meta("vel"):
		var velocity_from_meta: Vector2 = projectile.get_meta("vel", Vector2.ZERO)
		return velocity_from_meta
	var has_direction := false
	var has_speed := false
	for property: Dictionary in projectile.get_property_list():
		var property_name: String = str(property.get("name", ""))
		has_direction = has_direction or property_name == "direction"
		has_speed = has_speed or property_name == "speed"
	if has_direction and has_speed:
		return Vector2(float(projectile.get("direction")) * float(projectile.get("speed")), 0.0)
	if projectile.name == "PerucxFallingTennisBall":
		return Vector2.DOWN * 220.0
	return Vector2.ZERO


func _bot_evade_hazards(opponent: Player) -> bool:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return false
	for hazard_node: Node in scene.find_children("PoisonArea", "Area2D", true, false):
		var hazard: Area2D = hazard_node as Area2D
		if hazard == null or int(hazard.get_meta("source_player_id", -1)) != opponent.player_id:
			continue
		var collision: CollisionShape2D = hazard.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision == null or not (collision.shape is CircleShape2D):
			continue
		var radius: float = (collision.shape as CircleShape2D).radius * absf(hazard.global_scale.x)
		var separation: Vector2 = global_position - collision.global_position
		if separation.length() <= radius + 95.0:
			_bot_evade_direction = signf(separation.x)
			if _bot_evade_direction == 0.0:
				_bot_evade_direction = -opponent.get_facing_dir()
			_bot_begin_dodge()
			return true

		# Una nube lontana o alle spalle non deve congelare il bot. La tratta
		# solo come barriera se si trova davvero fra lui e l'avversario.
		var toward_target: float = signf(opponent.global_position.x - global_position.x)
		var hazard_x: float = collision.global_position.x - global_position.x
		var blocks_route: bool = toward_target != 0.0 \
				and signf(hazard_x) == toward_target \
				and absf(hazard_x) < absf(opponent.global_position.x - global_position.x) + radius \
				and absf(separation.y) < radius + 120.0
		if blocks_route:
			# Se può colpire dalla distanza, lo fa restando fuori dalla nube;
			# altrimenti aspetta che la barriera sparisca.
			_bot_input["dir"] = 0.0
			_bot_input["attack"] = false
			_bot_attack_left = maxf(_bot_attack_left, 0.35)
			_set_facing(opponent.global_position.x < global_position.x)
			_bot_use_secondary_at_range(global_position.distance_to(opponent.global_position))
			return true

	for chain_node: Node in scene.find_children("BigChain", "Area2D", true, false):
		var chain: Area2D = chain_node as Area2D
		var chain_state: String = str(chain.get_meta("state", "")) if chain != null else ""
		if chain == null or chain.get("source") != opponent \
				or chain_state not in ["spawning", "travel"]:
			continue
		var chain_direction: float = float(chain.get_meta("dir", 0.0))
		var to_bot: Vector2 = global_position - chain.global_position
		var ahead_distance: float = to_bot.x * chain_direction
		var warning_distance: float = 270.0 if chain_state == "spawning" else 440.0
		if ahead_distance > 0.0 and ahead_distance < warning_distance and absf(to_bot.y) < 150.0:
			_bot_evade_direction = -chain_direction
			_bot_begin_dodge()
			return true

	# Hitbox persistenti e aree di controllo (per esempio la colonna caricata
	# di Iacopo) non viaggiano come proiettili: reagisce alla loro forma attiva.
	var own_hurt_shape: CollisionShape2D = hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var own_half: Vector2 = _bot_shape_half_extents(own_hurt_shape)
	for area_node: Node in scene.find_children("*", "Area2D", true, false):
		var area: Area2D = area_node as Area2D
		if area == null or _bot_projectile_source(area) != opponent:
			continue
		var shape: CollisionShape2D = area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape == null or shape.disabled:
			continue
		var hazard_half: Vector2 = _bot_shape_half_extents(shape)
		var separation: Vector2 = global_position - shape.global_position
		if absf(separation.x) <= hazard_half.x + own_half.x + 70.0 \
				and absf(separation.y) <= hazard_half.y + own_half.y + 55.0:
			_bot_evade_direction = signf(separation.x)
			if _bot_evade_direction == 0.0:
				_bot_evade_direction = -opponent.get_facing_dir()
			_bot_begin_dodge()
			return true

	# Tutte le secondarie che materializzano un proiettile condividono questo
	# controllo: pallone, coltelli, palline e futuri proiettili con source + vel.
	var projectile_nodes: Array[Node] = scene.find_children("*", "Area2D", true, false)
	projectile_nodes.append_array(scene.find_children("SoccerBallProjectile", "Node2D", true, false))
	for projectile_node: Node in projectile_nodes:
		var projectile: Node2D = projectile_node as Node2D
		if projectile == null or projectile == self or _bot_projectile_source(projectile) != opponent:
			continue
		var velocity: Vector2 = _bot_projectile_velocity(projectile)
		if velocity.length_squared() <= 0.0:
			continue
		var to_bot: Vector2 = global_position - projectile.global_position
		var along_path: float = to_bot.dot(velocity.normalized())
		var distance_from_path: float = absf(to_bot.cross(velocity.normalized()))
		if along_path > 0.0 and along_path < 520.0 and distance_from_path < 110.0:
			_bot_evade_direction = -signf(velocity.x)
			if _bot_evade_direction == 0.0:
				_bot_evade_direction = -signf(opponent.global_position.x - global_position.x)
			_bot_begin_dodge()
			return true
	return false


func _bot_begin_dodge() -> void:
	_bot_input["dir"] = _bot_evade_direction
	_bot_attack_left = maxf(_bot_attack_left, 0.45)
	if is_on_floor() and _bot_jump_left <= 0.0:
		_bot_input["jump"] = true
		_bot_jump_left = _bot_rng.randf_range(0.8, 1.2)


func _bot_secondary_range() -> Vector2:
	if secondary_power == null:
		return Vector2.ZERO
	var script: Script = secondary_power.get_script() as Script
	var script_name: String = script.resource_path.get_file() if script != null else ""
	match script_name:
		"chain_power.gd", "chain_power_charged.gd":
			return Vector2(170.0, 900.0)
		"knife_power.gd", "andrix_madonnina.gd":
			return Vector2(200.0, 850.0)
		"perux_ambush.gd":
			return Vector2(250.0, 650.0)
		"perux_charged.gd":
			return Vector2(250.0, 850.0)
		"mencu_airstrike.gd":
			return Vector2(0.0, float(secondary_power.params.get("blast_radius", 420.0)))
		"nakakata_shadow_strike.gd":
			return Vector2(0.0, 1600.0)
		"trab_headbutt.gd":
			return Vector2(220.0, 950.0)
		_:
			return Vector2(150.0, 420.0)


func _bot_should_use_secondary(distance_x: float) -> bool:
	if secondary_power == null or not secondary_power.can_use():
		return false
	var useful_range: Vector2 = _bot_secondary_range()
	return distance_x >= useful_range.x and distance_x <= useful_range.y


func _bot_stamina_goal() -> float:
	if secondary_power == null:
		return max_stamina
	var power_params: Dictionary = secondary_power.params
	if secondary_power.has_method("is_deadlift") and bool(secondary_power.call("is_deadlift")):
		return max_stamina * float(power_params.get("aura_ratio_required", 1.0))
	var target_distance: float = INF
	if is_instance_valid(_bot_target):
		target_distance = absf(global_position.x - _bot_target.global_position.x)
	if secondary_power.has_charged_attack() and _bot_charge_opportunity(target_distance):
		var charged_cost: float = _bot_charged_stamina_cost()
		if charged_cost > 0.0:
			return minf(max_stamina, charged_cost + 5.0)
	var minimum: float = maxf(
		float(power_params.get("stamina_min", 0.0)),
		float(power_params.get("stamina_cost", 0.0))
	)
	return minf(max_stamina, minimum + 5.0)


func _bot_situation_favors_power() -> bool:
	if not is_instance_valid(_bot_target) or max_health <= 0 or _bot_target.max_health <= 0:
		return false
	var my_health: float = float(current_health) / float(max_health)
	var their_health: float = float(_bot_target.current_health) / float(_bot_target.max_health)
	var losing: bool = my_health <= 0.35 or my_health < their_health - 0.18
	var far_ahead: bool = my_health >= 0.65 and my_health > their_health + 0.30
	return losing or far_ahead


func _bot_charged_stamina_cost() -> float:
	if secondary_power == null:
		return 0.0
	var power_params: Dictionary = secondary_power.params
	var script: Script = secondary_power.get_script() as Script
	var script_name: String = script.resource_path.get_file() if script != null else ""
	match script_name:
		"chain_power_charged.gd":
			return float(power_params.get("charge_stamina_cost", power_params.get("charge_stamina_min", 0.0)))
		"perux_charged.gd":
			return max_stamina
		"andrix_madonnina.gd":
			return float(power_params.get("madonna_stamina_cost", power_params.get("madonna_stamina_min", 0.0)))
		_:
			return float(power_params.get("stamina_cost", 0.0))


func _bot_charge_opportunity(distance_x: float) -> bool:
	if secondary_power == null or not secondary_power.has_charged_attack() \
			or not is_instance_valid(_bot_target) \
			or secondary_power.cooldown_left > 0.0 or secondary_power.is_busy():
		return false
	var useful_range: Vector2 = _bot_secondary_range()
	if distance_x < useful_range.x or distance_x > useful_range.y:
		return false
	var script: Script = secondary_power.get_script() as Script
	var script_name: String = script.resource_path.get_file() if script != null else ""
	if script_name == "chain_power_charged.gd":
		var pointer_limit: float = float(secondary_power.params.get("pointer_max_distance", 500.0))
		if distance_x > pointer_limit + 80.0:
			return false
	var opponent_power_busy: bool = _bot_target.secondary_power != null \
			and _bot_target.secondary_power.is_busy()
	var safe_to_charge: bool = _bot_target.isHurt or _bot_target.is_blocking \
			or (distance_x > 260.0 and not opponent_power_busy \
			and not _bot_incoming_melee_threat(_bot_target))
	# Le cariche diventano una scelta normale nelle finestre sicure, con priorità
	# maggiore quando il bot sta perdendo o ha un vantaggio netto.
	var good_opportunity: bool = _bot_situation_favors_power() \
			or _bot_target.isHurt or _bot_target.is_blocking or distance_x > 350.0
	return safe_to_charge and good_opportunity


func _bot_should_charge_secondary(distance_x: float) -> bool:
	return _bot_charge_opportunity(distance_x) \
			and current_stamina >= _bot_charged_stamina_cost()


func _bot_is_ready_deathlift(distance_x: float) -> bool:
	return secondary_power != null \
			and secondary_power.has_method("is_deadlift") \
			and bool(secondary_power.call("is_deadlift")) \
			and _bot_should_use_secondary(distance_x)


func _bot_charged_extra_hold(distance_x: float) -> float:
	var script: Script = secondary_power.get_script() as Script
	var script_name: String = script.resource_path.get_file() if script != null else ""
	if script_name == "chain_power_charged.gd":
		var speed: float = maxf(float(secondary_power.params.get("pointer_speed", 300.0)), 1.0)
		return clampf((distance_x - 160.0) / speed, 0.15, 0.8)
	if script_name == "andrix_madonnina.gd":
		return 0.1
	return 0.15


func _bot_use_secondary_at_range(distance_x: float) -> void:
	if secondary_power == null or not is_on_floor() or not _bot_should_use_secondary(distance_x):
		return
	if secondary_power.has_charged_attack():
		if not _bot_charge_active:
			_bot_charge_active = true
			_bot_charge_left = 0.0
			if _bot_should_charge_secondary(distance_x):
				_bot_charge_extra_hold = _bot_charged_extra_hold(distance_x)
				_bot_charge_hold_limit = secondary_power.charge_time() + _bot_charge_extra_hold + 0.03
			else:
				_bot_charge_extra_hold = 0.0
				_bot_charge_hold_limit = 0.05
			_bot_input["block"] = true
	else:
		_bot_input["secondary"] = true


func _update_bot_ai(delta: float) -> void:
	if not is_bot:
		return
	_bot_attack_left = maxf(_bot_attack_left - delta, 0.0)
	_bot_jump_left = maxf(_bot_jump_left - delta, 0.0)
	if _bot_charge_active:
		# Il bot usa il tocco rapido delle mosse caricabili: tenerle cariche lo
		# immobilizzava a lungo. Carica solo quando la situazione e la stamina
		# giustificano il rischio; altrimenti rilascia subito la mossa rapida.
		if _secondary_charging:
			_bot_charge_left += delta
			_bot_input["block"] = _bot_charge_left < _bot_charge_extra_hold
		else:
			_bot_input["block"] = _secondary_hold_time < _bot_charge_hold_limit
		if not bool(_bot_input["block"]):
			_bot_charge_active = false
	else:
		_bot_input["block"] = false
	_bot_think_left -= delta
	if _bot_think_left > 0.0:
		return
	_bot_think_left = 0.10
	_bot_input["jump"] = false
	_bot_input["attack"] = false
	_bot_input["secondary"] = false
	_bot_input["reload"] = false
	_bot_input["run"] = false

	_bot_target = null
	var closest_distance: float = INF
	for candidate: Node in get_tree().get_nodes_in_group("players"):
		if candidate is Player and candidate != self and not candidate.is_dead and candidate.current_health > 0:
			var distance: float = global_position.distance_squared_to(candidate.global_position)
			if distance < closest_distance:
				_bot_target = candidate
				closest_distance = distance
	if not is_instance_valid(_bot_target):
		_bot_input["dir"] = 0.0
		return

	# Quando l'avversario è a terra, il bot tenta direttamente la fatality cinematografica.
	if _bot_target.is_downed and FatalityManager.is_player_downed(_bot_target.player_id) and GameState.gore_enabled:
		FatalityManager.trigger_fatality(self, _bot_target)
		return

	var delta_x: float = _bot_target.global_position.x - global_position.x
	var distance_x: float = absf(delta_x)
	var toward: float = signf(delta_x)
	if toward == 0.0:
		toward = get_facing_dir()
	_bot_notice_opponent_action(_bot_target)
	# Il facing deve essere corretto prima di innescare un attacco o un potere:
	# la direzione di movimento viene applicata più avanti nella fisica.
	_bot_face_target()
	if _bot_evade_hazards(_bot_target):
		return
	if _bot_hit_reaction_left > 0.0:
		_bot_input["dir"] = -toward
		_bot_input["run"] = distance_x > 180.0 and can_run
		_bot_input["attack"] = false
		_bot_input["secondary"] = false
		return
	var direction: float = 0.0
	var evading_melee: bool = _bot_incoming_melee_threat(_bot_target)
	if evading_melee and _bot_jump_left <= 0.0 and is_on_floor():
		direction = -toward
		_bot_input["jump"] = true
		_bot_jump_left = _bot_rng.randf_range(0.7, 1.2)
	elif evading_melee:
		direction = -toward
	var can_land_basic: bool = _bot_can_land_basic_attack(_bot_target)
	if not evading_melee:
		# Avanza finché la hitbox non può raggiungere il bersaglio. Non usare una
		# soglia di distanza arbitraria: cambia molto tra i personaggi.
		direction = 0.0 if can_land_basic else toward
	_bot_input["dir"] = direction
	_bot_input["run"] = can_run and distance_x > 300.0
	if evading_melee:
		return

	# Ricarica solo quando c'e' spazio e l'avversario non sta iniziando un attacco.
	var stamina_goal: float = _bot_stamina_goal()
	var reload_distance: float = 260.0 if _bot_charge_opportunity(distance_x) else 300.0
	if current_stamina + 1.0 < stamina_goal and distance_x > reload_distance \
			and not _bot_incoming_melee_threat(_bot_target) and is_on_floor():
		_bot_input["reload"] = true
		return

	var deadlift_ready: bool = _bot_is_ready_deathlift(distance_x)
	var charged_ready: bool = _bot_should_charge_secondary(distance_x)
	var choose_secondary: bool = is_on_floor() and _bot_should_use_secondary(distance_x) \
			and (deadlift_ready or charged_ready or _bot_target.is_blocking or not can_land_basic)
	if not choose_secondary and _bot_attack_left <= 0.0 and not isAttacking and can_land_basic:
		_bot_input["attack"] = true
		_bot_input["dir"] = 0.0
		_bot_face_target()
		# Pressa più velocemente quando l'avversario è vulnerabile; mantiene una
		# pausa breve tra i colpi quando entrambi sono ancora in piedi e attivi.
		_bot_attack_left = _bot_rng.randf_range(0.28, 0.44) if _bot_target.isHurt \
				else _bot_rng.randf_range(0.42, 0.68)

	if choose_secondary:
		_bot_use_secondary_at_range(distance_x)
		_bot_input["attack"] = false
	if _bot_charge_active:
		return


# Gestisce il tasto "secondary" per i poteri con attacco caricato (vedi
# fighter_power.has_charged_attack()): tenuto premuto oltre charge_time() secondi
# avvia la carica (start_charge/update_charge); il rilascio la conclude
# (release_charge). Un tocco più breve della soglia resta un uso normale
# del potere (use()), come per i poteri senza carica.
func _update_charged_secondary(delta: float) -> void:
	var held: bool = _block_pressed()  # stesso tasto del blocco, letto "tenuto premuto"

	if held:
		_secondary_hold_time += delta
		if _secondary_charging:
			secondary_power.update_charge(delta)
		elif _secondary_hold_time >= secondary_power.charge_time() and is_on_floor() \
				and not isAttacking and secondary_power.can_use():
			_secondary_charging = secondary_power.start_charge()  # puo' fallire (es. stamina): si ritenta ogni frame
		if _secondary_charging:
			_play_power_trail()
	else:
		if _secondary_charging:
			_secondary_charging = false
			if _deathlift_ready():
				deathlift_power.use()
			else:
				secondary_power.release_charge()
		elif _secondary_hold_time > 0.0 and is_on_floor() and not isAttacking:
			if _deathlift_ready():
				deathlift_power.use()
			elif secondary_power.can_use():
				secondary_power.use()
				_play_power_trail()
		_secondary_hold_time = 0.0


func intro_display_name() -> String:
	match fighter_name.to_lower():
		"trab": return "Trab"
		"iacopo", "iacobisio": return "Iacobisio"
		"naka", "nakakata", "maestro_nakakata": return "Maestro Nakakata"
		"andrix": return "Andrix"
	return str(_stat("character", "display_name", fighter_name))

func intro_focus_offset() -> Vector2:
	return Vector2(0.0, -get_visual_height() * 0.27)
func intro_duration() -> float:
	return maxf(float(_stat("cinematic", "intro_seconds", 1.1)), 0.2)
func intro_zoom() -> float:
	return clampf(float(_stat("cinematic", "intro_zoom", 3.0)), 1.2, 3.6)
func play_intro_pose() -> void:
	var anim := StringName(str(_stat("cinematic", "intro_animation", "hit")))
	var frames: SpriteFrames = current_sprite.sprite_frames
	if frames == null or not frames.has_animation(anim):
		anim = &"taunt" if frames != null and frames.has_animation("taunt") else (&"hit" if frames != null and frames.has_animation("hit") else &"idle")
	current_sprite.play(anim)
	synced_animation = String(anim)
func _spawn_afterimage(tint: Color) -> void:
	if not GameState.visual_effects:
		return
	var source: AnimatedSprite2D = chain_sprite if chain_sprite != null and chain_sprite.visible else current_sprite
	if source == null or source.sprite_frames == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = source.sprite_frames.get_frame_texture(source.animation, source.frame)
	if ghost.texture == null:
		return
	ghost.flip_h = source.flip_h
	ghost.scale = source.global_scale
	ghost.modulate = tint
	ghost.z_index = source.z_index - 1
	get_tree().current_scene.add_child(ghost)
	ghost.global_position = source.global_position - Vector2(get_facing_dir() * 9.0, 0.0)
	var tw := ghost.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "modulate:a", 0.0, 0.16)
	tw.tween_property(ghost, "position:x", ghost.position.x - get_facing_dir() * 12.0, 0.16)
	tw.chain().tween_callback(ghost.queue_free)
func _play_attack_trail() -> void:
	while isAttacking and is_inside_tree():
		if not GameState.visual_effects:
			return
		_spawn_afterimage(Color(0.55, 0.88, 1.0, 0.42))
		await get_tree().create_timer(0.055).timeout
func _play_power_trail() -> void:
	for i in range(5):
		if not is_inside_tree() or not GameState.visual_effects:
			return
		_spawn_afterimage(Color(0.82, 0.58, 1.0, 0.4))
		await get_tree().create_timer(0.045).timeout
func _spawn_burst(point: Vector2, tint: Color, count: int, speed_min: float, speed_max: float, life: float) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = life
	p.local_coords = false
	p.direction = Vector2(0.0, -0.35)
	p.spread = 75.0
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.gravity = Vector2(0.0, 65.0)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 4.0
	p.color = tint
	p.z_index = 14
	var gr := Gradient.new()
	gr.set_color(0, Color.WHITE)
	gr.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = gr
	get_tree().current_scene.add_child(p)
	p.global_position = point
	p.restart()
	get_tree().create_timer(life + 0.15).timeout.connect(p.queue_free)
func _spawn_impact_sparks(blocked: bool) -> void:
	if not GameState.visual_effects:
		return
	var tint := Color(0.35, 0.85, 1.0, 1.0) if blocked else Color(1.0, 0.72, 0.2, 1.0)
	_spawn_burst(hurtbox.global_position, tint, 7 if blocked else 14, 90.0 if blocked else 150.0, 230.0 if blocked else 360.0, 0.22)
func _spawn_landing_dust() -> void:
	if not GameState.visual_effects:
		return
	_spawn_burst(global_position + Vector2(0, 26), Color(0.72, 0.68, 0.62, 0.55), 8, 20.0, 65.0, 0.28)
	var rot := current_sprite.rotation
	current_sprite.rotation -= 0.07
	current_sprite.create_tween().tween_property(current_sprite, "rotation", rot, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
func _physics_process(delta: float) -> void:
	if Engine.get_physics_frames() % 30 == 0:
		print("[DEBUG] ", name, " player_id=", player_id, " device_id=", device_id, " combat_locked=", combat_locked, " is_dead=", is_dead, " is_networked=", is_networked)
	if is_dead:
		return
	if intro_locked:
		if is_networked and not is_multiplayer_authority():
			return
		if not is_on_floor():
			velocity += get_gravity() * delta
		velocity.x = 0.0
		move_and_slide()
		return
	if combat_locked:
		return  # fatality: blocca input e fisica
	if is_networked:
		if is_local:
			_send_local_input()
		if not is_multiplayer_authority():
			return  # il client non simula: aspetta la posizione sincronizzata dall'host

	if frozen_time_left > 0.0:
		frozen_time_left = maxf(frozen_time_left - delta, 0.0)
		velocity = Vector2.ZERO
		is_blocking = false
		is_reloading = false
		if current_sprite.sprite_frames.has_animation("idle"):
			current_sprite.play("idle")
			synced_animation = "idle"
		return

	if is_bot:
		_bot_hit_reaction_left = maxf(_bot_hit_reaction_left - delta, 0.0)

	if not is_on_floor():
		velocity += get_gravity() * delta

	# stordimento da colpo subito: durante hurt_stun_left il player non
	# risponde ai comandi, ma gravita' e rinculo continuano normalmente
	if hurt_stun_left > 0.0:
		hurt_stun_left = maxf(hurt_stun_left - delta, 0.0)
		isHurt = hurt_stun_left > 0.0
		velocity.x = move_toward(velocity.x, 0, hit_knockback * delta * 2.0)
		move_and_slide()
		return

	_update_bot_ai(delta)

	# ricarica stamina: tenendo premuto E / Triangolo si recupera stamina, ma il
	# player resta fermo (niente movimento, salto, attacco o poteri) finche' dura
	is_reloading = _reload_pressed() and is_on_floor() and not isAttacking \
			and not _power_busy() and current_stamina < max_stamina
	if is_reloading:
		is_blocking = false
		_secondary_hold_time = 0.0
		gain_stamina(stamina_reload_rate * delta)
		velocity.x = 0.0
		current_sprite.play("idle")
		synced_animation = "idle"
		move_and_slide()
		return

	# potere secondario (se il personaggio ne ha uno in [secondary]).
	# Due modalità, decise dal potere stesso (has_charged_attack()):
	#  - normale: un tocco del tasto "secondary" lo lancia subito
	#  - caricato: tenendo premuto "secondary" oltre charge_time() secondi parte
	#    la carica (es. il pointer di Bisio); un rilascio più rapido della soglia
	#    resta un tocco normale. Per questi poteri il blocco viene disattivato:
	#    lo stesso tasto serve per mirare/rilasciare (vedi _update_charged_secondary)
	var chargeable: bool = secondary_power != null and secondary_power.has_charged_attack()
	if chargeable:
		_update_charged_secondary(delta)
	elif secondary_power != null and _secondary_just_pressed() and is_on_floor() \
			and not isAttacking and (secondary_power.can_use() or _deathlift_ready()):
		if _deathlift_ready():
			deathlift_power.use()
		else:
			secondary_power.use()
		_play_power_trail()
	var power_busy: bool = _power_busy()

	# blocco: tenendo "secondary" fermi, non si può attaccare né saltare
	# (non si può iniziare a bloccare a metà di un attacco o del potere secondario)
	is_blocking = not chargeable and _block_pressed() and is_on_floor() and not isAttacking and not power_busy

	if not is_blocking and not power_busy:
		if _jump_just_pressed() and is_on_floor():
			velocity.y = jump_velocity

		if _attack_just_pressed():
			attack()

	# la hitbox si attiva solo quando scade il ritardo dell'attacco
	if hitbox_delay_left > 0.0:
		hitbox_delay_left -= delta
		if hitbox_delay_left <= 0.0 and isAttacking:
			_set_hitbox_disabled(current_hitbox, false)

	# chi ha can_run = false nel suo .cfg non può correre
	var is_running: bool = _is_running() and can_run
	var current_speed: float = run_speed if is_running else speed

	# stamina: NON si recupera piu' nel tempo, si ricarica tenendo premuto E / Triangolo
	# (vedi blocco is_reloading sopra). Il consumo e' nel potere: fighter_power.gd use()/start_charge()

	if isAttacking:
		current_speed = attack_move_speed
	elif power_busy:
		current_speed = 0.0  # fermo mentre lancia il potere secondario

	# mentre si blocca o si lancia il potere secondario si resta fermi sul posto
	var direction := 0.0 if (is_blocking or power_busy) else _get_direction()

	if direction:
		velocity.x = direction * current_speed
		if is_bot and is_instance_valid(_bot_target):
			_bot_face_target()
		else:
			_set_facing(direction < 0)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)

	if _attack_dash_left > 0.0:
		_attack_dash_left = maxf(_attack_dash_left - delta, 0.0)
		velocity.x = get_facing_dir() * attack_dash_speed

	if not isAttacking and not power_busy:
		if direction:
			if is_running:
				current_sprite.play("run")
				synced_animation = "run"
			else:
				current_sprite.play("walk")
				synced_animation = "walk"
		else:
			current_sprite.play("idle")
			synced_animation = "idle"

	if is_running and direction != 0.0:
		_run_trail_clock -= delta
		if _run_trail_clock <= 0.0:
			_spawn_afterimage(Color(0.68, 0.84, 1.0, 0.24))
			_run_trail_clock = 0.11
	else:
		_run_trail_clock = 0.0
	move_and_slide()
	var floor_now := is_on_floor()
	if not _was_on_floor and floor_now:
		_spawn_landing_dust()
	_was_on_floor = floor_now
	
	


func attack() -> void:
	if isAttacking or is_dead:
		return
	var windup := maxf(float(_stat("cinematic", "attack_windup", 0.07)), 0.0)
	if windup > 0.0:
		current_sprite.rotation = -get_facing_dir() * 0.06
		current_sprite.create_tween().tween_property(current_sprite, "rotation", 0.0, windup).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	isAttacking = true
	_attack_dash_left = attack_dash_duration
	if current_sprite.sprite_frames == null or not current_sprite.sprite_frames.has_animation(_current_attack_animation):
		_current_attack_animation = "hit"
	synced_animation = _current_attack_animation

	current_hitbox.reset_hits()
	if attack_delay <= 0.0:
		_set_hitbox_disabled(current_hitbox, false)
	else:
		hitbox_delay_left = attack_delay

	if chain_sprite != null:
		chain_sprite.visible = true
		chain_sprite.play("hit")
	else:
		current_sprite.play(_current_attack_animation)
	_play_attack_trail()

func _on_animation_finished() -> void:
	if current_sprite.animation == _current_attack_animation:
		isAttacking = false
		hitbox_delay_left = 0.0
		_set_hitbox_disabled(current_hitbox, true)


func _on_chain_animation_finished() -> void:
	if chain_sprite.animation == "hit":
		isAttacking = false
		hitbox_delay_left = 0.0
		chain_sprite.visible = false
		_set_hitbox_disabled(current_hitbox, true)


func _on_damaged(amount: int, source: Node) -> void:
	if is_networked and not is_multiplayer_authority():
		return  # in rete solo l'host applica i danni: il client vede solo il risultato sincronizzato
	if source == self or current_health <= 0 or is_dead:
		return  # un player non può colpire se stesso, né essere colpito da morto

	if combat_locked:
		# in corso una cinematica fatality: niente danno va processato finche' non
		# finisce, altrimenti un'arma "persistente" ancora attiva (es. la colonna
		# del potere caricato di Iacopo, che resta a contatto e continua a
		# collidere ogni frame anche mentre i player sono bloccati) rimetteva
		# ogni volta la vittima in stato "downed" e poteva far scattare una
		# SECONDA cinematica fatality mentre la prima era ancora in corso.
		return

	if is_downed:
		# Non fidarti solo del flag locale: se FatalityManager non ci considera
		# (piu') "downed" (vedi clear_downed(), chiamato da _load_stats()),
		# questo e' un residuo di un round precedente rimasto agganciato
		# (es. livello che resetta l'HP a mano senza richiamare _load_stats()).
		# In quel caso lo puliamo qui e il colpo viene trattato come danno
		# normale, invece di scatenare subito una fatality indesiderata.
		if not FatalityManager.is_player_downed(player_id):
			is_downed = false
		else:
			# e' gia' all'HP minimo, in attesa del colpo di grazia: un colpo qualsiasi la finisce
			# (vedi FatalityManager.settings.any_hit_finishes). Niente danno da calcolare: parte
			# direttamente la cinematica, che a fine sequenza emette "died" come faceva questo script prima.
			gain_stamina(-aura_loss_on_hit)
			_play_hit_feedback(source, false)
			FatalityManager.downed_player_hit(self, source)
			return

	# bloccando si subisce solo una frazione del danno (block_damage_reduction)
	var applied_damage: int = amount
	if is_blocking:
		applied_damage = int(round(amount * block_damage_reduction))

	var downed_health: int = FatalityManager.settings.downed_health if FatalityManager.settings else 1
	var would_be_health: int = current_health - applied_damage

	gain_stamina(-aura_loss_on_hit)

	if would_be_health <= 0:
		# invece di morire subito, si ferma all'HP minimo e diventa "downed":
		# serve il colpo di grazia (altro colpo, o la combo fatality dell'avversario) per finirla.
		current_health = maxi(downed_health, 1)
		health_changed.emit()
		_play_hit_feedback(source, is_blocking)
		is_downed = true
		FatalityManager.mark_downed(self, source)
		return

	current_health = would_be_health
	health_changed.emit()  # aggiorna la barra vita

	# il pugno normale (non un potere) va a segno: un po' di stamina a chi ha colpito
	# (source.isAttacking e' vero solo durante la hitbox del pugno base, non dei poteri)
	if source is Player and source != self and source.isAttacking:
		source.gain_stamina(source.stamina_hit_gain)

	_play_hit_feedback(source, is_blocking)


# Rinculo + stordimento breve + lampo sullo sprite + suono d'impatto.
# Se il colpo e' stato bloccato: rinculo ridotto e niente stordimento.
func _play_hit_feedback(source: Node, blocked: bool) -> void:
	# direzione della spinta = lontano da chi ha colpito
	var push_dir: float = 1.0 if current_sprite.flip_h else -1.0
	if source is Node2D and not _suppress_next_hit_knockback:
		var d: float = signf(global_position.x - source.global_position.x)
		if d != 0.0:
			push_dir = d
		var shove_force: float = source.attack_knockback if source is Player else hit_knockback
		velocity.x = push_dir * shove_force * (0.4 if blocked else 1.0)

	if is_bot:
		# Svuota i comandi accumulati prima del colpo. Finito lo stun, il bot
		# prima si disimpegna e poi rivaluta la situazione invece di ripartire
		# verso la hitbox con il vecchio comando d'attacco.
		_bot_hit_reaction_left = maxf(_bot_hit_reaction_left, 0.3 if blocked else 0.6)
		_bot_attack_left = maxf(_bot_attack_left, 0.8)
		_bot_charge_active = false
		_bot_charge_left = 0.0
		for action: String in ["attack", "secondary", "jump", "reload", "run", "block"]:
			_bot_input[action] = false
		_bot_input["dir"] = 0.0

	if not blocked:
		hurt_stun_left = hit_stun_duration
		isHurt = true
		_cancel_attack()  # il colpo subito interrompe il pugno in corso
		_play_hurt_animation()

	if GameState.visual_effects:
		_flash_sprite()
	_spawn_impact_sparks(blocked)
	var camera := get_viewport().get_camera_2d()
	if GameState.visual_effects and camera and camera.has_method("shake"):
		camera.shake(3.0 if blocked else 7.0, 0.12 if blocked else 0.18)
	if GameState.visual_effects:
		_play_impact_squash(blocked)
	_spawn_blood(push_dir, blocked)

	if hit_sound:
		hit_sfx.stream = hit_sound
		hit_sfx.play()


# Interrompe l'attacco in corso (senza questo, se "hurt" sostituisce l'animazione
# "hit" a meta', animation_finished non arriva e isAttacking resterebbe true per sempre)
func _cancel_attack() -> void:
	if secondary_power != null:
		secondary_power.on_player_hit()  # es. la catena in spawn si ritira, o la carica si annulla
	_secondary_charging = false
	_secondary_hold_time = 0.0

	if not isAttacking:
		return
	isAttacking = false
	hitbox_delay_left = 0.0
	_set_hitbox_disabled(current_hitbox, true)
	if chain_sprite != null and chain_sprite.visible:
		chain_sprite.stop()
		chain_sprite.visible = false


# Animazione "hurt": se lo sprite del personaggio non ce l'ha ancora, viene saltata
# (resta il lampo rosso) senza errori
func _play_hurt_animation() -> void:
	var frames: SpriteFrames = current_sprite.sprite_frames
	if frames == null or not frames.has_animation("hurt"):
		return
	current_sprite.stop()  # riparte da capo anche se si viene colpiti di nuovo
	current_sprite.play("hurt")
	synced_animation = "hurt"


# Schizzi di sangue: particelle rosse che partono dal punto colpito, spinte via
# da chi ha colpito e poi cadono per gravita'. Bloccando ne escono meno.
func _spawn_blood(push_dir: float, blocked: bool) -> void:
	if not GameState.gore_enabled or blood_amount <= 0:
		return
	var amount: int = maxi(int(round(blood_amount * (0.3 if blocked else 1.0))), 1)

	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = blood_lifetime
	p.local_coords = false  # le particelle restano nel mondo, non seguono il player
	p.direction = Vector2(push_dir, -0.6)
	p.spread = 55.0
	p.initial_velocity_min = blood_speed_min
	p.initial_velocity_max = blood_speed_max
	p.gravity = Vector2(0, 600)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.color = blood_color
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.z_index = 10

	# aggiunta alla scena (non al player) cosi' non viene girata/scalata con lo sprite
	get_parent().add_child(p)
	p.global_position = hurtbox.global_position  # punto colpito (torace)
	p.restart()
	get_tree().create_timer(blood_lifetime + 0.2).timeout.connect(p.queue_free)


func _play_impact_squash(blocked: bool) -> void:
	var original_scale := current_sprite.scale
	var factor := 1.04 if blocked else 1.12
	var tween := create_tween()
	tween.tween_property(current_sprite, "scale", original_scale * Vector2(factor, 1.0 / factor), 0.045)
	tween.tween_property(current_sprite, "scale", original_scale, 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _flash_sprite() -> void:
	if hit_flash_duration <= 0.0:
		return
	current_sprite.modulate = hit_flash_color
	var tween: Tween = create_tween()
	tween.tween_property(current_sprite, "modulate", Color.WHITE, hit_flash_duration)
