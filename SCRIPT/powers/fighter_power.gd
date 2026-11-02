extends Node
# Classe base dei poteri dei personaggi (attacco secondario ecc.).
#
# Come si crea un potere nuovo:
#   1) nuovo script in res://SCRIPT/powers/ che estende fighter_power.gd
#   2) override di default_params(): elenco dei settings e dei valori di default
#   3) override di use() (e se serve is_busy, on_player_hit, _update_power)
#   4) nel .cfg del personaggio:
#          [secondary]
#          script = "res://SCRIPT/powers/il_tuo_potere.gd"
#      Avviando il gioco dall'editor la console stampa tutti i settings
#      disponibili, pronti da incollare sotto [secondary].
#
# I settings finiti in "params" sono gia' uniti ai default: nello script si
# leggono con params["nome"].

var player  # il Player che possiede il potere (senza tipo: niente dipendenza circolare con player.gd)
var params: Dictionary = {}
var cooldown_left: float = 0.0


# Settings del potere: nome -> valore di default. Ogni chiave qui e' una chiave
# valida in [secondary] del .cfg. "cooldown" (secondi) e' gestito dalla base,
# "stamina_cost" e "stamina_min" pure (vedi can_use()/use() sotto).
func default_params() -> Dictionary:
	return {"cooldown": 5.0, "stamina_cost": 0.0, "stamina_min": 0.0}


func setup(owner_player, values: Dictionary) -> void:
	player = owner_player
	params = values
	_on_setup()


# Chiamata una volta, quando params e player sono pronti
func _on_setup() -> void:
	pass


# Il player puo' lanciare il potere adesso? (cooldown finito, non occupato,
# e ha almeno stamina_min di stamina)
func can_use() -> bool:
	return cooldown_left <= 0.0 and not is_busy() and _has_stamina(float(params.get("stamina_min", 0.0)))


# Lancia il potere (il player ha premuto il tasto): parte il cooldown e si
# consuma stamina_cost. I poteri con attacco caricato (has_charged_attack)
# non passano da qui per la carica: gate/consumo li gestiscono da soli con
# _has_stamina()/_spend_stamina() nei punti giusti (vedi start_charge/release_charge)
func use() -> void:
	cooldown_left = float(params.get("cooldown", 1.0))
	_spend_stamina(float(params.get("stamina_cost", 0.0)))


# Helper per le sottoclassi: il player ha almeno "amount" di stamina?
func _has_stamina(amount: float) -> bool:
	return player == null or player.current_stamina >= amount


# Helper per le sottoclassi: toglie "amount" di stamina al player (clampata a 0 da player.gd)
func _spend_stamina(amount: float) -> void:
	if player != null:
		player.spend_stamina(amount)


# true finche' il player deve restare fermo/bloccato a causa del potere
func is_busy() -> bool:
	return false


# Il player ha subito un colpo (stordimento): interrompi quello che stai facendo
func on_player_hit() -> void:
	pass


# --- Attacco caricato (opzionale) ---
# Un potere che vuole un attacco caricato (tenere premuto "secondary" invece
# del solito tocco) ritorna true da has_charged_attack(): a quel punto
# player.gd, invece del tocco singolo -> use(), gestisce il tasto cosi':
#   - tenuto premuto oltre charge_time() secondi -> start_charge(), poi
#     update_charge(delta) ogni frame finche' resta premuto
#   - rilasciato dopo la carica -> release_charge()
#   - rilasciato prima della soglia -> resta un tocco normale (use())
# Il blocco (tenere "secondary" fermi) viene disattivato per questi poteri:
# lo stesso tasto serve per caricare/rilasciare.
func has_charged_attack() -> bool:
	return false


# Secondi di pressione richiesti prima che la carica parta
func charge_time() -> float:
	return 0.5


# Il player ha iniziato a tenere premuto oltre charge_time(): a questo punto
# can_use() (quindi anche stamina_min) e' gia' stato verificato da player.gd,
# ma se la versione caricata ha una soglia/costo diversi dal tocco normale
# (es. charge_stamina_min/charge_stamina_cost) sta alla sottoclasse controllarli
# qui con _has_stamina()/_spend_stamina() prima di avviare davvero la carica.
# Ritorna true se la carica e' partita: player.gd chiama update_charge/
# release_charge solo in quel caso, altrimenti al rilascio resta un tocco
# normale (vedi player._update_charged_secondary)
func start_charge() -> bool:
	return true


# Chiamata ogni frame (anche a player fermo) finche' la carica e' attiva
func update_charge(_delta: float) -> void:
	pass


# Il player ha rilasciato il tasto dopo aver caricato
func release_charge() -> void:
	pass


# Da sovrascrivere per logica per-frame (girano anche se il player e' stordito)
func _update_power(_delta: float) -> void:
	pass


# I poteri con un effetto temporaneo possono mostrarlo sul client remoto usando
# lo stato replicato dal Player; gli altri non hanno effetti aggiuntivi.
func sync_remote_visual(_effect: String) -> void:
	pass


func _physics_process(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	_update_power(delta)
