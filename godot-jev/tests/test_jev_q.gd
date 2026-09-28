extends "res://tests/suite.gd"

const JevQ := preload("res://addons/jev/jev_q.gd")


func test_builders_use_the_wire_format() -> void:
	eq(JevQ.noul("It is raining."), {"type": "noul", "instructions": "It is raining."})
	eq(JevQ.choice("Which?", {"a": "first", "b": "second"}).criteria, {"a": "first", "b": "second"})
	eq(JevQ.score("How hot?", ["cold", "warm", "hot"]).criteria, ["cold", "warm", "hot"])


func test_ranked_sorts_by_probability() -> void:
	var ranked := JevQ.ranked({"probabilities": {"a": 0.2, "b": 0.7, "c": 0.1}})
	eq(ranked.map(func(p): return p[0]), ["b", "a", "c"])
