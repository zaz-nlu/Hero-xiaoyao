extends "res://tests/test_case.gd"


func test_runner_works() -> void:
	assert_eq(1 + 1, 2)


func test_assert_near() -> void:
	assert_near(0.1 + 0.2, 0.3)
