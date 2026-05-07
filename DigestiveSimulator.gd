# DigestiveSimulator.gd
# ============================================================
# Digestion Simulation Engine for Diet Health App
# Compatible with Godot 4.x
#
# USAGE:
#   var sim := DigestiveSimulator.new()
#   sim.load_food_database("res://data/foods_compounds.json")
#   var warnings := sim.analyze_meal(["black_beans", "cabbage", "milk"])
#   for w in warnings:
#       print(w.outcome, " | ", w.severity_label, " | ", w.message)
#
# Each warning dict contains:
#   {
#     "outcome":         String  – one of the OUTCOME_* constants
#     "severity":        int     – 1 (mild), 2 (moderate), 3 (severe)
#     "severity_label":  String  – "Mild" / "Moderate" / "Severe"
#     "message":         String  – human-readable explanation
#     "chemical_cause":  String  – which compounds triggered it
#     "icon":            String  – emoji for UI display
#     "foods_involved":  Array   – which food IDs contributed
#   }
# ============================================================

class_name DigestiveSimulator

# ─── Outcome type constants ───────────────────────────────────────────────────
const OUTCOME_BLOATING      := "BLOATING"
const OUTCOME_GAS_ODORLESS  := "GAS_ODORLESS"
const OUTCOME_GAS_SMELLY    := "GAS_SMELLY"
const OUTCOME_GAS_PUTRID    := "GAS_PUTRID"
const OUTCOME_LOOSE_STOOL   := "LOOSE_STOOL"
const OUTCOME_DIARRHEA      := "DIARRHEA"
const OUTCOME_GI_IRRITATION := "GI_IRRITATION"
const OUTCOME_GLUTEN        := "GLUTEN_REACTION"

# ---- Synergy (combination-only) outcome constants ----------------------------
# These fire ONLY when two specific compound categories meet in the same meal.
# Each has a unique key so it is never deduplicated against single-food warnings.
const OUTCOME_SYN_FAT_PROTEIN        := "SYNERGY_FAT_PROTEIN"
const OUTCOME_SYN_FAT_FERMENTABLE    := "SYNERGY_FAT_FERMENTABLE_CARBS"
const OUTCOME_SYN_FRUCTOSE_FIBER     := "SYNERGY_FRUCTOSE_FIBER"
const OUTCOME_SYN_LACTOSE_FAT        := "SYNERGY_LACTOSE_FAT"
const OUTCOME_SYN_SULFUR_FERMENT     := "SYNERGY_SULFUR_FERMENTABLE"
const OUTCOME_SYN_HISTAMINE_ALCOHOL  := "SYNERGY_HISTAMINE_ALCOHOL"
const OUTCOME_SYN_CAPSAICIN_CAFFEINE := "SYNERGY_CAPSAICIN_CAFFEINE"
const OUTCOME_SYN_TANNIN_PROTEIN     := "SYNERGY_TANNIN_PROTEIN"

# ─── Internal state ───────────────────────────────────────────────────────────
var _food_db: Dictionary = {}        # food_id → food dict
var _is_loaded: bool = false

# ─── User sensitivity flags (can be toggled from UI) ─────────────────────────
var user_lactose_intolerant: bool = false
var user_fructose_sensitive: bool = false
var user_gluten_sensitive: bool   = false
var user_histamine_sensitive: bool = false


# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

## Load the JSON food database from a file path (e.g. "res://data/foods_compounds.json")
func load_food_database(json_path: String) -> bool:
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("DigestiveSimulator: Cannot open food database at: " + json_path)
		return false

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_error("DigestiveSimulator: Failed to parse food database JSON.")
		return false

	var foods_array: Array = parsed.get("foods", [])
	for food in foods_array:
		if food.has("id"):
			_food_db[food["id"]] = food

	_is_loaded = true
	return true


## Load the database from an already-parsed Dictionary
## (useful if you loaded the JSON yourself or embedded it)
func load_food_database_from_dict(parsed: Dictionary) -> void:
	var foods_array: Array = parsed.get("foods", [])
	for food in foods_array:
		if food.has("id"):
			_food_db[food["id"]] = food
	_is_loaded = true


## Returns a list of all food IDs available in the database
func get_all_food_ids() -> Array:
	return _food_db.keys()


## Returns a food's display name by ID
func get_food_name(food_id: String) -> String:
	if _food_db.has(food_id):
		return _food_db[food_id].get("name", food_id)
	return food_id


## Returns all foods in a given category
func get_foods_by_category(category: String) -> Array:
	var result := []
	for food_id in _food_db:
		if _food_db[food_id].get("category", "") == category:
			result.append(food_id)
	return result


