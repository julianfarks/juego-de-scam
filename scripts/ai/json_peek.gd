class_name JsonPeek
extends RefCounted
## Lee el valor de un campo de texto de un JSON que todavía se está generando, para
## mostrar los subtítulos del cliente mientras el modelo escribe.


static func string_field(partial: String, field: String) -> String:
	var key := "\"%s\"" % field
	var k := partial.find(key)
	if k < 0:
		return ""
	var i := partial.find("\"", partial.find(":", k + key.length()) + 1)
	if i < 0:
		return ""
	var out := ""
	var esc := false
	for idx in range(i + 1, partial.length()):
		var ch := partial[idx]
		if esc:
			match ch:
				"n":
					out += " "
				"t":
					out += " "
				_:
					out += ch
			esc = false
		elif ch == "\\":
			esc = true
		elif ch == "\"":
			break
		else:
			out += ch
	return out


## true si el valor de texto del campo ya está cerrado (comillas de cierre generadas).
static func string_field_closed(partial: String, field: String) -> bool:
	var key := "\"%s\"" % field
	var k := partial.find(key)
	if k < 0:
		return false
	var i := partial.find("\"", partial.find(":", k + key.length()) + 1)
	if i < 0:
		return false
	var esc := false
	for idx in range(i + 1, partial.length()):
		var ch := partial[idx]
		if esc:
			esc = false
		elif ch == "\\":
			esc = true
		elif ch == "\"":
			return true
	return false
