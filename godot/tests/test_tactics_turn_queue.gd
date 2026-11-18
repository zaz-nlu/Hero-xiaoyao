extends "res://tests/test_case.gd"

const TurnQueue = preload("res://core/tactics/turn_queue.gd")


func _same_list(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true


func test_ct_rate() -> void:
	assert_eq(TurnQueue.ct_rate(8), 18)
	assert_eq(TurnQueue.ct_rate(50), 60)
	assert_eq(TurnQueue.THRESHOLD, 100)


func test_faster_unit_acts_more_often() -> void:
	# ct_rate = 10 + speed。速度 30 与 10 的刻度是 40 : 20 = 2:1；
	# 若用速度 20 与 10 则是 30 : 20 = 1.5:1。
	var queue = TurnQueue.new()
	queue.add("fast", 30)
	queue.add("slow", 10)
	var fast := 0
	var slow := 0
	for _i in range(30):
		var actor: String = queue.next_actor()
		if actor == "fast":
			fast += 1
		elif actor == "slow":
			slow += 1
		queue.end_turn(actor)
	assert_eq(fast + slow, 30)
	assert_true(
		fast >= slow * 2 - 3,
		"ct_rate 40 vs 20 should act about twice as often: %d vs %d" % [fast, slow]
	)


func test_tie_breaks_by_speed_then_join_order() -> void:
	var queue = TurnQueue.new()
	queue.add("slow", 10, TurnQueue.THRESHOLD)
	queue.add("fast", 30, TurnQueue.THRESHOLD)
	assert_eq(queue.next_actor(), "fast", "higher speed goes first")
	queue.end_turn("fast")
	assert_eq(queue.next_actor(), "slow")
	var joined = TurnQueue.new()
	joined.add("a", 10, TurnQueue.THRESHOLD)
	joined.add("b", 10, TurnQueue.THRESHOLD)
	assert_eq(joined.next_actor(), "a", "equal speed uses join order")
	joined.end_turn("a")
	assert_eq(joined.next_actor(), "b")


func test_next_actor_does_not_spend_ct() -> void:
	var queue = TurnQueue.new()
	queue.add("a", 10, TurnQueue.THRESHOLD)
	assert_eq(queue.next_actor(), "a")
	assert_eq(queue.ct_of("a"), TurnQueue.THRESHOLD, "ct is not deducted until end_turn")
	queue.end_turn("a")
	assert_eq(queue.ct_of("a"), 0)


func test_preview_matches_actual_and_does_not_mutate() -> void:
	var queue = TurnQueue.new()
	queue.add("a", 20)
	queue.add("b", 10)
	var before_ct := queue.ct_of("a")
	var preview: Array = queue.preview(8)
	assert_eq(queue.ct_of("a"), before_ct, "preview does not mutate ct")
	assert_eq(preview.size(), 8)
	var actual: Array = []
	for _i in range(8):
		var actor: String = queue.next_actor()
		actual.append(actor)
		queue.end_turn(actor)
	assert_true(_same_list(preview, actual), "preview matches the real order")
	assert_true(preview.has("a") and preview.has("b"), "both units appear")


func test_add_ct_grants_immediate_turn() -> void:
	var queue = TurnQueue.new()
	queue.add("a", 10)
	queue.add("b", 10)
	queue.add_ct("b", 100)
	assert_eq(queue.next_actor(), "b", "surprise bonus jumps the queue")
	assert_eq(queue.ct_of("b"), 100)


func test_remove_drops_unit() -> void:
	var queue = TurnQueue.new()
	queue.add("a", 10)
	queue.add("b", 10)
	queue.remove("b")
	for _i in range(5):
		var actor: String = queue.next_actor()
		assert_eq(actor, "a")
		queue.end_turn(actor)
	assert_eq(queue.ct_of("b"), 0, "removed unit has no ct")


func test_snapshot_and_restore() -> void:
	var queue = TurnQueue.new()
	queue.add("a", 20)
	queue.add("b", 10)
	queue.end_turn(queue.next_actor())
	var snapshot: Dictionary = queue.snapshot()
	var expected_order: Array = queue.preview(6)
	queue.add_ct("b", 80)
	queue.restore(snapshot)
	assert_eq(queue.ct_of("b"), int(snapshot["ct"]["b"]), "ct restored")
	assert_true(_same_list(queue.preview(6), expected_order), "order restored")
