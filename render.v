module main

import models
import strings

// ============ 安全转义函数 ============
// h：HTML 文本/属性值转义（& < > " '），用于 ${h(x)} 嵌到 HTML 标签内容或属性
fn h(s string) string {
	return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;').replace("'",
		'&#39;')
}

// js_str：JS 字符串字面量内容转义（用于 '...' 或 "..." 包裹的 JS 字符串）。
// 额外转义 </script 和 U+2028/U+2029（行分隔符/段分隔符在 JSON 非法但在 JS 字符串中会终止语句）。
fn js_str(s string) string {
	mut out := s.replace('\\', '\\\\').replace("'", "\\'").replace('"', '\\"').replace('\n', '\\n').replace('\r',
		'\\r').replace('\t', '\\t').replace('\x00', '\\u0000')
	out = out.replace('</', '<\\/')
	out = out.replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
	return out
}

// a：URL path 片段转义（iso2, market, category id），用于 href="/xxx/${a(y)}"。
// V veb 路由对 :param 已经做了 / 的分隔，这里再做 HTML 转义 + 拒绝控制字符与 ?# 片段
fn a(s string) string {
	return h(s.replace('?', '').replace('#', ''))
}

// digits_only：保留字符串中属于 allowed 的字符。
// （注：V 0.5.2 的 string.filter 返回 void，此处手写避免编译失败。）
fn digits_only(s string, allowed string) string {
	mut out := []u8{}
	for c in s {
		mut found := false
		for ac in allowed {
			if c == ac {
				found = true
				break
			}
		}
		if found {
			out << c
		}
	}
	return out.bytestr()
}

// render_page 渲染主框架：顶部统计 + 右侧栏（分类 + 搜索）+ 主内容区
fn render_page(active string, ws models.WorldStats, _cats []models.Category, search string, app &App) string {
	mut sb := sidebar_html(active, search)
	mut main_html := main_content_html(active, ws, app)
	return page_shell('世界数据全景', ws, sb, main_html)
}

fn page_shell(title string, ws models.WorldStats, sidebar string, main string) string {
	last_upd := if ws.last_update != '' { ws.last_update } else { '等待首次抓取' }
	return '
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
<meta name="theme-color" content="#0f1420">
<meta name="description" content="WorldApp 世界数据全景 - 整合 WorldBank、IMF 与全球市场行情，全面展示我们的世界">
<title>${h(title)} | WorldApp</title>
<link rel="stylesheet" href="/static/css/style.css">
<link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>
<script defer src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
	<script src="/static/js/app.js"></script>
</head>
<body>
<header class="topbar">
  <div class="brand">🌐 World<span>App</span></div>
  <div class="topstats">
    <div class="ts"><span class="tsv">${models.format_large(ws.total_gdp)}</span><span class="tsl">世界GDP (USD)</span></div>
    <div class="ts"><span class="tsv">${ws.total_countries}</span><span class="tsl">国家数</span></div>
    <div class="ts"><span class="tsv">${fmt2(ws.avg_life)}</span><span class="tsl">平均寿命 (年)</span></div>
    <div class="ts"><span class="tsv" id="fetchStatus" title="${h(last_upd)}">就绪</span><span class="tsl">更新状态</span></div>
  </div>
  <div class="top-actions">
    <span class="clock-display" id="clockDisplay"></span>
    <button class="theme-toggle" id="themeToggle" title="切换主题">☀️</button>
  </div>
</header>
<div class="mobile-bar">
  <span style="font-size:13px;color:var(--text-muted)">世界数据全景 · ${ws.total_countries} 个国家</span>
  <button id="sidebarToggle">☰ 菜单</button>
</div>
<div id="sidebarOverlay"></div>
<div class="layout">
  <main class="content">
    ${main}
  </main>
  ${sidebar}
</div>
</body>
</html>'
}