## Main analysis function.
## Pass an Array of food IDs (strings) from your selected meal.
## Returns an Array of warning Dictionaries.
func analyze_meal(food_ids: Array) -> Array:
	if not _is_loaded:
		push_warning("DigestiveSimulator: Database not loaded. Call load_food_database() first.")
		return []

	# ── Step 1: Accumulate compound totals across all foods ───────────────
	var totals: Dictionary = {}       # compound_name → int total
	var sources: Dictionary = {}      # compound_name → [food_ids that contribute]

	for food_id in food_ids:
		if not _food_db.has(food_id):
			push_warning("DigestiveSimulator: Unknown food ID '%s', skipping." % food_id)
			continue
		var compounds: Dictionary = _food_db[food_id].get("compounds", {})
		for compound in compounds:
			var value: int = compounds[compound]
			if value <= 0:
				continue
			totals[compound] = totals.get(compound, 0) + value
			if not sources.has(compound):
				sources[compound] = []
			if not sources[compound].has(food_id):
				sources[compound].append(food_id)

	# ── Step 2: Run all rule sets ─────────────────────────────────────────
	var warnings: Array = []

	_check_bloating(totals, sources, warnings)
	_check_gas_odorless(totals, sources, warnings)
	_check_gas_smelly(totals, sources, warnings)
	_check_gas_putrid(totals, sources, warnings)
	_check_loose_stool(totals, sources, warnings)
	_check_diarrhea(totals, sources, warnings)
	_check_gi_irritation(totals, sources, warnings)
	_check_gluten(totals, sources, warnings)

	# Step 3: Run synergy combination rules
	_check_synergy_combinations(totals, sources, warnings)

	# ── Step 4: De-duplicate and sort by severity descending ──────────────
	warnings = _deduplicate_outcomes(warnings)
	warnings.sort_custom(func(a, b): return a["severity"] > b["severity"])

	return warnings


## Returns a summary string for quick display (e.g. notification badge)
func get_meal_summary(food_ids: Array) -> String:
	var warnings := analyze_meal(food_ids)
	if warnings.is_empty():
		return "✅ No major digestive concerns detected."
	var lines := []
	for w in warnings:
		lines.append("%s %s: %s" % [w["icon"], w["severity_label"], w["message"]])
	return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# PRIVATE RULE CHECKERS
# Each function appends warning dicts to the `warnings` array.
# ─────────────────────────────────────────────────────────────────────────────

func _check_bloating(totals: Dictionary, sources: Dictionary, warnings: Array) -> void:
	var score := 0
	var causes := []
	var foods := []

	# Raffinose (beans, cabbage) – major bloat driver
	var raf : int = totals.get("raffinose", 0)
	if raf >= 1:
		score += raf
		causes.append("raffinose/oligosaccharides (undigestible sugars → CO₂ + H₂ fermentation)")
		_merge_foods(foods, sources.get("raffinose", []))

	# Inulin / FOS (garlic, onion, artichoke)
	var fos : int = totals.get("inulin_fos", 0)
	if fos >= 1:
		score += fos
		causes.append("inulin/FOS (fructooligosaccharides → rapid bacterial fermentation)")
		_merge_foods(foods, sources.get("inulin_fos", []))

	# Resistant starch (cold potato, green banana, legumes)
	var rs : int = totals.get("resistant_starch", 0)
	if rs >= 2:
		score += rs - 1
		causes.append("resistant starch (escapes digestion → colonic fermentation → gas)")
		_merge_foods(foods, sources.get("resistant_starch", []))

	# Soluble fiber (fermentable)
	var sf : int = totals.get("soluble_fiber", 0)
	if sf >= 3:
		score += 1
		causes.append("high soluble fiber (β-glucan, pectin → fermentation → gas)")
		_merge_foods(foods, sources.get("soluble_fiber", []))

	# Lactose triggers bloating (even without diarrhea)
	var lac : int = totals.get("lactose", 0)
	if lac >= 2 or (user_lactose_intolerant and lac >= 1):
		score += lac
		causes.append("lactose (undigested milk sugar → lactic acid + CO₂ fermentation)")
		_merge_foods(foods, sources.get("lactose", []))

	# Fructose in large amounts
	var fru : int = totals.get("fructose", 0)
	if fru >= 3 or (user_fructose_sensitive and fru >= 2):
		score += 1
		causes.append("excess fructose (saturates GLUT-5 transporter → colonic fermentation)")
		_merge_foods(foods, sources.get("fructose", []))

	if score <= 0:
		return

	var sev := clampi(_severity_from_score(score, 2, 5, 9), 1, 3)
	warnings.append(_make_warning(
		OUTCOME_BLOATING, sev, false,
		"Bloating",
		"Gut bacteria ferment undigested carbohydrates, producing CO2, H2 and CH4 gas that distends the intestine.",
		"Abdominal bloating, visible distension, and a feeling of pressure or fullness.",
		", ".join(causes), foods, "🫃"
	))


