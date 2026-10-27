class_name UIKit
extends RefCounted
## Tema visual y utilidades para construir la interfaz táctil por código
## (textos grandes, botones amplios, paneles redondeados).

const C_BG := Color("1d2333")
const C_PANEL := Color("273049")
const C_PANEL2 := Color("323d5c")
const C_ACCENT := Color("ffc93c")
const C_GOOD := Color("2ecc71")
const C_BAD := Color("e74c3c")
const C_TEXT := Color("f4f1ea")
const C_MUTED := Color("aab3c5")
const C_BLUE := Color("4ea8de")

static var _theme: Theme


static func flat(color: Color, radius := 18, border := 0, border_color := Color.TRANSPARENT, margin := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.6
	s.content_margin_bottom = margin * 0.6
	s.anti_aliasing = true
	return s


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 26
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_color", "Button", Color("1b1b22"))
	t.set_color("font_hover_color", "Button", Color("1b1b22"))
	t.set_color("font_pressed_color", "Button", Color("1b1b22"))
	t.set_color("font_focus_color", "Button", Color("1b1b22"))
	t.set_color("font_disabled_color", "Button", Color(0.3, 0.3, 0.3))
	t.set_stylebox("normal", "Button", flat(C_ACCENT, 16, 0, Color.TRANSPARENT, 18))
	t.set_stylebox("hover", "Button", flat(C_ACCENT.lightened(0.15), 16, 0, Color.TRANSPARENT, 18))
	t.set_stylebox("pressed", "Button", flat(C_ACCENT.darkened(0.2), 16, 0, Color.TRANSPARENT, 18))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", flat(Color("7f8696"), 16, 0, Color.TRANSPARENT, 18))
	t.set_stylebox("panel", "PanelContainer", flat(C_PANEL, 22, 0, Color.TRANSPARENT, 18))
	t.set_stylebox("panel", "Panel", flat(C_PANEL, 22))
	t.set_stylebox("normal", "LineEdit", flat(Color("f4f1ea"), 12, 2, C_ACCENT, 12))
	t.set_stylebox("focus", "LineEdit", flat(Color("ffffff"), 12, 3, C_BLUE, 12))
	t.set_color("font_color", "LineEdit", Color("1b1b22"))
	t.set_color("font_placeholder_color", "LineEdit", Color("6b6f7a"))
	t.set_color("caret_color", "LineEdit", Color("1b1b22"))
	t.set_stylebox("background", "ProgressBar", flat(Color("161b29"), 10, 0, Color.TRANSPARENT, 0))
	t.set_stylebox("fill", "ProgressBar", flat(C_GOOD, 10, 0, Color.TRANSPARENT, 0))
	t.set_color("font_color", "ProgressBar", C_TEXT)
	t.set_stylebox("slider", "HSlider", flat(Color("161b29"), 8, 0, Color.TRANSPARENT, 6))
	t.set_stylebox("grabber_area", "HSlider", flat(C_ACCENT, 8, 0, Color.TRANSPARENT, 6))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(C_ACCENT, 8, 0, Color.TRANSPARENT, 6))
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_color("font_color", "CheckButton", C_TEXT)
	t.set_color("font_hover_color", "CheckButton", C_TEXT)
	t.set_color("font_pressed_color", "CheckButton", C_TEXT)
	t.set_color("font_color", "OptionButton", Color("1b1b22"))
	t.set_stylebox("normal", "OptionButton", flat(Color("f4f1ea"), 12, 0, Color.TRANSPARENT, 14))
	t.set_stylebox("hover", "OptionButton", flat(Color("ffffff"), 12, 0, Color.TRANSPARENT, 14))
	t.set_stylebox("pressed", "OptionButton", flat(Color("dddddd"), 12, 0, Color.TRANSPARENT, 14))
	t.set_stylebox("panel", "PopupMenu", flat(Color("f4f1ea"), 10, 0, Color.TRANSPARENT, 10))
	t.set_color("font_color", "PopupMenu", Color("1b1b22"))
	t.set_color("font_hover_color", "PopupMenu", Color("1b1b22"))
	t.set_font_size("font_size", "PopupMenu", 28)
	t.set_stylebox("hover", "PopupMenu", flat(C_ACCENT, 8, 0, Color.TRANSPARENT, 8))
	t.set_stylebox("panel", "TabContainer", flat(C_PANEL, 18, 0, Color.TRANSPARENT, 14))
	t.set_stylebox("tab_selected", "TabContainer", flat(C_ACCENT, 12, 0, Color.TRANSPARENT, 14))
	t.set_stylebox("tab_unselected", "TabContainer", flat(C_PANEL2, 12, 0, Color.TRANSPARENT, 14))
	t.set_stylebox("tab_hovered", "TabContainer", flat(C_PANEL2.lightened(0.1), 12, 0, Color.TRANSPARENT, 14))
	t.set_color("font_selected_color", "TabContainer", Color("1b1b22"))
	t.set_color("font_unselected_color", "TabContainer", C_TEXT)
	t.set_color("font_hovered_color", "TabContainer", C_TEXT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", C_TEXT)
	t.set_constant("scrollbar_h_separation", "ScrollContainer", 8)
	t.set_stylebox("scroll", "VScrollBar", flat(Color(0, 0, 0, 0.2), 6, 0, Color.TRANSPARENT, 4))
	t.set_stylebox("grabber", "VScrollBar", flat(C_MUTED, 6, 0, Color.TRANSPARENT, 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(C_ACCENT, 6, 0, Color.TRANSPARENT, 4))
	_theme = t
	return t


static func label(text: String, size := 26, color := C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, cb: Callable, color := C_ACCENT, min_h := 72, font := 28) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", font)
	if color != C_ACCENT:
		b.add_theme_stylebox_override("normal", flat(color, 16, 0, Color.TRANSPARENT, 18))
		b.add_theme_stylebox_override("hover", flat(color.lightened(0.15), 16, 0, Color.TRANSPARENT, 18))
		b.add_theme_stylebox_override("pressed", flat(color.darkened(0.2), 16, 0, Color.TRANSPARENT, 18))
		var dark_text := color.get_luminance() > 0.55
		var fc := Color("1b1b22") if dark_text else Color.WHITE
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(k, fc)
	b.pressed.connect(func() -> void:
		Audio.play("tap", -6.0)
		cb.call())
	return b


static func panel(color := C_PANEL, radius := 22, margin := 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(color, radius, 0, Color.TRANSPARENT, margin))
	return p


static func vbox(sep := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	# En filas horizontales, las etiquetas cortas no deben partirse letra a letra
	h.sort_children.connect(func() -> void:
		for c in h.get_children():
			if c is Label and not (c.size_flags_horizontal & Control.SIZE_EXPAND) and c.custom_minimum_size.x <= 0.0:
				c.autowrap_mode = TextServer.AUTOWRAP_OFF)
	return h


static func spacer(h := 0, w := 0, expand := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func bar(value: float, max_v := 100.0, color := C_GOOD, h := 22) -> ProgressBar:
	var b := ProgressBar.new()
	b.max_value = max_v
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_stylebox_override("fill", flat(color, 10, 0, Color.TRANSPARENT, 0))
	return b


## Capa a pantalla completa con fondo oscurecido y un panel centrado.
static func modal(parent: Node, width := 900.0, height := 0.0) -> Dictionary:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.theme = theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var p := panel()
	p.custom_minimum_size = Vector2(width, height)
	center.add_child(p)
	var v := vbox(14)
	p.add_child(v)
	parent.add_child(layer)
	return {"layer": layer, "panel": p, "box": v}


static func money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if v < 0 else "") + "$" + out
