extends Control

const Battle = preload("res://scripts/core/battle.gd")
const Arena = preload("res://scripts/ui/arena.gd")
const SequenceBar = preload("res://scripts/ui/sequence_bar.gd")
const Rules = preload("res://scripts/core/rules.gd")
const PAPER = Color("e5ddc8")
const MUTED = Color("95a29b")
const BRONZE = Color("9c8b65")
const FIRE = Color("ed8953")

var battle = Battle.new()
var defaults: Dictionary
var playing: bool = false
var speed_halves: int = 2
var tick_credit: int = 0
var logged_events: int = 0
var actor_widgets: Array = []
var input_controls: Array = []
var title_font: SystemFont
var body_font: SystemFont
var arena: Control
var play_button: Button
var frame_label: Label
var log_view: RichTextLabel
var capture_path: String = ""
var capture_countdown: int = 8
var game_display: HBoxContainer
var game_toolbar: PanelContainer
var tech_panel: PanelContainer
var tech_toggle: Button
var tech_scroll: ScrollContainer
var step_button: Button
var speed_control: OptionButton
var fps_label: Label
var spell_inputs: Dictionary = {}
var timing_inputs: Dictionary = {}
var fps_update_time: float = 0.0
var summary_overlay: Control
var summary_title: Label
var summary_labels: Array = []
var summary_opened: bool = false
var summary_button: Button


func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(1200, 900))
	defaults = JSON.parse_string(FileAccess.get_file_as_string("res://data/duel.json"))
	body_font = SystemFont.new()
	body_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	title_font = SystemFont.new()
	title_font.font_names = PackedStringArray(["STZhongsong", "SimSun", "Noto Serif CJK SC"])
	build_theme()
	build_ui()
	reset_battle()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		if argument == "--preview-battle":
			prepare_first_frame()
			for i in range(179):
				advance_frame()
		if argument == "--show-tech":
			toggle_technical()
		if argument == "--preview-summary":
			prepare_first_frame()
			while not battle.finished:
				advance_frame()


func build_theme() -> void:
	var skin := Theme.new()
	skin.default_font = body_font
	skin.default_font_size = 14
	skin.set_color("font_color", "Label", PAPER)
	skin.set_color("font_color", "Button", PAPER)
	skin.set_color("font_hover_color", "Button", Color("fff1d3"))
	skin.set_color("font_disabled_color", "Button", Color("63706c"))
	for type_name in ["Button", "OptionButton"]:
		var padding: int = 5 if type_name == "OptionButton" else 9
		skin.set_stylebox("normal", type_name, box(Color("142529"), Color("42504a"), padding))
		skin.set_stylebox("hover", type_name, box(Color("223837"), BRONZE, padding))
		skin.set_stylebox("pressed", type_name, box(Color("30413a"), BRONZE, padding))
		skin.set_stylebox("disabled", type_name, box(Color("111c1f"), Color("2b3935"), padding))
		skin.set_stylebox("focus", type_name, box(Color(0, 0, 0, 0), BRONZE, padding))
	skin.set_stylebox("normal", "LineEdit", box(Color("0c191c"), Color("3b4c45"), 7))
	skin.set_stylebox("focus", "LineEdit", box(Color("122124"), BRONZE, 7))
	skin.set_color("font_color", "LineEdit", PAPER)
	skin.set_color("font_uneditable_color", "LineEdit", MUTED)
	skin.set_stylebox("panel", "PopupMenu", box(Color("142529"), BRONZE, 8))
	skin.set_color("font_color", "PopupMenu", PAPER)
	theme = skin


func box(background: Color, border: Color, padding: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func label(value: String, font_size: int = 14, color: Color = PAPER) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node


func button(value: String, callback: Callable) -> Button:
	var node := Button.new()
	node.text = value
	node.custom_minimum_size = Vector2(110, 40)
	node.pressed.connect(callback)
	return node


func gap(parent: BoxContainer) -> void:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)


