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

	# ── Step 3: De-duplicate and sort by severity descending ──────────────
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
		OUTCOME_BLOATING, sev,
		"Likely to cause abdominal bloating and distension. The meal contains multiple fermentable compounds that gut bacteria convert into CO₂, H₂, and CH₄ gas.",
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
		OUTCOME_GAS_ODORLESS, sev,
		"High volume of odorless intestinal gas expected. Gut bacteria ferment undigested carbohydrates, producing large quantities of CO₂, H₂, and potentially CH₄. Gas may be frequent but not malodorous.",
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
		OUTCOME_GAS_SMELLY, sev,
		"Gas is likely to be noticeably malodorous. Sulfur-containing compounds are metabolized by gut bacteria into hydrogen sulfide (H₂S), methanethiol, and organosulfides — all detectable at parts-per-billion concentrations.",
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
		OUTCOME_GAS_PUTRID, sev,
		"High risk of intensely foul-smelling gas. Bacterial putrefaction of undigested protein produces indole and skatole (the primary compounds responsible for fecal odor) plus cadaverine and putrescine.",
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
		OUTCOME_LOOSE_STOOL, sev,
		"This meal is likely to produce loose or soft stools. Osmotically active compounds retain water in the gut, while motility stimulants accelerate transit before full water absorption can occur.",
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
		OUTCOME_DIARRHEA, sev,
		"This meal combination has a significant risk of causing diarrhea. The compounds present either overwhelm intestinal absorption capacity (osmotic), directly stimulate fluid secretion into the gut (secretory), or severely accelerate transit time.",
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
		OUTCOME_GI_IRRITATION, sev,
		"This meal is likely to cause general gastrointestinal irritation: cramping, nausea, or a burning sensation in the gut. Biogenic amines, ethanol, and neurogenic compounds can directly inflame the intestinal mucosa.",
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
		OUTCOME_GLUTEN, sev,
		"This meal contains gluten. In gluten-sensitive or celiac individuals, gliadin proteins trigger an immune response causing villous atrophy, malabsorption, diarrhea, bloating, and systemic inflammation.",
		"gluten/gliadin (immune-mediated enteropathy in sensitive individuals)",
		foods, "🌾⚠️"
	))


# ─────────────────────────────────────────────────────────────────────────────
# PRIVATE HELPER METHODS
# ─────────────────────────────────────────────────────────────────────────────

func _make_warning(
	outcome: String,
	severity: int,
	message: String,
	chemical_cause: String,
	foods_involved: Array,
	icon: String
) -> Dictionary:
	var labels := ["", "Mild", "Moderate", "Severe"]
	return {
		"outcome":        outcome,
		"severity":       severity,
		"severity_label": labels[clampi(severity, 1, 3)],
		"message":        message,
		"chemical_cause": chemical_cause,
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
	var result := []
	for w in warnings:
		var key: String = w["outcome"]
		if not seen.has(key) or seen[key]["severity"] < w["severity"]:
			seen[key] = w
	for key in seen:
		result.append(seen[key])
	return result