// 右侧栏：分类目录 + 搜索框
fn sidebar_html(active string, search string) string {
	mut cats := models.all_categories()
	mut groups := map[string][]models.Category{}
	for c in cats {
		groups[c.source] << c
	}
	mut html := '<aside class="sidebar"><div class="side-search">
		<input type="text" id="sideSearch" placeholder="搜索国家 / 市场 / 指标..." value="${h(search)}">
		<button onclick="doSideSearch()">🔍</button>
	</div><nav class="side-nav">'
	labels := {
		'worldbank': '🌍 世界银行'
		'imf':       '🏛️ 国际货币基金'
		'market':    '📈 全球市场'
	}
	for src, list in groups {
		html += '<div class="side-group"><div class="side-group-title">${labels[src] or { src }}</div><ul>'
		for c in list {
			cls := if c.id == active { ' active' } else { '' }
			html += '<li><a class="side-link${cls}" href="/category/${c.id}"><span class="ico">${c.icon}</span>${c.title}</a></li>'
		}
		html += '</ul></div>'
	}
	html += '</nav>
	<div class="side-foot">
		<button class="refresh-btn" onclick="triggerRefresh()">🔄 立即更新数据</button>
	</div>
	</aside>'
	return html
}

// 主内容区：根据 active 分类渲染不同内容
fn main_content_html(active string, ws models.WorldStats, app &App) string {
	match active {
		'overview' { return overview_html(ws, app) }
		'wb_overview', 'wb_gdp', 'wb_social', 'wb_energy' { return wb_html(active, app) }
		'imf_gdp', 'imf_wEO' { return imf_html(active, app) }
		'mk_cn' { return market_html('cn', app) }
		'mk_hk' { return market_html('hk', app) }
		'mk_us' { return market_html('us', app) }
		'mk_index' { return market_html('index', app) }
		'mk_fx' { return market_html('fx', app) }
		'mk_commodity' { return market_html('commodity', app) }
		else { return overview_html(ws, app) }
	}
}