func _check_gas_odorless(totals: Dictionary, sources: Dictionary, warnings: Array) -> void:
	# Odorless gas (volume) comes from carbohydrate fermentation
	var score := 0
	var causes := []
	var foods := []

	var raf : int = totals.get("raffinose", 0)
	var fos : int = totals.get("inulin_fos", 0)
	var rs  : int = totals.get("resistant_starch", 0)
	var lac : int = totals.get("lactose", 0)
	var fru : int = totals.get("fructose", 0)

	score = raf + fos + rs + (lac if lac >= 2 else 0) + (fru if fru >= 3 else 0)

	if raf >= 2:
		causes.append("raffinose → CO₂ + H₂ by colonic bacteria")
		_merge_foods(foods, sources.get("raffinose", []))
	if fos >= 2:
		causes.append("FOS → H₂ + CO₂ (Bifidobacteria fermentation)")
		_merge_foods(foods, sources.get("inulin_fos", []))
	if rs >= 2:
		causes.append("resistant starch → H₂ + CO₂ + methane (CH₄)")
		_merge_foods(foods, sources.get("resistant_starch", []))

	if score < 3:
		return

	var sev := clampi(_severity_from_score(score, 3, 6, 10), 1, 3)
	warnings.append(_make_warning(
		OUTCOME_GAS_ODORLESS, sev, false,
		"High-Volume Odorless Gas",
		"Fermentation of undigested carbohydrates by colonic bacteria produces large volumes of CO2, H2, and CH4.",
		"Frequent passing of gas that is not malodorous but may be embarrassing due to volume.",
		", ".join(causes), foods, "💨"
	))


func _check_gas_smelly(totals: Dictionary, sources: Dictionary, warnings: Array) -> void:
	var score := 0
	var causes := []
	var foods := []

	# Sulfur amino acids (eggs, meat, whey) → H₂S + methanethiol
	var saa : int = totals.get("sulfur_aa", 0)
	if saa >= 1:
		score += saa
		causes.append("sulfur amino acids (methionine/cysteine → H₂S + methanethiol by gut bacteria)")
		_merge_foods(foods, sources.get("sulfur_aa", []))

	# Glucosinolates (cruciferous veg) → H₂S via Desulfovibrio
	var gls : int = totals.get("glucosinolates", 0)
	if gls >= 1:
		score += gls
		causes.append("glucosinolates (cruciferous sulfur compounds → H₂S via sulfate-reducing bacteria)")
		_merge_foods(foods, sources.get("glucosinolates", []))

	# Allicin compounds (garlic, onion) → diallyl sulfide, allyl mercaptan
	var alc : int = totals.get("allicin_compounds", 0)
	if alc >= 1:
		score += alc
		causes.append("allicin/organosulfurs (garlic/onion → diallyl sulfide, allyl mercaptan)")
		_merge_foods(foods, sources.get("allicin_compounds", []))

	if score < 2:
		return

	var sev := clampi(_severity_from_score(score, 2, 5, 8), 1, 3)
	warnings.append(_make_warning(
		OUTCOME_GAS_SMELLY, sev, false,
		"Malodorous Gas (Sulfur)",
		"Gut bacteria metabolize sulfur-containing compounds into hydrogen sulfide (H2S), methanethiol, and organosulfides, detectable at parts-per-billion concentrations.",
		"Gas with a strong rotten-egg or sulfurous odor.",
		", ".join(causes), foods, "🤢"
	))


func _check_gas_putrid(totals: Dictionary, sources: Dictionary, warnings: Array) -> void:
	# Putrefactive odor = protein decomposition → indole, skatole, cadaverine, putrescine
	var score := 0
	var causes := []
	var foods := []

	var trp : int = totals.get("tryptophan", 0)
	var prot : int = totals.get("high_protein", 0)
	var rs   : int = totals.get("resistant_starch", 0)
	var saa  : int = totals.get("sulfur_aa", 0)

	if trp >= 2:
		score += trp
		causes.append("tryptophan → indole + skatole (intensely fecal odor; produced by Clostridium/Bacteroides)")
		_merge_foods(foods, sources.get("tryptophan", []))

	if prot >= 2:
		score += prot - 1
		causes.append("high protein load → putrefaction (cadaverine, putrescine, phenols)")
		_merge_foods(foods, sources.get("high_protein", []))

	# Synergy: high protein + resistant starch accelerates putrefaction
	# (bacteria get more substrate AND more time with slower transit)
	if prot >= 2 and rs >= 2:
		score += 2
		causes.append("protein + resistant starch synergy → prolonged transit → deeper putrefaction")

	if score < 3:
		return

	var sev := clampi(_severity_from_score(score, 3, 6, 9), 1, 3)
	warnings.append(_make_warning(
		OUTCOME_GAS_PUTRID, sev, false,
		"Intensely Foul-Smelling Gas (Putrefaction)",
		"Bacterial putrefaction of undigested protein produces indole and skatole — the primary compounds responsible for fecal odor — plus cadaverine and putrescine.",
		"Gas with an intensely fecal, putrid odor.",
		", ".join(causes), foods, "💀"
	))


