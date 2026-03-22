extends Control

func _ready():
	Global.load_points()
	refresh()

func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		Global.load_points()
		refresh()

func refresh():
	refresh_today()
	refresh_week()
	refresh_alltime()

func refresh_today():
	var panel = $Panel/VBoxContainer/PeriodTabs/TodayPanel/VBoxContainer
	var points = snappedf(Global.get_points_today(), 0.1)
	panel.get_node("PointsLabel").text = "⭐ " + str(points) + " points today"
	panel.get_node("MessageLabel").text = get_message(points)

func refresh_week():
	var panel = $Panel/VBoxContainer/PeriodTabs/WeekPanel/VBoxContainer
	var total = snappedf(Global.get_points_week(), 0.1)
	panel.get_node("PointsLabel").text = "⭐ " + str(total) + " points this week"

	# Show each day of the week
	var list = panel.get_node("DaysList")
	for child in list.get_children():
		child.queue_free()

	var unix_now = Time.get_unix_time_from_system()
	for i in range(7):
		var unix_day = unix_now - (i * 86400)
		var datetime = Time.get_datetime_dict_from_unix_time(unix_day)
		var date = "%04d-%02d-%02d" % [datetime.year, datetime.month, datetime.day]
		var pts = snappedf(Global.points_history.get(date, 0.0), 0.1)
		var label = Label.new()
		var day_name = "Today" if i == 0 else date
		label.text = day_name + ":  " + str(pts) + " pts"
		list.add_child(label)

	panel.get_node("MessageLabel").text = get_message(total)

func refresh_alltime():
	var panel = $Panel/VBoxContainer/PeriodTabs/AllTimePanel/VBoxContainer
	var total = snappedf(Global.get_points_alltime(), 0.1)
	panel.get_node("PointsLabel").text = "⭐ " + str(total) + " points total"

	# Find best day
	var best_pts = 0.0
	var best_date = "—"
	for date in Global.points_history.keys():
		if Global.points_history[date] > best_pts:
			best_pts = Global.points_history[date]
			best_date = date
	panel.get_node("BestDayLabel").text = "🏆 Best day: " + str(snappedf(best_pts, 0.1)) + " pts on " + best_date

	panel.get_node("MessageLabel").text = get_message(total)

func get_message(points: float) -> String:
	if points == 0:
		return "Log your meals to earn points!"
	elif points < 1:
		return "Good start — keep going!"
	elif points < 3:
		return "Nice work! You're on track 💪"
	elif points < 7:
		return "Great consistency this week! 🔥"
	else:
		return "Outstanding! You're crushing it! 🏆"
