class_name DemoRouter
extends RefCounted
## AUTO-GENERATED from demos_router_router.guitkx -- do not edit.

static func render(props: Dictionary, children: Array) -> RUIVNode:
	return (V.router({ "initial": "/" }, [V.fc(DemoRouterInner.render)]))