func _check_loose_stool(totals: Dictionary, sources: Dictionary, warnings: Array) -> void:
	var score := 0
	var causes := []
	var foods := []

	# Sorbitol alone → osmotic water retention
	var sor : int = totals.get("sorbitol", 0)
	if sor >= 2:
		score += sor
		causes.append("sorbitol (osmotically active sugar alcohol → draws water into intestine)")
		_merge_foods(foods, sources.get("sorbitol", []))

	# Mannitol (mushrooms, sugar-free products)
	var man : int = totals.get("mannitol", 0)
	if man >= 2:
		score += man
		causes.append("mannitol (poorly absorbed polyol → osmotic water retention)")
		_merge_foods(foods, sources.get("mannitol", []))

	# Xylitol
	var xyl : int = totals.get("xylitol", 0)
	if xyl >= 1:
		score += xyl
		causes.append("xylitol (sugar alcohol → colonic osmotic effect)")
		_merge_foods(foods, sources.get("xylitol", []))

	# Caffeine → colonic motility stimulation
	var caf : int = totals.get("caffeine", 0)
	if caf >= 2:
		score += caf - 1
		causes.append("caffeine (stimulates colonic motility via adenosine receptors → accelerated transit)")
		_merge_foods(foods, sources.get("caffeine", []))

	# High fat → large bile acid bolus → secretory effect in colon
	var fat : int = totals.get("fat_high", 0)
	if fat >= 2:
		score += fat - 1
		causes.append("high fat (large bile acid release → deoxycholic acid stimulates Cl⁻ secretion in colon)")
		_merge_foods(foods, sources.get("fat_high", []))

	# Capsaicin → TRPV1 activation → secretion + hypermotility
	var cap : int = totals.get("capsaicin", 0)
	if cap >= 2:
		score += cap
		causes.append("capsaicin (TRPV1 receptor activation → intestinal hypersecretion and motility spike)")
		_merge_foods(foods, sources.get("capsaicin", []))

	# Magnesium (high dose)
	var mag : int = totals.get("magnesium", 0)
	if mag >= 2:
		score += mag
		causes.append("magnesium (poorly absorbed Mg²⁺ ions → osmotic laxative effect)")
		_merge_foods(foods, sources.get("magnesium", []))

	if score < 2:
		return

	var sev := clampi(_severity_from_score(score, 2, 5, 8), 1, 3)
	warnings.append(_make_warning(
		OUTCOME_LOOSE_STOOL, sev, false,
		"Loose or Soft Stool",
		"Osmotically active compounds retain water in the gut while motility stimulants accelerate transit, preventing full water absorption.",
		"Loose, soft, or mushy stools shortly after eating.",
		", ".join(causes), foods, "🚽"
	))


func _check_diarrhea(totals: Dictionary, sources: Dictionary, warnings: Array) -> void:
	var score := 0
	var causes := []
	var foods := []

	# ── Rule 1: Fructose + Sorbitol (synergistic – most potent combination) ──
	var fru : int = totals.get("fructose", 0)
	var sor : int = totals.get("sorbitol", 0)
	if fru >= 2 and sor >= 2:
		score += fru + sor + 2   # +2 synergy bonus
		causes.append("fructose + sorbitol synergy (sorbitol competitively inhibits GLUT-5, causing far more fructose to reach the colon → explosive osmotic diarrhea)")
		_merge_foods(foods, sources.get("fructose", []))
		_merge_foods(foods, sources.get("sorbitol", []))

	# ── Rule 2: High lactose (especially in intolerant individuals) ──────────
	var lac : int = totals.get("lactose", 0)
	if lac >= 3 or (user_lactose_intolerant and lac >= 2):
		score += lac + (2 if user_lactose_intolerant else 0)
		causes.append("high lactose (unhydrolyzed lactose → osmotic gradient + lactic acid fermentation → watery stool)")
		_merge_foods(foods, sources.get("lactose", []))

	# ── Rule 3: Alcohol (mucosal damage + hypersecretion) ───────────────────
	var alc : int = totals.get("alcohol", 0)
	if alc >= 2:
		score += alc
		causes.append("alcohol (disrupts intestinal tight junctions + stimulates Cl⁻ secretion + accelerates motility)")
		_merge_foods(foods, sources.get("alcohol", []))

	# ── Rule 4: Alcohol + Caffeine (double motility hit) ────────────────────
	var caf : int = totals.get("caffeine", 0)
	if alc >= 1 and caf >= 2:
		score += 3
		causes.append("alcohol + caffeine combination (independent motility stimulants → severely accelerated transit)")
		_merge_foods(foods, sources.get("caffeine", []))

	# ── Rule 5: Very high fat + protein (bile salt diarrhea) ────────────────
	var fat  : int = totals.get("fat_high", 0)
	var prot : int = totals.get("high_protein", 0)
	if fat >= 3 and prot >= 3:
		score += 4
		causes.append("extreme fat + protein load (overwhelms bile acid reabsorption → deoxycholic acid reaches colon → secretory diarrhea)")
		_merge_foods(foods, sources.get("fat_high", []))
		_merge_foods(foods, sources.get("high_protein", []))

	# ── Rule 6: Multiple sugar alcohols ─────────────────────────────────────
	var xyl : int = totals.get("xylitol", 0)
	var man : int = totals.get("mannitol", 0)
	var polyol_total := sor + xyl + man
	if polyol_total >= 5:
		score += 3
		causes.append("multiple polyols/sugar alcohols (sorbitol + xylitol + mannitol → combined osmotic overload)")
		_merge_foods(foods, sources.get("sorbitol", []))
		_merge_foods(foods, sources.get("xylitol", []))
		_merge_foods(foods, sources.get("mannitol", []))

	# ── Rule 7: Capsaicin + fat (delayed capsaicin + bile surge) ────────────
	var cap : int = totals.get("capsaicin", 0)
	if cap >= 2 and fat >= 2:
		score += 3
		causes.append("capsaicin + fat (fat delays gastric emptying, then capsaicin arrives as a bolus → intense TRPV1 activation + bile acid surge → secretory diarrhea)")
		_merge_foods(foods, sources.get("capsaicin", []))
		_merge_foods(foods, sources.get("fat_high", []))

	if score < 5:
		return

	var sev := clampi(_severity_from_score(score, 5, 9, 14), 1, 3)
	warnings.append(_make_warning(
		OUTCOME_DIARRHEA, sev, false,
		"Diarrhea Risk",
		"The compounds present either overwhelm intestinal absorption (osmotic), directly stimulate fluid secretion (secretory), or severely accelerate transit time.",
		"Watery or very loose stools, possibly urgent and crampy.",
		", ".join(causes), foods, "⚠️🚽"
	))


