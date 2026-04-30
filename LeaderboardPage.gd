extends Control

# ── Level System ──
var user_level: int = 0
var level_streak: int = 0      # consecutive days fulfilling all recommendations
var level_fail_streak: int = 0  # consecutive days failing recommendations

signal level_changed(new_level: int)

func _ready():
	load_level()
	_check_daily_level()
	Global.badge_earned.connect(_on_badge_earned_leaderboard)
	refresh_display()

# ─────────────────────────────────────────
#  LEVEL SYSTEM
# ─────────────────────────────────────────
func _check_daily_level():
	var today    = Time.get_date_string_from_system()
	var last_day = _load_level_check_date()
	if last_day == today: return  # already checked today

	var met_all = _did_meet_recommendations_yesterday()
	if met_all:
		level_streak += 1
		level_fail_streak = 0
		var old_level = user_level
		user_level += 1
		if user_level != old_level:
			level_changed.emit(user_level)
	else:
		level_fail_streak += 1
		if level_fail_streak >= 10:
			user_level = max(0, user_level - 10)
			level_fail_streak = 0
	save_level(today)

func _did_meet_recommendations_yesterday() -> bool:
	var yesterday = _get_yesterday_string()
	var home_page = get_tree().root.get_node_or_null("Main/ContentArea/HomePage")
	if not home_page: return false
	var history = home_page.meal_history
	if not history.has(yesterday): return false
	var day = history[yesterday]
	var totals = day.get("totals", {})
	if totals.is_empty(): return false

	var macro_goals = Global.get_macro_goals()
	var daily_goal  = Global.body_metrics.get("daily_goal", 2000.0)
	var water_goal  = Global.daily_water_liters * 1000.0
	var water_ml    = day.get("water_ml", 0.0)

	# Check kcal within 15%
	var kcal = totals.get("calories", 0.0)
	if daily_goal > 0 and not (kcal >= daily_goal * 0.85 and kcal <= daily_goal * 1.15):
		return false

	# Check protein
	if totals.get("protein_g", 0.0) < macro_goals.get("protein_g", 50.0):
		return false

	# Check fiber
	if totals.get("fiber_g", 0.0) < macro_goals.get("fiber_g", 25.0):
		return false

	# Check water
	if water_goal > 0 and water_ml < water_goal * 0.9:
		return false

	return true

func _get_yesterday_string() -> String:
	var unix = Time.get_unix_time_from_system() - 86400
	var dt   = Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]

func save_level(today: String):
	var file = FileAccess.open("user://level.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"level":          user_level,
		"level_streak":   level_streak,
		"fail_streak":    level_fail_streak,
		"last_check":     today
	}))
	file.close()

