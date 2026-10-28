extends Node
## Ejecuta el panel de diagnóstico del juego sin interfaz (para comprobarlo en CI/PC):
##   godot --headless --path . tests/eval/diag_run.tscn
func _ready() -> void:
	await get_tree().process_frame
	var brain := get_tree().root.get_node("Brain")
	await brain.load_all()
	var dp := DiagnosticsPanel.new()
	get_tree().root.add_child(dp)
	dp.open()
	dp._t_files()
	await dp._t_gemma()
	await dp._t_call()
	print("DIAG-INFORME\n" + dp.report.text)
	get_tree().quit()