// 概览：世界统计卡片 + GDP Top10 图表（含"世界"合计行）
fn overview_html(ws models.WorldStats, app &App) string {
	top := app.db.get_country_gdp_top(10) or { []models.CountryGdp{} }
	mut labels := '['
	mut values := '['
	for i, item in top {
		if i > 0 {
			labels += ','
			values += ','
		}
		labels += "'" + js_str(item.iso2) + "'"
		v_str := item.value.str()
		v_int_part := v_str.split('.')[0]
		if v_int_part == '' || !v_int_part.contains_any('0123456789-') {
			values += '0'
		} else {
			values += digits_only(v_int_part, '0123456789-')
		}
	}
	labels += ']'
	values += ']'
	last_upd := if ws.last_update != '' { ws.last_update } else { '' }

	// Build GDP table rows
	mut rows := ''
	world_val := ws.total_gdp
	rows += '<tr style="background:var(--brand-soft);font-weight:700">' +
		'<td style="color:var(--brand)"> </td>' +
		'<td class="num-cell">${models.format_large(world_val)}</td>' +
		'<td style="font-size:12px;color:var(--text-muted)"></td>' +
	'</tr>'
	for i, item in top {
		rank := i + 2
		pct := if top.len > 0 && top[0].value > 0 { item.value / top[0].value * 100.0 } else { 0.0 }
		mut pct_safe := digits_only(pct.str().split('.')[0], '0123456789')
		if pct_safe == '' { pct_safe = '0' }
		rows += '<tr>' +
			'<td style="font-weight:600;color:var(--text-muted)">#' + rank.str() + '</td>' +
			'<td>' + h(item.name) + ' <a href="/country/' + a(item.iso2) + '" style="font-size:11px;color:var(--text-muted);font-weight:400">' + h(item.iso2) + '</a></td>' +
			'<td class="num-cell">${models.format_large(item.value)}</td>' +
			'<td style="font-size:12px;color:var(--text-muted)">' + item.year.str() + '</td>' +
		'</tr>'
	}

	// Build WLD cards panel
	mut wld_cards := ''
	if ws.gdp_per_capita > 0 { wld_cards += '<div class="card"><div class="cv">' + fmt2(ws.gdp_per_capita) + '</div><div class="cl">GDP per capita (USD, const 2015)</div></div>' }
	if ws.inflation > 0 {
		color := if ws.inflation > 5.0 { 'var(--warn)' } else { 'var(--brand-2)' }
		wld_cards += '<div class="card"><div class="cv" style="color:' + color + '">' + fmt2(ws.inflation) + '%</div><div class="cl">CPI Inflation (%)</div></div>'
	}
	if ws.unemployment > 0 {
		color := if ws.unemployment > 6.0 { 'var(--warn)' } else { 'var(--brand-2)' }
		wld_cards += '<div class="card"><div class="cv" style="color:' + color + '">' + fmt2(ws.unemployment) + '%</div><div class="cl">Unemployment (%)</div></div>'
	}
	if ws.internet_users > 0 { wld_cards += '<div class="card"><div class="cv">' + fmt2(ws.internet_users) + '%</div><div class="cl">Internet Penetration</div></div>' }
	if ws.education_spend > 0 { wld_cards += '<div class="card"><div class="cv">' + fmt2(ws.education_spend) + '%</div><div class="cl">Education Spend (% GDP)</div></div>' }
	if ws.health_spend > 0 { wld_cards += '<div class="card"><div class="cv">' + fmt2(ws.health_spend) + '%</div><div class="cl">Health Spend (% GDP)</div></div>' }
	if ws.energy_use > 0 { wld_cards += '<div class="card"><div class="cv">' + fmt2(ws.energy_use) + '</div><div class="cl">Energy Use (kg oil eq/cap)</div></div>' }
	wld_count := wld_cards.split('card').len - 1
	wld_panel := if wld_count > 0 {
		'<div class="panel">' +
		'<div class="panel-header"><h2 style="margin:0">World Core Indicators (WLD)</h2><span class="panel-badge">' + wld_count.str() + ' items</span></div>' +
		'<div class="cards" style="grid-template-columns:repeat(auto-fit,minmax(180px,1fr));margin:0">' + wld_cards + '</div>' +
		'</div>'
	} else { '' }

	// Build page HTML
	mut sb := strings.new_builder(4096)
	sb.write_string('<h1> </h1>')
	sb.write_string('<p class="sub"> <b>World Bank</b><b>IMF</b>  <b></b>   ' + h(last_upd) + '</p>')
	sb.write_string('<div class="cards">')
	sb.write_string('<div class="card"><div class="cv">${models.format_large(ws.total_gdp)}</div><div class="cl">  GDP USD</div></div>')
	sb.write_string('<div class="card"><div class="cv">${ws.total_countries}</div><div class="cl"> </div></div>')
	sb.write_string('<div class="card"><div class="cv">${models.format_large(ws.total_population)}</div><div class="cl"> </div></div>')
	sb.write_string('<div class="card"><div class="cv">${fmt2(ws.avg_life)}</div><div class="cl"> </div></div>')
	sb.write_string('</div>')
	sb.write_string('<div class="panel">')
	sb.write_string('<div class="panel-header"><h2 style="margin:0"> GDP Top 10</h2><span class="panel-badge"></span></div>')
	sb.write_string('<div class="table-wrap">')
	sb.write_string('<table class="data-table">')
	sb.write_string('<thead><tr><th>#</th><th></th><th class="num-cell">GDP (USD)</th><th></th></tr></thead>')
	sb.write_string('<tbody>' + rows + '</tbody>')
	sb.write_string('</table>')
	sb.write_string('</div>')
	sb.write_string('</div>')
	sb.write_string(wld_panel)
	sb.write_string('<div class="panel">')
	sb.write_string('<div class="panel-header"><h2 style="margin:0"> IMF GDP Top 10</h2><span class="panel-badge">API</span></div>')
	sb.write_string('<canvas id="imfChart" height="140"></canvas>')
	sb.write_string('</div>')
	sb.write_string('<div class="panel" id="gdpChartPanel" style="display:none">')
	sb.write_string('<div class="panel-header"><h2 style="margin:0"> GDP Chart</h2><span class="panel-badge">Chart.js</span></div>')
	sb.write_string('<canvas id="gdpChart" height="180"></canvas>')
	sb.write_string('</div>')
	sb.write_string('<script>')
	sb.write_string('window.addEventListener("DOMContentLoaded", () => {')
	sb.write_string('  if (window.renderBarChart) window.renderBarChart("gdpChart", ' + labels + ', ' + values + ', "GDP (USD)");')
	sb.write_string('  document.getElementById("gdpChartPanel").style.display = "block";')
	sb.write_string('  if (window.renderImfTop) window.renderImfTop("imfChart");')
	sb.write_string('});')
	sb.write_string('</script>')
	return sb.str()
}


