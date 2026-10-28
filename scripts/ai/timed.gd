class_name Timed
extends RefCounted
## Espera el resultado de una operación asíncrona con un TIEMPO MÁXIMO REAL.
##
## Antes, la llamada hacía `await stream.next_token()` y solo miraba el reloj cuando
## llegaba un token: si el motor de IA no devolvía nunca el primero, el juego se
## quedaba «pensando» para siempre. Aquí la operación corre por su cuenta y quien
## espera comprueba el reloj en cada fotograma, así que el límite se cumple siempre.
##
## Uso:  var r := await Timed.run(func(): return await algo(), 30000)
##       if r["ok"]: r["value"]   else: r["timeout"] == true


## Ejecuta `job` (un Callable que puede usar await) y espera como mucho timeout_ms.
## Devuelve {ok: bool, value, timeout: bool, ms: int}.
static func run(job: Callable, timeout_ms: int, cancel_flag: Dictionary = {}) -> Dictionary:
	var box := {"done": false, "value": null}
	_runner(job, box)
	var tree := Engine.get_main_loop() as SceneTree
	var t0 := Time.get_ticks_msec()
	while not box["done"]:
		if cancel_flag.get("cancel", false):
			return {"ok": false, "value": null, "timeout": false, "cancelled": true, "ms": Time.get_ticks_msec() - t0}
		if Time.get_ticks_msec() - t0 > timeout_ms:
			return {"ok": false, "value": null, "timeout": true, "ms": Time.get_ticks_msec() - t0}
		await tree.process_frame
	return {"ok": true, "value": box["value"], "timeout": false, "ms": Time.get_ticks_msec() - t0}


static func _runner(job: Callable, box: Dictionary) -> void:
	box["value"] = await job.call()
	box["done"] = true
