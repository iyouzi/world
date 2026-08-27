module main

import models

fn test_fmt2() {
	assert fmt2(3.14159) == '3.14'
	// 恰好 2 位小数；不足补零
	assert fmt2(5.0) == '5.00'
	assert fmt2(-2.5) == '-2.50'
	assert fmt2(12.3456) == '12.35'
}

fn test_page_shell_contains_assets_and_title() {
	html := page_shell('测试标题', models.WorldStats{}, '', '', .zh)
	assert html.contains('<title>测试标题 | WorldApp</title>')
	assert html.contains('/static/css/style.css')
	assert html.contains('/static/js/app.js')
	// 顶栏统计占位
	assert html.contains('topbar')
}

fn test_sidebar_html_lists_categories_and_search() {
	sb := sidebar_html('wb_overview', 'china', models.all_categories(), .zh)
	// 搜索框回填
	assert sb.contains('value="china"')
	// 分类链接齐全
	assert sb.contains('/category/wb_overview')
	assert sb.contains('/category/imf_gdp')
	assert sb.contains('/category/mk_us')
	assert sb.contains('/category/mk_fx')
	assert sb.contains('/category/mk_commodity')
	// 当前分类高亮
	assert sb.contains('side-link active')
	// 手动刷新按钮
	assert sb.contains('triggerRefresh()')
}

// 边栏必须位于主内容之后（右侧），便于鼠标操作
fn test_page_shell_sidebar_on_right() {
	html := page_shell('t', models.WorldStats{}, '<aside class="sidebar">S</aside>',
		'<main>M</main>', .zh)
	si := html.index('<aside') or { -1 }
	mi := html.index('<main class="content">') or { -1 }
	assert si != -1 && mi != -1
	assert si > mi
}

// IMF / 行情页空数据时给出可读提示而不是空白表格
fn test_market_meta_covers_all_markets() {
	for m in ['cn', 'hk', 'us', 'index', 'fx', 'commodity'] {
		title, sub := market_meta(m, .zh)
		assert title != ''
		assert sub != ''
	}
}

// ========== 安全转义：防止 XSS / JS 注入 ==========
fn test_h_escape_html_injection_payloads() {
	// 经典 XSS payloads
	assert h('<script>alert(1)</script>') == '&lt;script&gt;alert(1)&lt;/script&gt;'
	assert h('"><img src=x onerror=alert(1)>') == '&quot;&gt;&lt;img src=x onerror=alert(1)&gt;'
	assert h("' onclick='alert(1)'") == '&#39; onclick=&#39;alert(1)&#39;'
	// 实体双编码：& 必须最先转义，避免 &lt; 的 & 再次编码
	assert h('&<') == '&amp;&lt;'
	// 空字符串与中文无副作用
	assert h('') == ''
	assert h('中国🇨🇳') == '中国🇨🇳'
}

fn test_sidebar_search_escapes_xss_payload() {
	sb := sidebar_html('wb_overview', '"><script>alert(1)</script>', [], .zh)
	// 原始脚本串绝不能直接出现在 value 属性中（会被解释为属性闭合+脚本）
	assert !sb.contains('"><script>')
	// 搜索框 value 必须是经过转义的形式
	assert sb.contains('value=&quot;&gt;&lt;script&gt;')
		|| sb.contains('value="&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;"')
}

fn test_js_str_blocks_script_closer() {
	// </script> 会终止整个 script 块，必须转义为 <\/ 避免 break-out
	assert js_str('foo</script>bar').contains('<\\/script>')
		|| js_str('foo</script>bar') == 'foo<\\/script>bar'
	// 引号与反斜杠
	assert js_str('it\'s "ok"').contains("\\'") && js_str('it\'s "ok"').contains('\\"')
	assert js_str('a\\b').starts_with('a\\\\b')
}

// 标题若包含 HTML 注入字符不会泄漏到 <title> 标签外
fn test_page_shell_title_xss_escaped() {
	html := page_shell('</title><script>alert(1)</script>', models.WorldStats{}, '', '', .zh)
	assert !html.contains('<script>alert(1)</script>')
	assert html.contains('&lt;/title&gt;&lt;script&gt;alert(1)&lt;/script&gt;')
}
