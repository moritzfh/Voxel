extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var file := FileAccess.open("user://spielstand.dat",FileAccess.READ)
	if not file: print("FAIL Exported test map did not save"); quit(1); return
	var value: Dictionary = file.get_var(false)
	var types := {}
	for record in value.get("wildlife",[]):
		if record.get("enemy",false): types[record.get("species","")] = true
	var ok := types.size()==6
	print(("PASS " if ok else "FAIL ")+"Actual exported EXE generated and saved all six enemy types: "+str(types.keys()))
	quit(0 if ok else 1)
