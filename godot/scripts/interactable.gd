class_name Interactable
extends Area3D
## Something the player can use with E (or G with the right gadget).
## `prompt_fn` returns the prompt text ("" hides it); `use_fn` performs it.

var prompt_fn: Callable
var use_fn: Callable
## Gadget kind that this accepts with G ("poison", "forgery"...), or "".
var gadget_kind := ""

static func make(parent: Node3D, pos: Vector3, size: Vector3, prompt: Callable, use: Callable, gadget := "") -> Interactable:
	var a := Interactable.new()
	a.collision_layer = 16
	a.collision_mask = 0
	a.monitoring = false
	a.monitorable = true
	a.prompt_fn = prompt
	a.use_fn = use
	a.gadget_kind = gadget
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	a.add_child(cs)
	a.position = pos
	parent.add_child(a)
	return a

func prompt() -> String:
	return prompt_fn.call() if prompt_fn.is_valid() else ""

func use() -> void:
	if use_fn.is_valid():
		use_fn.call()
