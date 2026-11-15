extends TileMapLayer

const TOTAL_ERRORS := 1000000
const PER_FRAME := 1000

var done := 0

func _process(_delta):
	if done >= TOTAL_ERRORS:
		set_process(false)
		return
	for i in PER_FRAME:
		push_error("Test error %d" % done)
		done += 1