func _check_gi_irritation(totals: Dictionary, sources: Dictionary, warnings: Array) -> void:
	var score := 0
	var causes := []
	var foods := []

	# Histamine (fermented foods, aged cheese, red wine)
	var his : int = totals.get("histamine", 0)
	if his >= 2 or (user_histamine_sensitive and his >= 1):
		score += his + (2 if user_histamine_sensitive else 0)
		causes.append("histamine (biogenic amine → H1/H2 receptor activation → GI cramping, secretion, motility)")
		_merge_foods(foods, sources.get("histamine", []))

	# Alcohol + high fiber (mechanical irritation + fermentation)
	var alc : int = totals.get("alcohol", 0)
	var fib : int = totals.get("insoluble_fiber", 0)
	if alc >= 1 and fib >= 2:
		score += 2
		causes.append("alcohol + insoluble fiber (ethanol damages mucosa; fiber causes mechanical irritation in inflamed tissue)")
		_merge_foods(foods, sources.get("alcohol", []))

	# Capsaicin at high levels = TRPV1 mediated mucosal burning
	var cap : int = totals.get("capsaicin", 0)
	if cap >= 3:
		score += 2
		causes.append("very high capsaicin (TRPV1 overstimulation → sensation of intestinal burning)")
		_merge_foods(foods, sources.get("capsaicin", []))

	# Tannins at high levels
	var tan : int = totals.get("tannins", 0)
	if tan >= 3:
		score += 1
		causes.append("high tannins (precipitate mucosal proteins → astringency and GI discomfort)")
		_merge_foods(foods, sources.get("tannins", []))

	if score < 2:
		return

	var sev := clampi(_severity_from_score(score, 2, 4, 7), 1, 3)
	warnings.append(_make_warning(
		OUTCOME_GI_IRRITATION, sev, false,
		"GI Irritation",
		"Biogenic amines, ethanol, and neurogenic compounds directly inflame or irritate the intestinal mucosa.",
		"Cramping, nausea, or a burning sensation in the gut.",
		", ".join(causes), foods, "🔥"
	))


func _check_gluten(totals: Dictionary, sources: Dictionary, warnings: Array) -> void:
	if not user_gluten_sensitive:
		return

	var glu : int = totals.get("gluten", 0)
	if glu < 1:
		return

	var foods : Array = sources.get("gluten", [])
	var sev := clampi(glu, 1, 3)
	warnings.append(_make_warning(
		OUTCOME_GLUTEN, sev, false,
		"Gluten Reaction",
		"Gliadin proteins trigger an immune response in sensitive individuals, causing villous atrophy and malabsorption.",
		"Bloating, diarrhea, fatigue, and systemic inflammation in gluten-sensitive individuals.",
		"gluten/gliadin (immune-mediated enteropathy)",
		foods, "🌾⚠️"
	))
	
# =============================================================================
# PRIVATE - SYNERGY COMBINATION CHECKER
#
# Each rule fires ONLY when two specific compound categories from DIFFERENT
# foods are present together in the same meal. is_synergy = true tells the UI
# to display the special "Combination Warning" badge and explanation.
# =============================================================================
 