// WorldBank 分类内容
fn wb_html(cat string, app &App) string {
	mut indicator := 'NY.GDP.MKTP.CD'
	mut title := '国家经济概览'
	mut unit := 'USD'
	mut icon := '🌍'
	match cat {
		'wb_gdp' {
			indicator = 'NY.GDP.MKTP.CD'
			title = 'GDP 与增长'
			unit = 'USD'
			icon = '💰'
		}
		'wb_social' {
			indicator = 'SP.DYN.LE00.IN'
			title = '社会民生（预期寿命）'
			unit = 'years'
			icon = '👥'
		}
		'wb_energy' {
			indicator = 'EG.USE.PCAP.KG.OE'
			title = '能源使用（人均）'
			unit = 'kg'
			icon = '🌱'
		}
		else {
			indicator = 'NY.GDP.MKTP.CD'
			title = '国家经济概览'
			unit = 'USD'
			icon = '🌍'
		}
	}
	top := app.db.get_country_indicator_top('worldbank', indicator, 15) or { []models.CountryGdp{} }
	if top.len == 0 {
		return '
		<h1>${icon} ${h(title)}</h1>
		<p class="sub">数据源：World Bank · 指标代码：<code>${h(indicator)}</code> · 单位：${h(unit)}</p>
		<div class="empty-state"><div class="emoji">📭</div>
		<p>暂无数据：后台抓取尚未成功或源接口不可用</p>
		<p style="margin-top:6px;font-size:12px">可点击侧栏「🔄 立即更新数据」重试，详见 world_app.log</p>
		</div>'
	}
	mut rows := ''
	for i, item in top {
		rank := (i + 1)
		pct := if top.len > 0 && top[0].value > 0 { item.value / top[0].value * 100.0 } else { 0.0 }
		mut pct_safe := digits_only(pct.str().split('.')[0], '0123456789')
		if pct_safe == '' { pct_safe = '0' }
		rows += '<tr>
			<td style="font-weight:600;color:var(--text-muted)">#${rank}</td>
			<td>${h(item.name)} <a href="/country/${a(item.iso2)}" style="font-size:11px;color:var(--text-muted);font-weight:400">${h(item.iso2)}</a></td>
			<td class="num-cell" style="font-weight:600">${models.format_large(item.value)}</td>
			<td style="font-size:12px;color:var(--text-muted)">${item.year}年</td>
			<td class="bar-cell"><div class="bar-wrap"><div class="bar" style="width:${pct_safe}%"></div></div>
			<div style="font-size:11px;color:var(--text-muted);margin-top:4px">${h(pct_safe)}% of #1</div></td>
		</tr>'
	}
	return '
	<h1>${icon} ${h(title)}</h1>
	<p class="sub">数据源：World Bank · 指标代码：<code>${h(indicator)}</code> · 单位：${h(unit)} · 共 ${top.len} 个国家（最新年份）</p>
	<div class="panel" style="padding:0;overflow:hidden">
	<div class="panel-header" style="padding:18px 20px 0"><h2 style="margin:0">排名列表</h2><span class="panel-badge">Top ${top.len}</span></div>
	<div class="table-wrap" style="padding:0 4px 4px">
	<table class="data-table" style="border-radius:0">
		<thead><tr><th>#</th><th>国家</th><th class="num-cell">数值</th><th>年份</th><th>相对占比</th></tr></thead>
		<tbody>${rows}</tbody>
	</table>
	</div>
	</div>'
}

