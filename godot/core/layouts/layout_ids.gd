@tool
extends RefCounted

# 地图 ID 的共享安全规则：只允许小写字母开头的字母/数字/下划线。
# LayoutDocument、LayoutCatalog、编辑器和触发器目标都从这里取同一份判断，
# 保证“用 ID 拼路径”永远不会穿越目录。


static func valid_id(id: String) -> bool:
	if id.is_empty():
		return false
	for i in range(id.length()):
		var code := id.unicode_at(i)
		if i == 0:
			if code < 97 or code > 122:
				return false
		elif not ((code >= 97 and code <= 122) \
				or (code >= 48 and code <= 57) or code == 95):
			return false
	return true
