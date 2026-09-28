extends RefCounted
## Base for test suites: collects failures instead of stopping.

var errors: Array = []


func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


func eq(actual: Variant, expected: Variant, message := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		errors.append("%s expected %s, got %s" % [message, var_to_str(expected), var_to_str(actual)])