// IMF 分类内容：imf_gdp -> NGDPD（GDP 现价美元）；imf_wEO -> NGDP_RPCH（实际增长预测）
fn imf_html(cat string, app &App) string {
	code := if cat == 'imf_wEO' { 'NGDP_RPCH' } else { 'NGDPD' }
	title := if cat == 'imf_wEO' { 'IMF 经济增长预测' } else { 'IMF 口径 GDP 估算' }
	icon := if cat == 'imf_wEO' { '📈' } else { '🏛️' }
	sub := if cat == 'imf_wEO' {
		'数据源：IMF Data Mapper · <code>NGDP_RPCH</code> · 实际 GDP 同比增长 %'
	} else {
		'数据源：IMF Data Mapper · <code>NGDPD</code> · 现价美元 (USD)'
	}
	top := app.db.get_indicator_top('imf', code, 15) or { []models.Indicator{} }
	if top.len == 0 {
		return '
		<h1>${icon} ${h(title)}</h1>
		<p class="sub">${sub}</p>
		<div class="empty-state"><div class="emoji">📭</div>
		<p>暂无 IMF 数据：后台抓取尚未成功或源接口不可用</p>
		<p style="margin-top:6px;font-size:12px">可点击侧栏「🔄 立即更新数据」重试，详见 world_app.log</p>
		</div>'
	}
	upd := top[0].updated_at
	mut rows := ''
	for i, ind in top {
		rank := (i + 1)
		mut pct := 0.0
		if top.len > 0 && top[0].value != 0 {
			if code == 'NGDP_RPCH' {
				// 增长率用绝对值排名更直观，避免负号让占比出问题
				pct = ((ind.value - top[top.len - 1].value) / (top[0].value - top[top.len -
					1].value + 0.0001) * 100.0)
			} else {
				pct = ind.value / top[0].value * 100.0
			}
		}
		if pct < 0 { pct = 0 }
		if pct > 100 { pct = 100 }
		pct_safe := digits_only(pct.str().split('.')[0], '0123456789')
		pct_str := if pct_safe == '' { '0' } else { pct_safe }
		mut val_txt := ''
		mut arrow_cls := ''
		mut sign := ''
		if code == 'NGDP_RPCH' {
			if ind.value >= 0 {
				arrow_cls = 'arrow-up up'
				sign = '+'
			} else {
				arrow_cls = 'arrow-down down'
			}
			// arrow_cls / sign 都是静态值，无 XSS 风险；fmt2() 只输出数字、小数点、负号
			val_txt = '<span class="${arrow_cls}">${sign}${fmt2(ind.value)}%</span>'
		} else {
			val_txt = fmt2(ind.value)
		}
		bar_cls := if code == 'NGDP_RPCH' { 'bar alt' } else { 'bar' }
		rows += '<tr>
			<td style="font-weight:600;color:var(--text-muted)">#${rank}</td>
			<td><a href="/country/${a(ind.country_iso)}">${h(ind.country_iso)}</a></td>
			<td style="font-size:12px;color:var(--text-muted)">${h(ind.year.str())}</td>
			<td class="num-cell" style="font-weight:600">${val_txt}</td>
			<td class="bar-cell"><div class="bar-wrap"><div class="${bar_cls}" style="width:${pct_str}%"></div></div></td>
		</tr>'
	}
	return '
	<h1>${icon} ${h(title)}</h1>
	<p class="sub">${sub} · 更新于 ${h(upd)} · 共 ${top.len} 个经济体</p>
	<div class="panel" style="padding:0;overflow:hidden">
	<div class="panel-header" style="padding:18px 20px 0"><h2 style="margin:0">排名列表</h2><span class="panel-badge">Top ${top.len}</span></div>
	<div class="table-wrap" style="padding:0 4px 4px">
	<table class="data-table" style="border-radius:0">
		<thead><tr><th>#</th><th>国家代码</th><th>年份</th><th>数值</th><th style="min-width:200px">相对分布</th></tr></thead>
		<tbody>${rows}</tbody>
	</table>
	</div>
	</div>'
}

