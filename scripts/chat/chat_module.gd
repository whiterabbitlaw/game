class_name ChatModule
extends RefCounted
## 畅聊模块接口。各模块注册到 ChatRegistry，按 data/chat/module_order.json 的顺序
## 贡献提示词片段。placement 常见值：system、post_history、at_depth。


func module_id() -> String:
	return ""


func prompt_sections(_ctx: Dictionary) -> Array:
	## 返回 [{id, placement, content, depth, priority}]
	return []