func build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("091316")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	header.add_to_group("game_display")
	layout.add_child(header)
	var brand := label("斗法", 24)
	brand.add_theme_font_override("font", title_font)
	header.add_child(brand)
	gap(header)
	game_display = HBoxContainer.new()
	game_display.name = "GameDisplay"
	game_display.add_to_group("game_display")
	game_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_display.add_theme_constant_override("separation", 16)
	layout.add_child(game_display)
	build_actor_card(game_display, 0)
	arena = Arena.new()
	arena.battle = battle
	arena.title_font = title_font
	arena.body_font = body_font
	arena.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena.custom_minimum_size = Vector2(480, 300)
	game_display.add_child(arena)
	build_actor_card(game_display, 1)
	build_toolbar(layout)
	tech_toggle = button("▸  技术调整", toggle_technical)
	tech_toggle.name = "TechnicalToggle"
	tech_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tech_toggle.custom_minimum_size.y = 34
	tech_toggle.add_theme_stylebox_override("normal", box(Color("111b20"), Color("35424a"), 7))
	layout.add_child(tech_toggle)
	build_technical_panel(layout)
	build_summary()


func build_actor_card(parent: Control, side: int) -> void:
	var definition: Dictionary = defaults.actors[side]
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 224
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", box(Color("101e21"), Color("3a463d"), 16))
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var name_label := label(definition.name, 22)
	name_label.add_theme_font_override("font", title_font)
	column.add_child(name_label)
	column.add_child(label(definition.get("realm", "练气前期"), 12, MUTED))
	var widget: Dictionary = {}
	widget.passives_label = label("", 12, Color("a3bfb0"))
	column.add_child(widget.passives_label)
	var resources := VBoxContainer.new()
	resources.add_theme_constant_override("separation", 8)
	column.add_child(resources)
	for resource in ["hp", "mana", "mind"]:
		var resource_box := VBoxContainer.new()
		resource_box.add_theme_constant_override("separation", 3)
		resources.add_child(resource_box)
		var line := HBoxContainer.new()
		resource_box.add_child(line)
		line.add_child(label({"hp": "血量", "mana": "法力", "mind": "神识"}[resource], 13, MUTED))
		gap(line)
		var amount := label("", 13)
		line.add_child(amount)
		widget[resource + "_label"] = amount
		var bar := ProgressBar.new()
		bar.custom_minimum_size.y = 7
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", box(Color("081215"), Color("081215")))
		var fill := StyleBoxFlat.new()
		fill.bg_color = {"hp": Color("ac6453"), "mana": Color("5f9993"), "mind": BRONZE}[resource]
		bar.add_theme_stylebox_override("fill", fill)
		resource_box.add_child(bar)
		widget[resource + "_bar"] = bar
	var status := VBoxContainer.new()
	status.add_theme_constant_override("separation", 4)
	column.add_child(status)
	var state := label("待战", 13, FIRE)
	status.add_child(state)
	widget.state = state
	var progress := ProgressBar.new()
	progress.custom_minimum_size.y = 4
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background", box(Color("081215"), Color("081215")))
	var fill := StyleBoxFlat.new()
	fill.bg_color = BRONZE
	progress.add_theme_stylebox_override("fill", fill)
	status.add_child(progress)
	widget.cast_bar = progress
	widget.sequence = SequenceBar.new()
	widget.sequence.side = side
	widget.sequence.set_actions(definition.actions)
	column.add_child(widget.sequence)
	widget.entities_label = label("", 13, Color("9dbdb6"))
	column.add_child(widget.entities_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	actor_widgets.append(widget)


func build_toolbar(parent: Control) -> void:
	game_toolbar = PanelContainer.new()
	game_toolbar.add_to_group("game_display")
	game_toolbar.add_theme_stylebox_override("panel", box(Color("101e21"), Color("3a463d"), 8))
	parent.add_child(game_toolbar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	game_toolbar.add_child(row)
	play_button = button("开始", toggle_play)
	play_button.add_theme_stylebox_override("normal", box(Color("713e2d"), Color("bb8050"), 10))
	row.add_child(play_button)
	row.add_child(button("重开", reset_battle))
	summary_button = button("结算", show_summary)
	summary_button.visible = false
	row.add_child(summary_button)


func build_summary() -> void:
	summary_overlay = Control.new()
	summary_overlay.name = "BattleSummary"
	summary_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena.add_child(summary_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.03, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	summary_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	summary_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 440
	panel.add_theme_stylebox_override("panel", box(Color("101e21"), BRONZE, 24))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	summary_title = label("", 24)
	summary_title.add_theme_font_override("font", title_font)
	summary_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(summary_title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	grid.add_child(label(""))
	for side in range(2):
		var name_label := label(defaults.actors[side].name, 15, Color("8ab7ae") if side == 0 else Color("ce9a84"))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(name_label)
	for title in ["造成伤害", "承受伤害", "护盾承伤", "法器承伤", "本体承伤"]:
		grid.add_child(label(title, 14, PAPER if summary_labels.size() < 2 else MUTED))
		var values: Array = []
		for side in range(2):
			var value := label("0", 17)
			value.custom_minimum_size.x = 90
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(value)
			values.append(value)
		summary_labels.append(values)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	gap(footer)
	footer.add_child(button("关闭", hide_summary))
	summary_overlay.visible = false


func show_summary() -> void:
	if not battle.finished:
		return
	var statistics: Array = battle.get_statistics()
	summary_title.text = {"left_win": "青衫修士胜", "right_win": "赤衣修士胜", "double_ko": "同归于尽", "stalemate": "僵持", "timeout": "未分胜负", "effect_limit": "结算中止"}.get(battle.result, "结算")
	for side in range(2):
		var totals: Dictionary = statistics[side]
		var values := [totals.damage_dealt_milli, totals.damage_taken_milli,
			totals.taken_by_kind.get("shield", 0), totals.taken_by_kind.get("artifact", 0), totals.taken_by_kind.get("cultivator", 0)]
		for i in range(values.size()):
			summary_labels[i][side].text = number(float(values[i]) / 1000)
	summary_overlay.visible = true
	arena.summary_visible = true
	summary_opened = true


func hide_summary() -> void:
	if summary_overlay != null:
		summary_overlay.visible = false
		arena.summary_visible = false


func toggle_technical() -> void:
	tech_panel.visible = not tech_panel.visible
	tech_toggle.text = "▾  技术调整" if tech_panel.visible else "▸  技术调整"


func build_technical_panel(parent: Control) -> void:
	tech_panel = PanelContainer.new()
	tech_panel.name = "TechnicalTools"
	tech_panel.add_to_group("technical_tools")
	tech_panel.custom_minimum_size.y = 240
	tech_panel.add_theme_stylebox_override("panel", box(Color("111b20"), Color("35424a"), 12))
	parent.add_child(tech_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	tech_panel.add_child(row)
	tech_scroll = ScrollContainer.new()
	tech_scroll.name = "ParameterScroll"
	tech_scroll.custom_minimum_size.x = 610
	tech_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tech_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(tech_scroll)
	var settings := HBoxContainer.new()
	settings.add_theme_constant_override("separation", 12)
	tech_scroll.add_child(settings)
	for side in range(2):
		build_actor_settings(settings, side)
	build_spell_settings(settings)
	var inspector := VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 6)
	row.add_child(inspector)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	inspector.add_child(controls)
	step_button = button("+1帧", single_step)
	step_button.custom_minimum_size = Vector2(106, 34)
	controls.add_child(step_button)
	speed_control = OptionButton.new()
	for value in ["0.5x", "1x", "2x", "4x"]:
		speed_control.add_item(value)
	speed_control.select(1)
	speed_control.custom_minimum_size = Vector2(104, 34)
	speed_control.item_selected.connect(func(index: int): speed_halves = [1, 2, 4, 8][index]; tick_credit = 0)
	controls.add_child(speed_control)
	var diagnostics := HBoxContainer.new()
	inspector.add_child(diagnostics)
	frame_label = label("", 12, Color("b5c3cb"))
	diagnostics.add_child(frame_label)
	gap(diagnostics)
	fps_label = label("60Hz · 60FPS", 11, Color("859ca8"))
	diagnostics.add_child(fps_label)
	build_log(inspector)
	tech_panel.visible = false


func settings_column(parent: Control, title: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 192
	column.add_theme_constant_override("separation", 6)
	parent.add_child(column)
	column.add_child(label(title, 13, Color("b5c3cb")))
	return column


func number_input(grid: GridContainer, title: String, value: float, minimum: float, maximum: float, increment: float = 1) -> SpinBox:
	grid.add_child(label(title, 12, Color("859ca8")))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = increment
	spin.value = value
	spin.custom_minimum_size.x = 90
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(spin)
	input_controls.append(spin)
	return spin


func settings_grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	return grid


func build_actor_settings(parent: Control, side: int) -> void:
	var definition: Dictionary = defaults.actors[side]
	var widget: Dictionary = actor_widgets[side]
	var column := settings_column(parent, "青方" if side == 0 else "赤方")
	var grid := settings_grid(column)
	widget.hp_input = number_input(grid, "HP", definition.hp, 1, 100000)
	widget.mana_input = number_input(grid, "MP", definition.mana, 0, 100000)
	widget.quality_input = number_input(grid, "Q", float(definition.quality_permille) / 1000, 0.1, 10, 0.1)
	widget.mind_input = number_input(grid, "神识", definition.get("mind_capacity", 2), 0, 64)


func build_spell_settings(parent: Control) -> void:
	var column := settings_column(parent, "参数")
	var grid := settings_grid(column)
	timing_inputs.cast_interval_frames = number_input(grid, "间隔 s", float(defaults.get("cast_interval_frames", 90)) / 60, 0, 600, 0.1)
	timing_inputs.shield_cooldown_frames = number_input(grid, "护盾 CD", float(defaults.get("shield_cooldown_frames", 1200)) / 60, 0, 600, 0.1)
	timing_inputs.sword_cooldown_frames = number_input(grid, "剑 CD", float(defaults.get("sword_cooldown_frames", 1200)) / 60, 0, 600, 0.1)
	timing_inputs.sword_attack_cooldown_frames = number_input(grid, "剑内 CD", float(defaults.get("sword_attack_cooldown_frames", 180)) / 60, 0, 600, 0.1)
	spell_inputs.sword_windup_frames = number_input(grid, "剑前摇 F", defaults.get("sword_windup_frames", 6), 0, 3600)
	spell_inputs.sword_outbound_frames = number_input(grid, "剑去程 F", defaults.get("sword_outbound_frames", 45), 1, 3600)
	spell_inputs.sword_return_frames = number_input(grid, "剑返程 F", defaults.get("sword_return_frames", 45), 1, 3600)
	for field in ["mana_cost", "windup_frames", "flight_frames", "recovery_frames"]:
		var titles := {"mana_cost": "火球 C", "windup_frames": "火球前摇", "flight_frames": "飞行帧", "recovery_frames": "火球后摇"}
		spell_inputs[field] = number_input(grid, titles[field], defaults.spell[field], 1, 100000 if field == "mana_cost" else 3600)
	spell_inputs.shield_cost = number_input(grid, "护盾 C", defaults.get("shield_cost", 50), 1, 100000)
	spell_inputs.sword_cost = number_input(grid, "青云剑 C", defaults.get("sword_cost", 10), 1, 100000)


func build_log(parent: Control) -> void:
	parent.add_child(label("日志", 12, Color("b5c3cb")))
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.add_theme_font_size_override("normal_font_size", 12)
	log_view.add_theme_color_override("default_color", Color("b5c3cb"))
	parent.add_child(log_view)


func read_configuration() -> Dictionary:
	var settings: Dictionary = defaults.duplicate(true)
	for side in range(2):
		var widgets: Dictionary = actor_widgets[side]
		settings.actors[side].hp = int(widgets.hp_input.value)
		settings.actors[side].mana = int(widgets.mana_input.value)
		settings.actors[side].quality_permille = roundi(widgets.quality_input.value * 1000)
		settings.actors[side].mind_capacity = int(widgets.mind_input.value)
		settings.actors[side].actions = widgets.sequence.get_actions()
	for field in spell_inputs:
		if defaults.spell.has(field):
			settings.spell[field] = int(spell_inputs[field].value)
		else:
			settings[field] = int(spell_inputs[field].value)
	for field in timing_inputs:
		settings[field] = roundi(timing_inputs[field].value * 60)
	return settings


func lock_inputs(locked: bool) -> void:
	for widgets in actor_widgets:
		widgets.sequence.set_editable(not locked)
	for control in input_controls:
		if control is SpinBox:
			control.editable = not locked
		else:
			control.disabled = locked


func reset_battle() -> void:
	playing = false
	hide_summary()
	summary_opened = false
	tick_credit = 0
	battle.reset(read_configuration())
	logged_events = 0
	log_view.clear()
	lock_inputs(false)
	update_ui()


func prepare_first_frame() -> void:
	if battle.frame == -1:
		battle.reset(read_configuration())
		lock_inputs(true)


func toggle_play() -> void:
	if battle.finished:
		reset_battle()
	prepare_first_frame()
	playing = not playing
	tick_credit = 0
	update_ui()


func single_step() -> void:
	playing = false
	tick_credit = 0
	prepare_first_frame()
	advance_frame()


func _physics_process(_delta: float) -> void:
	if not playing:
		return
	tick_credit += speed_halves
	while tick_credit >= 2 and playing:
		tick_credit -= 2
		advance_frame()


func advance_frame() -> void:
	battle.step()
	while logged_events < battle.events.size():
		append_event(battle.events[logged_events])
		logged_events += 1
	if battle.finished:
		playing = false
		if not summary_opened:
			show_summary()
	update_ui()


func update_ui() -> void:
	if actor_widgets.size() != 2:
		return
	for side in range(2):
		var actor: Dictionary = battle.actors[side]
		var widgets: Dictionary = actor_widgets[side]
		var passive_names := PackedStringArray()
		for passive_id in actor.passives:
			passive_names.append(battle.config.library.passives[passive_id].name)
		widgets.passives_label.text = "被动 · " + "、".join(passive_names)
		widgets.passives_label.visible = not passive_names.is_empty()
		widgets.hp_label.text = "%s / %s" % [number(float(actor.hp_milli) / 1000.0), number(float(actor.max_hp_milli) / 1000.0)]
		widgets.mana_label.text = "%d / %d" % [actor.mana, actor.max_mana]
		widgets.hp_bar.max_value = actor.max_hp_milli
		widgets.hp_bar.value = actor.hp_milli
		widgets.mana_bar.max_value = maxi(1, int(actor.max_mana))
		widgets.mana_bar.value = actor.mana
		var mind: int = battle.mind_used(actor.entity_id)
		var remaining_mind: int = maxi(0, int(actor.mind_capacity) - mind)
		widgets.mind_label.text = "%d / %d" % [remaining_mind, actor.mind_capacity]
		widgets.mind_bar.max_value = maxi(1, int(actor.mind_capacity))
		widgets.mind_bar.value = remaining_mind
		widgets.sequence.set_active(int(actor.cast.sequence_slot) if not actor.cast.is_empty() else -1)
		if battle.finished:
			widgets.sequence.set_editable(true)
		var entity_names := PackedStringArray()
		for entity in battle.defenders(side):
			if entity.kind != "cultivator":
				entity_names.append("%s %s" % [entity.name, number(float(entity.hp_milli) / 1000)])
		widgets.entities_label.text = "\n".join(entity_names)
		widgets.entities_label.visible = not entity_names.is_empty()
		widgets.cast_bar.value = 0
		if actor.hp_milli <= 0:
			widgets.state.text = "倒下"
		elif battle.finished:
			widgets.state.text = "结束"
		elif actor.blocked:
			widgets.state.text = "待战" if actor.waiting == "no_actions" else "法力不支"
		elif actor.waiting == "mind":
			widgets.state.text = "神识不足"
		elif not actor.cast.is_empty():
			var cast: Dictionary = actor.cast
			widgets.state.text = "施法 · %s" % Rules.name({"ability": cast.ability, "mode": cast.mode})
			widgets.cast_bar.value = 100.0 * (battle.frame - int(cast.start_frame)) / maxi(1, int(cast.release_frame) - int(cast.start_frame))
		elif battle.frame >= 0 and int(actor.ready_frame) > battle.frame:
			widgets.state.text = "收势"
		elif battle.frame >= 0 and int(actor.next_cast_frame) > battle.frame:
			widgets.state.text = "调息"
			widgets.cast_bar.value = 100.0 * (battle.frame - int(actor.last_release_frame)) / maxi(1, int(actor.next_cast_frame) - int(actor.last_release_frame))
		elif actor.waiting == "cooldown":
			widgets.state.text = "冷却 %.1fs" % (maxi(0, int(actor.waiting_until) - battle.frame) / 60.0)
		else:
			widgets.state.text = "待战" if battle.frame < 0 else "等待"
	play_button.text = "再战" if battle.finished else ("暂停" if playing else ("开始" if battle.frame < 0 else "继续"))
	summary_button.visible = battle.finished
	frame_label.text = "F%04d · %.3fs" % [maxi(0, battle.frame), maxf(0, battle.frame) / 60.0]


func append_event(event: Dictionary) -> void:
	var text: String = ""
	var color: String = "b4beb3"
	var side: int = int(event.get("side", 0))
	var prefix: String = "青" if side == 0 else "赤"
	var entity_id: int = int(event.get("entity_id", battle.actors[side].entity_id))
	var source: Dictionary = battle.entities.get(entity_id, {})
	if source.get("kind", "cultivator") == "artifact" and event.kind in ["cast", "release", "hit"]:
		prefix += "/" + str(source.name)
	match event.kind:
		"cast":
			text = "%s 施法·%s" % [prefix, Rules.name({"ability": event.ability, "mode": event.mode})]
			if event.get("from_deferred", false):
				text += "·优先"
			color = "7f9289"
		"passive":
			text = "%s 被动·%s" % [prefix, event.name]
		"release":
			text = "%s MP −%d → %d" % [prefix, event.cost, event.mana] if int(event.cost) > 0 else prefix + " 攻击"
			if event.ability != "shield":
				text += " | D %d × %s × %d = %s" % [event.power_base,
					number(float(event.quality_permille) / 1000), event.damage_multiplier,
					number(float(event.damage_milli) / 1000)]
			color = "dfbc8a"
		"spawn":
			if source.get("kind", "") not in ["shield", "artifact"]:
				return
			text = "%s 生成%s HP %s" % [prefix, source.name, number(float(event.hp_milli) / 1000)]
		"hit":
			text = "%s 命中%s D %s" % [prefix, "青" if int(event.target) == 0 else "赤", number(float(event.damage_milli) / 1000)]
			color = "ed8953"
		"damage":
			text = "%s/%s HP %s → %s" % [prefix, event.name, number(float(event.hp_before) / 1000), number(float(event.hp_after) / 1000)]
		"death":
			text = "%s 倒下" % prefix
		"destroy", "expire":
			text = "%s %s%s" % [prefix, event.name, "到期" if event.kind == "expire" else "损毁"]
		"interrupt":
			text = "%s 施法中断·%s" % [prefix, event.reason]
		"launch":
			text = "%s 出击 → F%d" % [prefix, event.hit_frame]
		"return":
			text = "%s 返回" % prefix
		"defer":
			text = "%s 跳过%s CD→F%d" % [prefix, Rules.name(event.ability), event.ready_frame]
		"exhausted":
			text = "%s MP不足 %d/%d" % [prefix, event.mana, event.cost]
		"end":
			text = {"left_win": "青胜", "right_win": "赤胜", "double_ko": "同归于尽", "stalemate": "僵持", "timeout": "超时", "effect_limit": "触发上限"}.get(event.result, "")
			color = "e5ddc8"
	if not text.is_empty():
		log_view.append_text("[color=#%s]F%04d  %s[/color]\n" % [color, event.frame, text])


func number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else ("%.3f" % value).trim_suffix("0").trim_suffix("0")


func _process(delta: float) -> void:
	fps_update_time += delta
	if fps_update_time >= 0.5:
		fps_update_time = 0
		fps_label.text = "60Hz · %d/60FPS" % Engine.get_frames_per_second()
	if capture_path.is_empty():
		return
	capture_countdown -= 1
	if capture_countdown == 0:
		capture_screen.call_deferred()


func capture_screen() -> void:
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	var error: Error = screenshot.save_png(capture_path)
	print("CAPTURE: ", capture_path, " error=", error)
	get_tree().quit(int(error))