func load_level():
	if not FileAccess.file_exists("user://level.json"): return
	var file = FileAccess.open("user://level.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	user_level        = data.get("level", 0)
	level_streak      = data.get("level_streak", 0)
	level_fail_streak = data.get("fail_streak", 0)

func _load_level_check_date() -> String:
	if not FileAccess.file_exists("user://level.json"): return ""
	var file = FileAccess.open("user://level.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return ""
	return data.get("last_check", "")

# ─────────────────────────────────────────
#  DISPLAY
# ─────────────────────────────────────────
func refresh_display():
	var vbox = $Panel/ScrollContainer/VBoxContainer

	# League + level + streak header
	var league = Global.get_current_league()
	var season = Global.get_current_season()

	vbox.get_node("SeasonLabel").text  = season["emoji"] + " " + season["name"]
	vbox.get_node("LeagueName").text   = league["name"]
	vbox.get_node("LevelLabel").text   = "⚡ Level " + str(user_level)
	vbox.get_node("StreakLabel").text  = "🔥 " + str(Global.daily_streak) + " days"
	vbox.get_node("PYLabel").text      = "💰 " + str(Global.py_currency) + " PY"

	# League progress bar
	var pct   = league["progress_pct"]
	var filled = int(pct * 10)
	vbox.get_node("LeagueBar").text = "█".repeat(filled) + "░".repeat(10 - filled) + \
		"  " + str(league["pts_to_next"]) + " pts to next"

	# Badges summary
	var badges_lbl = vbox.get_node("BadgesLabel")
	badges_lbl.text = "🏅 " + str(Global.earned_badges.size()) + " badges"

	# Tabs
	var tabs = vbox.get_node("LeaderboardTabs")
	_populate_tab(tabs, 0, "today")
	_populate_tab(tabs, 1, "week")
	_populate_tab(tabs, 2, "alltime")

	# Open on the user's current league tab by default
	var league_idx = Global.current_league_idx
	tabs.current_tab = min(league_idx, tabs.get_tab_count() - 1)

func _populate_tab(tabs: TabContainer, tab_idx: int, mode: String):
	var scroll = tabs.get_tab_control(tab_idx)
	if not scroll: return
	var vbox = scroll.get_child(0) if scroll.get_child_count() > 0 else null
	if not vbox: return
	for child in vbox.get_children(): child.queue_free()

	# Get the user's own entry
	var user_pts = 0.0
	match mode:
		"today":   user_pts = Global.get_points_today()
		"week":    user_pts = _get_week_total()
		"alltime": user_pts = Global.get_points_alltime()

	# Build user entry (single player game — show only the user)
	_add_leaderboard_entry(vbox, 1, _get_username(), user_pts, user_level,
		Global.earned_badges, Global.get_current_league(), mode)

	# League ladder below
	vbox.add_child(HSeparator.new())
	_build_league_ladder(vbox)

func _get_week_total() -> float:
	# Sum points from Monday of the current week to today
	var total    = 0.0
	var unix_now = Time.get_unix_time_from_system()
	var now_dt   = Time.get_datetime_dict_from_unix_time(unix_now)
	# Godot weekday: 0=Sun, 1=Mon ... 6=Sat
	var weekday  = now_dt.get("weekday", 1)
	var days_since_monday = (weekday + 6) % 7  # Mon=0
	for i in range(days_since_monday + 1):
		var unix_day = unix_now - (i * 86400)
		var dt       = Time.get_datetime_dict_from_unix_time(unix_day)
		var date_str = "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]
		total += Global.points_history.get(date_str, 0.0)
	return total

func _get_username() -> String:
	if FileAccess.file_exists("user://profile.json"):
		var file = FileAccess.open("user://profile.json", FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if data and data.has("username"):
			return data.get("username", "You")
	return "You"

func _add_leaderboard_entry(vbox: VBoxContainer, rank: int, name: String,
		pts: float, level: int, badges: Array, league: Dictionary, mode: String):

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 80)
	vbox.add_child(row)

	# Rank
	var rank_lbl = Label.new()
	rank_lbl.text = "#" + str(rank)
	rank_lbl.add_theme_font_size_override("font_size", 48)
	rank_lbl.custom_minimum_size = Vector2(40, 0)
	row.add_child(rank_lbl)

	var info_col = VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info_col)

	# Name + league
	var name_row = HBoxContainer.new()
	info_col.add_child(name_row)

	var name_lbl = Label.new()
	name_lbl.text = name
	name_lbl.add_theme_font_size_override("font_size", 48)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	name_row.add_child(name_lbl)

	var league_lbl = Label.new()
	league_lbl.text = " " + league["name"]
	league_lbl.add_theme_font_size_override("font_size", 48)
	league_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	name_row.add_child(league_lbl)

	# Level + streak
	var meta_lbl = Label.new()
	meta_lbl.text = "⚡ Lv." + str(level) + "  🔥 " + str(Global.daily_streak) + " days"
	meta_lbl.add_theme_font_size_override("font_size", 48)
	info_col.add_child(meta_lbl)

	# Badges (show up to 5)
	if not badges.is_empty():
		var badge_row = HBoxContainer.new()
		badge_row.add_theme_constant_override("separation", 4)
		info_col.add_child(badge_row)
		var shown = min(5, badges.size())
		for i in range(shown):
			for badge_def in Global.ALL_BADGES:
				if badge_def["id"] == badges[i]:
					var bl = Label.new()
					bl.text = badge_def["name"].split(" ")[0]  # just the emoji part
					bl.add_theme_font_size_override("font_size", 48)
					bl.add_theme_color_override("font_color",
						Global.BADGE_TIER_COLORS.get(badge_def.get("tier","bronze"), Color.WHITE))
					badge_row.add_child(bl)
					break
		if badges.size() > 5:
			var more = Label.new()
			more.text = " +" + str(badges.size() - 5)
			more.add_theme_font_size_override("font_size", 48)
			more.add_theme_color_override("font_color", Color(0.5,0.5,0.5))
			badge_row.add_child(more)

	# Points
	var pts_lbl = Label.new()
	var pts_label: String 
	match mode:
		"today":   str(snappedf(pts,0.1)) + " pts\ntoday"
		"week":    str(snappedf(pts,0.1)) + " pts\nthis week"
		"alltime": str(snappedf(pts,0.1)) + " pts\nall time"
		_:         str(snappedf(pts,0.1)) + " pts"
	pts_lbl.text = pts_label
	pts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pts_lbl.add_theme_font_size_override("font_size", 48)
	pts_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	row.add_child(pts_lbl)

func _build_league_ladder(container: VBoxContainer):
	var title = Label.new()
	title.text = "League Progression"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	container.add_child(title)

	var all_time = int(Global.get_points_alltime())
	for i in range(Global.LEAGUE_NAMES.size() - 1, -1, -1):
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		container.add_child(row)

		var is_current  = (i == Global.current_league_idx)
		var is_achieved = all_time >= Global.LEAGUE_THRESHOLDS[i]

		var name_lbl = Label.new()
		name_lbl.text = Global.LEAGUE_NAMES[i]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 48 if is_current else 36)
		if is_current:
			name_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
		elif not is_achieved:
			name_lbl.add_theme_color_override("font_color", Color(0.35,0.35,0.35))
		row.add_child(name_lbl)

		var pts_lbl = Label.new()
		pts_lbl.text = str(Global.LEAGUE_THRESHOLDS[i]) + " pts"
		pts_lbl.add_theme_font_size_override("font_size", 48)
		pts_lbl.add_theme_color_override("font_color",
			Color(0.5,0.5,0.5) if not is_achieved else Color(0.6,0.9,0.6))
		row.add_child(pts_lbl)

		if is_current:
			var cur_lbl = Label.new()
			cur_lbl.text = "← YOU"
			cur_lbl.add_theme_font_size_override("font_size", 48)
			cur_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
			row.add_child(cur_lbl)

func _on_badge_earned_leaderboard(_badge: Dictionary):
	refresh_display()

func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		Global.load_points()    # ← reload from disk every time leaderboard is opened
		refresh_display()
