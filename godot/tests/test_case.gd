extends RefCounted

var failures: Array[String] = []


func assert_eq(actual, expected, msg := "") -> void:
	if actual != expected:
		var detail := "expected %s, got %s" % [str(expected), str(actual)]
		if msg != "":
			detail += " (%s)" % msg
		failures.append(detail)


func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		var detail := "expected true, got false"
		if msg != "":
			detail += " (%s)" % msg
		failures.append(detail)


func assert_near(a: float, b: float, eps := 0.0001, msg := "") -> void:
	if absf(a - b) > eps:
		var detail := "expected %.6f (eps %.6f), got %.6f" % [b, eps, a]
		if msg != "":
			detail += " (%s)" % msg
		failures.append(detail)