func _check_synergy_combinations(totals: Dictionary, sources: Dictionary, warnings: Array) -> void:
 
	var fat  :int= totals.get("fat_high", 0)
	var prot :int= totals.get("high_protein", 0)
	var trp  :int= totals.get("tryptophan", 0)
	var raf  :int= totals.get("raffinose", 0)
	var fos  :int= totals.get("inulin_fos", 0)
	var rs   :int= totals.get("resistant_starch", 0)
	var fru  :int= totals.get("fructose", 0)
	var sf   :int= totals.get("soluble_fiber", 0)
	var lac  :int= totals.get("lactose", 0)
	var saa  :int= totals.get("sulfur_aa", 0)
	var gls  :int= totals.get("glucosinolates", 0)
	var his  :int= totals.get("histamine", 0)
	var alc  :int= totals.get("alcohol", 0)
	var cap  :int= totals.get("capsaicin", 0)
	var caf  :int= totals.get("caffeine", 0)
	var tan  :int= totals.get("tannins", 0)
 
	# ---- SYNERGY 1: Fat + Protein (Putrefaction Accelerator) -----------------
	# High fat slows gastric emptying. Protein lingers in the small intestine
	# far longer than normal, so more reaches the colon intact where bacteria
	# putrefy it into indole, skatole, cadaverine, and H2S.
	# Neither food alone causes this — the delayed transit is the key.
	if fat >= 2 and prot >= 2 and trp >= 2:
		var foods :Array= []
		_merge_foods(foods, sources.get("fat_high", []))
		_merge_foods(foods, sources.get("high_protein", []))
		_merge_foods(foods, sources.get("tryptophan", []))
		var sev :int= 2 if (fat >= 3 or prot >= 3) else 1
		warnings.append(_make_warning(
			OUTCOME_SYN_FAT_PROTEIN, sev, true,
			"Fat + Protein — Putrefaction Accelerator",
			"High dietary fat slows gastric emptying, so protein sits in the gut much longer than it would alone. Bacteria putrefy the excess protein into indole, skatole, cadaverine, and hydrogen sulfide — compounds that neither the fat food nor the protein food would generate eaten separately at these levels.",
			"Intensely foul-smelling, delayed gas 1-3 hours after eating, with possible cramping. Neither food eaten alone would cause this.",
			"fat_high (delayed transit) + high_protein + tryptophan (amplified colonic putrefaction)",
			foods, "⚡🧪"
		))
 
	# ---- SYNERGY 2: Fat + Fermentable Carbohydrates (Fermentation Amplifier) -
	# Fat slows intestinal transit. Fermentable carbs that would normally pass
	# through in 4-6 hours instead sit in the colon far longer, giving bacteria
	# much more time to ferment them. Gas volume is substantially worse than
	# either food group causes alone.
	var fermentable := raf + fos + rs
	if fat >= 2 and fermentable >= 3:
		var foods :Array= []
		_merge_foods(foods, sources.get("fat_high", []))
		if raf >= 1: _merge_foods(foods, sources.get("raffinose", []))
		if fos >= 1: _merge_foods(foods, sources.get("inulin_fos", []))
		if rs  >= 1: _merge_foods(foods, sources.get("resistant_starch", []))
		var sev :int= 2 if fat >= 3 else 1
		warnings.append(_make_warning(
			OUTCOME_SYN_FAT_FERMENTABLE, sev, true,
			"Fat + Fermentable Carbs — Fermentation Amplifier",
			"Fat significantly slows intestinal transit, giving colonic bacteria far more time to ferment oligosaccharides and resistant starch. Gas production is amplified well beyond what either food group would cause alone.",
			"Prolonged, severe bloating and gas that builds over several hours — much worse than eating the carbohydrate-rich foods without fat.",
			"fat_high (slowed transit) + raffinose/inulin_fos/resistant_starch (extended colonic fermentation window)",
			foods, "⚡💨"
		))
 
	# ---- SYNERGY 3: Fructose + Soluble Fiber (Osmotic Amplifier) -------------
	# Soluble fiber ferments rapidly, producing short-chain fatty acids that lower
	# luminal pH and reduce fructose absorption further. The fermentation
	# byproducts also draw water osmotically. Together they create a compounded
	# osmotic-fermentation effect neither causes alone.
	if fru >= 2 and sf >= 2:
		var foods :Array= []
		_merge_foods(foods, sources.get("fructose", []))
		_merge_foods(foods, sources.get("soluble_fiber", []))
		var sev :int= 2 if (fru >= 3 and sf >= 3) else 1
		warnings.append(_make_warning(
			OUTCOME_SYN_FRUCTOSE_FIBER, sev, true,
			"Fructose + Soluble Fiber — Osmotic Amplifier",
			"Soluble fiber fermentation lowers colonic pH and produces osmotically active short-chain fatty acids. This environment reduces fructose absorption and compounds the water-drawing osmotic effect — a double osmotic hit that neither compound causes alone at these levels.",
			"Loose stools or diarrhea with cramping, more severe than eating either the fruit or the fiber-rich food alone.",
			"fructose (GLUT-5 saturation) + soluble_fiber (SCFA fermentation -> pH drop -> amplified osmotic effect)",
			foods, "⚡🚽"
		))
 
	# ---- SYNERGY 4: Lactose + High Fat (Bolus Delivery Effect) ---------------
	# Fat delays gastric emptying substantially. Lactose that would normally
	# arrive in the small intestine gradually instead arrives as a concentrated
	# bolus, overwhelming lactase enzyme capacity all at once. Even partially
	# tolerant individuals can experience osmotic symptoms.
	if lac >= 2 and fat >= 2:
		var foods :Array= []
		_merge_foods(foods, sources.get("lactose", []))
		_merge_foods(foods, sources.get("fat_high", []))
		var sev :int= 3 if user_lactose_intolerant else (2 if (lac >= 3 or fat >= 3) else 1)
		warnings.append(_make_warning(
			OUTCOME_SYN_LACTOSE_FAT, sev, true,
			"Lactose + Fat — Bolus Delivery Effect",
			"Fat delays gastric emptying, causing lactose to arrive in the small intestine as a concentrated bolus rather than gradually. This overwhelms lactase enzyme capacity even in partially tolerant individuals, causing osmotic shock that neither the dairy nor the fatty food would cause separately.",
			"Sudden cramping, bloating, and watery diarrhea 1-2 hours after the meal — more severe than either food eaten alone.",
			"fat_high (delayed gastric emptying) + lactose (bolus delivery -> lactase overload -> osmotic diarrhea)",
			foods, "⚡💧"
		))
 
	# ---- SYNERGY 5: Sulfur + Fermentable Carbs (H2S Amplifier) ---------------
	# Fermentation of oligosaccharides produces large quantities of H2 gas.
	# Sulfate-reducing bacteria (Desulfovibrio) use this H2 as an electron donor
	# to reduce sulfate from sulfur amino acids into H2S.
	# Reaction: SO4(2-) + 4H2 -> H2S + 4H2O (requires BOTH substrates).
	# Neither the sulfur-rich food nor the fermentable carb food alone produces
	# this H2S load.
	var sulfur_total := saa + gls
	if sulfur_total >= 2 and (raf >= 2 or rs >= 2 or fos >= 2):
		var foods :Array= []
		if saa >= 1: _merge_foods(foods, sources.get("sulfur_aa", []))
		if gls >= 1: _merge_foods(foods, sources.get("glucosinolates", []))
		if raf >= 1: _merge_foods(foods, sources.get("raffinose", []))
		if rs  >= 1: _merge_foods(foods, sources.get("resistant_starch", []))
		if fos >= 1: _merge_foods(foods, sources.get("inulin_fos", []))
		var sev :int= 2 if sulfur_total >= 4 else 1
		warnings.append(_make_warning(
			OUTCOME_SYN_SULFUR_FERMENT, sev, true,
			"Sulfur Foods + Fermentable Carbs — H2S Amplifier",
			"Fermentation of oligosaccharides produces large amounts of H2 gas. Sulfate-reducing gut bacteria (Desulfovibrio) use this H2 to reduce sulfate from sulfur amino acids into hydrogen sulfide via the reaction SO4(2-) + 4H2 -> H2S. This reaction requires both substrates simultaneously — neither the sulfur-rich food nor the fermentable carb alone produces this H2S load.",
			"Gas that is dramatically more foul-smelling than eating either food alone — a rotten-egg sulfurous odor that can last for hours.",
			"sulfur_aa/glucosinolates (sulfate donor) + raffinose/resistant_starch/inulin_fos (H2 donor -> H2S via Desulfovibrio)",
			foods, "⚡🥚"
		))
 
	# ---- SYNERGY 6: Histamine + Alcohol (DAO Inhibition) ---------------------
	# Alcohol inhibits diamine oxidase (DAO), the primary intestinal enzyme that
	# breaks down histamine. A histamine load that would normally be safely
	# metabolized accumulates in the gut wall because the enzyme is blocked.
	# The histamine food alone is fine; alcohol alone at moderate levels is fine.
	# Together the histamine cannot be cleared.
	if his >= 2 and alc >= 1:
		var foods :Array= []
		_merge_foods(foods, sources.get("histamine", []))
		_merge_foods(foods, sources.get("alcohol", []))
		var sev :int= 3 if (user_histamine_sensitive or (his >= 3 and alc >= 2)) else 2
		warnings.append(_make_warning(
			OUTCOME_SYN_HISTAMINE_ALCOHOL, sev, true,
			"Histamine + Alcohol — DAO Enzyme Inhibition",
			"Alcohol inhibits diamine oxidase (DAO), the intestinal enzyme responsible for breaking down histamine. A histamine load from fermented foods, aged cheese, or wine that would normally be safely cleared instead accumulates in the gut wall, activating H1, H2, and H4 receptors. You may normally tolerate both foods individually — the problem is the combination.",
			"Flushing, GI cramping, diarrhea, headache, and nausea appearing even though you tolerate both foods individually.",
			"alcohol (DAO inhibition) + histamine (biogenic amine accumulation -> H1/H2/H4 receptor activation)",
			foods, "⚡🚨"
		))
 
	# ---- SYNERGY 7: Capsaicin + Caffeine (Double Motility Spike) -------------
	# Capsaicin activates TRPV1 receptors on enteric neurons, triggering
	# hypermotility and secretion. Caffeine independently stimulates colonic
	# contractions via adenosine receptor blockade. These mechanisms act on
	# completely different receptor systems simultaneously, producing a combined
	# motility surge neither compound causes alone at moderate doses.
	if cap >= 2 and caf >= 2:
		var foods :Array= []
		_merge_foods(foods, sources.get("capsaicin", []))
		_merge_foods(foods, sources.get("caffeine", []))
		var sev :int= 2 if (cap >= 3 or caf >= 3) else 1
		warnings.append(_make_warning(
			OUTCOME_SYN_CAPSAICIN_CAFFEINE, sev, true,
			"Capsaicin + Caffeine — Double Motility Spike",
			"Capsaicin activates TRPV1 receptors on enteric neurons causing motility and secretion, while caffeine simultaneously blocks adenosine receptors to trigger colonic contractions. These two mechanisms act on completely different receptor systems at the same time, producing a combined motility surge neither compound causes alone at these doses.",
			"Urgent loose stools or diarrhea with cramping that comes on faster and harder than either food alone — the spicy coffee effect.",
			"capsaicin (TRPV1 -> enteric neuron hypermotility) + caffeine (adenosine blockade -> colonic contraction)",
			foods, "⚡☕🌶️"
		))
 
	# ---- SYNERGY 8: Tannins + High Protein (Putrefaction Paradox) ------------
	# Tannins bind to mucosal proteins and slow intestinal transit (constipating
	# via astringency). Protein that would normally clear the colon in a
	# reasonable time instead sits there longer, giving bacteria more time for
	# putrefaction. The gut feels settled initially, then becomes increasingly
	# uncomfortable hours later — a paradox because the "calming" tannins trap
	# the protein fermentation products inside.
	if tan >= 2 and prot >= 2:
		var foods :Array= []
		_merge_foods(foods, sources.get("tannins", []))
		_merge_foods(foods, sources.get("high_protein", []))
		if trp >= 1: _merge_foods(foods, sources.get("tryptophan", []))
		var sev :int= 2 if (tan >= 3 and prot >= 3) else 1
		warnings.append(_make_warning(
			OUTCOME_SYN_TANNIN_PROTEIN, sev, true,
			"Tannins + High Protein — Putrefaction Paradox",
			"Tannins bind to intestinal mucosal proteins and slow gut transit through astringency. Protein that would normally clear the colon relatively quickly instead lingers, giving bacteria far more time to putrefy it into indole, skatole, and other foul-smelling compounds. The gut feels settled initially — then gets progressively worse over hours.",
			"Delayed 2-4 hours foul-smelling gas, bloating, and cramping that worsens over time — not something either the tannin-rich food or the protein food would cause eaten separately.",
			"tannins (slowed transit via mucosal astringency) + high_protein/tryptophan (prolonged putrefaction -> indole, skatole)",
			foods, "⚡🍷🥩"
		))