// 国家详情页
fn render_country(ws models.WorldStats, _cats []models.Category, iso2 string, inds []models.Indicator, _app &App) string {
	iso3 := models.iso2_to_iso3(iso2)
	flag := models.iso2_to_flag_emoji(iso2)
	iso2_safe := h(iso2)
	iso3_safe := h(iso3)
	page_title := '国家 ${iso2_safe}'
	if inds.len == 0 {
		sidebar := sidebar_html('wb_overview', '')
		main_html := '
		<h1>${flag} 国家详情：${iso2_safe}${if iso3 != '' {
			' (' + iso3_safe + ')'
		} else {
			''
		}}</h1>
		<p class="sub">该国在经济、社会、环境等维度的全部指标</p>
		<div class="empty-state"><div class="emoji">📭</div>
		<p>该国家暂无已记录的指标数据</p>
		<p style="margin-top:6px;font-size:12px">可点击侧栏「🔄 立即更新数据」抓取最新数据</p>
		</div>'
		return page_shell(page_title, ws, sidebar, main_html)
	}
	// 按 source 分组
	mut groups := map[string][]models.Indicator{}
	for ind in inds {
		groups[ind.source] << ind
	}
	mut groups_html := ''
	source_label := {
		'worldbank': '🌍 世界银行 (WorldBank)'
		'imf':       '🏛️ 国际货币基金 (IMF)'
	}
	for src, list in groups {
		mut rows := ''
		for ind in list {
			rows += '<tr>
				<td><b>${h(ind.label)}</b></td>
				<td style="font-size:12px;color:var(--text-muted);font-family:var(--font-mono)">${h(ind.indicator)}</td>
				<td style="font-size:12px;color:var(--text-muted)">${h(ind.year.str())}</td>
				<td class="num-cell" style="font-weight:600">${fmt2(ind.value)} <span style="color:var(--text-muted);font-size:12px;font-weight:400">${h(ind.unit)}</span></td>
			</tr>'
		}
		lb := source_label[src] or { src }
		groups_html += '
		<div class="panel" style="padding:0;overflow:hidden;margin-bottom:18px">
		<div class="panel-header" style="padding:18px 20px 0">
			<h2 style="margin:0">${h(lb)}</h2><span class="panel-badge">${list.len} 项</span>
		</div>
		<div class="table-wrap" style="padding:0 4px 4px">
		<table class="data-table" style="border-radius:0">
			<thead><tr><th>指标名</th><th>指标代码</th><th>年份</th><th>数值</th></tr></thead>
			<tbody>${rows}</tbody>
		</table>
		</div>
		</div>'
	}
	sidebar := sidebar_html('wb_overview', '')
	main_html := '
	<h1>${flag} 国家详情：${iso2_safe}${if iso3 != '' {
		' (' + iso3_safe + ')'
	} else {
		''
	}}</h1>
	<p class="sub">该国在经济、社会、环境等维度的全部指标 · 共 <b>${inds.len}</b> 条记录</p>
	${groups_html}'
	return page_shell(page_title, ws, sidebar, main_html)
}

// market_title 各行情页标题与数据源说明
fn market_meta(market string) (string, string, string) {
	return match market {
		'cn' { '🇨🇳 A股行情', '数据源：腾讯 / 新浪 / 网易 实时接口', '🇨🇳' }
		'hk' { '🇭🇰 港股行情', '数据源：腾讯 / 新浪 / 网易 实时接口', '🇭🇰' }
		'us' { '🇺🇸 美股行情', '数据源：腾讯 / 新浪 / 网易 实时接口', '🇺🇸' }
		'index' { '📊 全球指数', '数据源：腾讯 / 新浪 实时接口', '📊' }
		'fx' { '💱 全球汇率', '数据源：open.er-api.com（兑美元，免 key）', '💱' }
		'commodity' { '🛢️ 大宗商品', '数据源：新浪外盘期货（hf_*，GBK 转码）', '🛢️' }
		else { '📈 全球市场行情', '数据源：多市场实时接口', '📈' }
	}
}

// 所有 market 分类（用于 pill tabs 快速切换）
fn market_tabs(active string) string {
	tabs := [
		models.Category{
			id:          'mk_cn'
			title:       'A股'
			source:      'market'
			icon:        '🇨🇳'
			description: ''
		},
		models.Category{
			id:          'mk_hk'
			title:       '港股'
			source:      'market'
			icon:        '🇭🇰'
			description: ''
		},
		models.Category{
			id:          'mk_us'
			title:       '美股'
			source:      'market'
			icon:        '🇺🇸'
			description: ''
		},
		models.Category{
			id:          'mk_index'
			title:       '指数'
			source:      'market'
			icon:        '📊'
			description: ''
		},
		models.Category{
			id:          'mk_fx'
			title:       '汇率'
			source:      'market'
			icon:        '💱'
			description: ''
		},
		models.Category{
			id:          'mk_commodity'
			title:       '大宗'
			source:      'market'
			icon:        '🛢️'
			description: ''
		},
	]
	mut html := '<div class="market-tabs">'
	aid := 'mk_' + active
	for t in tabs {
		cls := if t.id == aid { ' active' } else { '' }
		html += '<a class="market-tab${cls}" href="/category/${t.id}">${t.icon} ${t.title}</a>'
	}
	html += '</div>'
	return html
}

