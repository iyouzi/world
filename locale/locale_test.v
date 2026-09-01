module locale

import os as _

// 双语词典必须保持 key 完全一致：缺失一侧的 key 会在运行时静默回退到另一种
// 语言（见 lookup），导致界面混语而非报错。此测试捕获这种回归。
fn test_dict_key_parity() {
	zh := zh_dict()
	en := en_dict()
	assert zh.keys().len == en.keys().len
	mut missing := []string{}
	for k, _ in zh {
		if k !in en {
			missing << k
		}
	}
	for k, _ in en {
		if k !in zh {
			missing << k
		}
	}
	assert missing.len == 0, '双语词典 key 不一致: ${missing}'
}

// tf 的 {name} 占位符替换必须与 JS 端语义一致（V 与 JS 都用 '{name}' 语法）。
fn test_tf_placeholder() {
	r := tf(.zh, 'mobile_bar', {
		'n': '200'
	})
	assert r.contains('200')
	assert !r.contains('{n}')
}