# ─────────────────────────────────────────────────────────────────────────────
# PRIVATE HELPER METHODS
# ─────────────────────────────────────────────────────────────────────────────

func _make_warning(
	outcome: String,
	severity: int,
	is_synergy: bool,
	title: String,
	mechanism: String,
	consequence: String,
	chemical_cause: String,
	foods_involved: Array,
	icon: String
) -> Dictionary:
	var labels := ["", "Mild", "Moderate", "Severe"]
	var full_message: String
	if is_synergy:
		full_message = "COMBINATION WARNING\n\n%s\n\nWhat you will feel: %s" % [mechanism, consequence]
	else:
		full_message = "%s\n\nWhat you will feel: %s" % [mechanism, consequence]
	return {
		"outcome":        outcome,
		"severity":       clampi(severity, 1, 3),
		"severity_label": labels[clampi(severity, 1, 3)],
		"title":          title,
		"mechanism":      mechanism,
		"consequence":    consequence,
		"message":        full_message,
		"chemical_cause": chemical_cause,
		"is_synergy":     is_synergy,
		"foods_involved": foods_involved,
		"icon":           icon
	}


## Maps a raw score to a severity tier (1, 2, or 3)
func _severity_from_score(score: int, mild_threshold: int, moderate_threshold: int, severe_threshold: int) -> int:
	if score >= severe_threshold:
		return 3
	elif score >= moderate_threshold:
		return 2
	elif score >= mild_threshold:
		return 1
	return 0


## Merges food IDs into an array without duplicates
func _merge_foods(target: Array, source: Array) -> void:
	for f in source:
		if not target.has(f):
			target.append(f)


## Removes duplicate outcome entries, keeping the highest severity one
func _deduplicate_outcomes(warnings: Array) -> Array:
	var seen: Dictionary = {}
	var result :Array= []
	for w in warnings:
		if w.get("is_synergy", false):
			result.append(w)
		else:
			var key: String = w["outcome"]
			if not seen.has(key) or seen[key]["severity"] < w["severity"]:
				seen[key] = w
	for key in seen:
		result.append(seen[key])
	return result
