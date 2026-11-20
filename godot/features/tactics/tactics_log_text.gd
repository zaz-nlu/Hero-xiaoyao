extends RefCounted

# 战斗日志文本的补全：招式名后面带形态后缀（如“乱砍[扫]”）。
# 只做纯文本映射，不碰战斗状态；视图只调用这里的静态方法。

const TacticsForms = preload("res://core/tactics/tactics_forms.gd")


static func with_form(name_text: String, move_def) -> String:
	var form := TacticsForms.move_form(move_def)
	if form == "":
		return name_text
	return "%s[%s]" % [name_text, TacticsForms.form_name(form)]
