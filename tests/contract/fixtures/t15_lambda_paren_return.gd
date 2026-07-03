class_name LambdaGuard
extends RefCounted
## AUTO-GENERATED from t15_lambda_paren_return.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	var items = props.get("items", [])
	var pick = func(i):
	return V.label({ "text": "i * 2" })