// 市场行情内容片段（供分类页调用，不含外层 shell）
fn market_html(market string, app &App) string {
	title, sub, _ := market_meta(market)
	quotes := app.db.get_market_quotes(market, '') or { []models.MarketQuote{} }
	tabs := market_tabs(market)
	if quotes.len == 0 {
		return '
		<h1>${h(title)}</h1>
		<p class="sub">${h(sub)}</p>
		${tabs}
		<div class="empty-state"><div class="emoji">📭</div>
		<p>暂无行情数据：后台抓取尚未成功或行情源不可用</p>
		<p style="margin-top:6px;font-size:12px">可点击侧栏「🔄 立即更新数据」重试，详见 world_app.log</p>
		</div>'
	}
	// 汇总统计
	mut up_count := 0
	mut down_count := 0
	mut avg_pct := 0.0
	for q in quotes {
		if q.change >= 0 {
			up_count++
		} else {
			down_count++
		}
		avg_pct += q.change_pct
	}
	if quotes.len > 0 { avg_pct = avg_pct / f64(quotes.len) }
	mut rows := ''
	for q in quotes {
		up := q.change >= 0
		cls := if up { 'up' } else { 'down' }
		arrow := if up { 'arrow-up' } else { 'arrow-down' }
		sign := if up { '+' } else { '' }
		vol_txt := if q.volume > 0 { models.format_large(f64(q.volume)) } else { '-' }
		// name/source/symbol 来自外部 API（腾讯/新浪返回 GBK 中文名），必须 HTML 转义
		rows += '<tr class="${cls} market-row">
			<td><b>${h(q.name)}</b><div style="font-size:11px;color:var(--text-muted);margin-top:2px">来源: ${h(q.source)}</div></td>
			<td style="font-family:var(--font-mono);font-size:12px;color:var(--text-muted)">${h(q.symbol)}</td>
			<td class="num-cell" style="font-weight:600;font-size:15px">${fmt2(q.price)}</td>
			<td class="${arrow} num-cell" style="font-weight:600">${sign}${fmt2(q.change)}</td>
			<td class="${arrow} num-cell" style="font-weight:600">${sign}${fmt2(q.change_pct)}%</td>
			<td class="num-cell" style="font-variant-numeric:tabular-nums">${vol_txt}</td>
		</tr>'
	}
	up_pct := if quotes.len > 0 { (up_count * 100 / quotes.len) } else { 0 }
	avg_pct_color := if avg_pct >= 0 { 'var(--up)' } else { 'var(--down)' }
	avg_pct_sign := if avg_pct >= 0 { '+' } else { '' }
	return '
	<h1>${h(title)}</h1>
	<p class="sub">${h(sub)}</p>
	${tabs}
	<div class="cards" style="grid-template-columns:repeat(auto-fit,minmax(140px,1fr));margin-bottom:18px">
		<div class="card"><div class="cv">${quotes.len}</div><div class="cl">📋 标的数</div></div>
		<div class="card"><div class="cv" style="color:var(--up)">${up_count}</div><div class="cl">📈 上涨家数</div></div>
		<div class="card"><div class="cv" style="color:var(--down)">${down_count}</div><div class="cl">📉 下跌家数</div></div>
		<div class="card"><div class="cv" style="color:${avg_pct_color}">${avg_pct_sign}${fmt2(avg_pct)}%</div><div class="cl">📊 平均涨跌幅 · ${up_pct}% 上涨</div></div>
	</div>
	<div class="panel" style="padding:0;overflow:hidden">
	<div class="table-wrap">
	<table class="data-table market" style="border-radius:0">
		<thead><tr><th>名称</th><th>代码</th><th>现价</th><th>涨跌</th><th>涨跌幅</th><th>成交量</th></tr></thead>
		<tbody>${rows}</tbody>
	</table>
	</div>
	</div>'
}

// 市场页（独立 shell）
fn render_market(ws models.WorldStats, _cats []models.Category, market string, _quotes []models.MarketQuote, app &App) string {
	sidebar := sidebar_html('mk_' + market, '')
	main_html := market_html(market, app)
	return page_shell('市场行情', ws, sidebar, main_html)
}

// fmt2 将浮点数格式化为最多 2 位小数（避免 f64.str() 缺小数导致 split 越界）
fn fmt2(f f64) string {
	s := f.str()
	if s.contains('.') {
		parts := s.split('.')
		mut dec := parts[1]
		if dec.len > 2 {
			dec = dec[0..2]
		}
		return parts[0] + '.' + dec
	}
	return s + '.00'
}
