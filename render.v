module main

import models
import locale
import strings

// ============ 安全转义函数 ============
// h：HTML 文本/属性值转义（& < > " '）
fn h(s string) string {
	return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;').replace("'",
		'&#39;')
}

// js_str：JS 字符串字面量内容转义
fn js_str(s string) string {
	mut out := s.replace('\\', '\\\\').replace("'", "\\'").replace('"', '\\"').replace('\n', '\\n').replace('\r',
		'\\r').replace('\t', '\\t').replace('\x00', '\\u0000')
	out = out.replace('</', '<\\/')
	out = out.replace('\u2028', '\\u2028').replace('\u2029', '\\u2029')
	return out
}

// a：URL path 片段转义（iso2, market, category id）
fn a(s string) string {
	return h(s.replace('?', '').replace('#', ''))
}

// digits_only：保留字符串中属于 allowed 的字符
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

// fmt2 将浮点数格式化为恰好 2 位小数（Python .2f 风格）
fn fmt2(f f64) string {
	return '${f:.2f}'
}

// ============ 页面骨架 ============

// render_page 渲染主框架：顶部统计 + 右侧栏（分类 + 搜索）+ 主内容区
fn render_page(active string, ws models.WorldStats, cats []models.Category, search string, app &App, lang locale.Lang) string {
	mut sb := sidebar_html(active, search, cats, lang)
	mut main_html := main_content_html(active, ws, app, lang)
	return page_shell(locale.t(lang, 'app_title'), ws, sb, main_html, lang)
}

fn page_shell(title string, ws models.WorldStats, sidebar string, main string, lang locale.Lang) string {
	last_upd := if ws.last_update != '' {
		ws.last_update
	} else {
		locale.t(lang, 'wait_first_fetch')
	}
	html_lang := if lang == .en { 'en' } else { 'zh-CN' }
	return '
<!DOCTYPE html>
<html lang="${html_lang}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
<meta name="theme-color" content="#0f1420">
<meta name="description" content="${h(locale.t(lang,
		'meta_desc'))}">
<title>${h(title)} | WorldApp</title>
<link rel="stylesheet" href="/static/css/style.css">
<link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>
<script defer src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
	<script src="/static/js/app.js"></script>
	<script>window.LANG = "${lang.str()}"; window.I18N = ${locale.json_bundle()};</script>
</head>
<body>
<header class="topbar">
  <div class="brand">🌐 World<span>App</span></div>
  <div class="topstats">
    <div class="ts"><span class="tsv">${models.format_large(ws.total_gdp)}</span><span class="tsl">${locale.t(lang,
		'top_world_gdp')}</span></div>
    <div class="ts"><span class="tsv">${ws.total_countries}</span><span class="tsl">${locale.t(lang,
		'top_countries')}</span></div>
    <div class="ts"><span class="tsv">${fmt2(ws.avg_life)}</span><span class="tsl">${locale.t(lang,
		'top_life')}</span></div>
    <div class="ts"><span class="tsv" id="fetchStatus" title="${h(last_upd)}">${locale.t(lang,
		'status_ready')}</span><span class="tsl">${locale.t(lang, 'top_status')}</span></div>
  </div>
  <div class="top-actions">
    <span class="clock-display" id="clockDisplay"></span>
    <span class="lang-switch">
      <a href="?lang=zh" class="${if lang == .zh {
		'on'
	} else {
		''
	}}">${locale.t(lang, 'lang_zh')}</a>
      <a href="?lang=en" class="${if lang == .en {
		'on'
	} else {
		''
	}}">${locale.t(lang, 'lang_en')}</a>
    </span>
    <button class="theme-toggle" id="themeToggle" title="${h(locale.t(lang,
		'theme_toggle'))}">☀️</button>
  </div>
</header>
<div class="mobile-bar">
  <span style="font-size:13px;color:var(--text-muted)">${h(locale.tf(lang,
		'mobile_bar', {
		'n': ws.total_countries.str()
	}))}</span>
  <button id="sidebarToggle">☰ ${h(locale.t(lang, 'menu'))}</button>
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
fn sidebar_html(active string, search string, cats []models.Category, lang locale.Lang) string {
	mut groups := map[string][]models.Category{}
	for c in cats {
		groups[c.source] << c
	}
	mut html := '<aside class="sidebar"><div class="side-search">
		<input type="text" id="sideSearch" placeholder="${h(locale.t(lang,
		'search_placeholder'))}" value="${h(search)}">
		<button onclick="doSideSearch()">🔍</button>
	</div><nav class="side-nav">'
	for src, list in groups {
		html += '<div class="side-group"><div class="side-group-title">${h(locale.t(lang, 'src_' +
			src))}</div><ul>'
		for c in list {
			cls := if c.id == active { ' active' } else { '' }
			html += '<li><a class="side-link${cls}" href="/category/${a(c.id)}"><span class="ico">${c.icon}</span>${h(locale.t(lang,

				'cat_' + c.id))}</a></li>'
		}
		html += '</ul></div>'
	}
	html += '</nav>
	<div class="side-foot">
		<button class="refresh-btn" onclick="triggerRefresh()">🔄 ${h(locale.t(lang,
		'refresh_btn'))}</button>
	</div>
	</aside>'
	return html
}

// 主内容区：根据 active 分类渲染不同内容
fn main_content_html(active string, ws models.WorldStats, app &App, lang locale.Lang) string {
	match active {
		'overview' {
			return overview_html(ws, app, lang)
		}
		'wb_overview', 'wb_gdp', 'wb_social', 'wb_energy' {
			return wb_html(active, app, lang)
		}
		'imf_gdp', 'imf_wEO' {
			return imf_html(active, app, lang)
		}
		'owid_population', 'owid_health', 'owid_energy', 'owid_economy', 'owid_education',
		'owid_food' {
			return owid_html(active, app, lang)
		}
		'mk_cn' {
			return market_html('cn', app, lang)
		}
		'mk_hk' {
			return market_html('hk', app, lang)
		}
		'mk_us' {
			return market_html('us', app, lang)
		}
		'mk_index' {
			return market_html('index', app, lang)
		}
		'mk_fx' {
			return market_html('fx', app, lang)
		}
		'mk_commodity' {
			return market_html('commodity', app, lang)
		}
		else {
			return overview_html(ws, app, lang)
		}
	}
}

// 概览：世界统计卡片 + GDP Top20 图表（含"世界"合计行）
fn overview_html(ws models.WorldStats, app &App, lang locale.Lang) string {
	top := app.db.get_country_gdp_top(20) or { []models.CountryGdp{} }
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
		'<td style="font-size:12px;color:var(--text-muted)"></td>' + '</tr>'
	for i, item in top {
		rank := i + 2
		pct := if top.len > 0 && top[0].value > 0 { item.value / top[0].value * 100.0 } else { 0.0 }
		mut pct_safe := digits_only(pct.str().split('.')[0], '0123456789')
		if pct_safe == '' { pct_safe = '0' }
		rows += '<tr>' + '<td style="font-weight:600;color:var(--text-muted)">#' + rank.str() +
			'</td>' + '<td>' + h(item.name) + ' <a href="/country/' + a(item.iso2) +
			'" style="font-size:11px;color:var(--text-muted);font-weight:400">' + h(item.iso2) +
			'</a></td>' + '<td class="num-cell">${models.format_large(item.value)}</td>' +
			'<td class="bar-cell"><div class="bar-wrap"><div class="bar" style="width:' + pct_safe +
			'%"></div></div></td>' + '<td style="font-size:12px;color:var(--text-muted)">' +
			item.year.str() + '</td>' + '</tr>'
	}

	// Build WLD cards panel
	mut wld_cards := ''
	if ws.gdp_per_capita > 0 {
		wld_cards += '<div class="card"><div class="cv">' + fmt2(ws.gdp_per_capita) +
			'</div><div class="cl">' + h(locale.t(lang, 'wld_gdp_pc')) + '</div></div>'
	}
	if ws.inflation > 0 {
		color := if ws.inflation > 5.0 { 'var(--warn)' } else { 'var(--brand-2)' }
		wld_cards += '<div class="card"><div class="cv" style="color:' + color + '">' +
			fmt2(ws.inflation) + '%</div><div class="cl">' + h(locale.t(lang, 'wld_cpi')) +
			'</div></div>'
	}
	if ws.unemployment > 0 {
		color := if ws.unemployment > 6.0 { 'var(--warn)' } else { 'var(--brand-2)' }
		wld_cards += '<div class="card"><div class="cv" style="color:' + color + '">' +
			fmt2(ws.unemployment) + '%</div><div class="cl">' + h(locale.t(lang, 'wld_unemp')) +
			'</div></div>'
	}
	if ws.internet_users > 0 {
		wld_cards += '<div class="card"><div class="cv">' + fmt2(ws.internet_users) +
			'%</div><div class="cl">' + h(locale.t(lang, 'wld_inet')) + '</div></div>'
	}
	if ws.education_spend > 0 {
		wld_cards += '<div class="card"><div class="cv">' + fmt2(ws.education_spend) +
			'%</div><div class="cl">' + h(locale.t(lang, 'wld_edu')) + '</div></div>'
	}
	if ws.health_spend > 0 {
		wld_cards += '<div class="card"><div class="cv">' + fmt2(ws.health_spend) +
			'%</div><div class="cl">' + h(locale.t(lang, 'wld_health')) + '</div></div>'
	}
	if ws.energy_use > 0 {
		wld_cards += '<div class="card"><div class="cv">' + fmt2(ws.energy_use) +
			'</div><div class="cl">' + h(locale.t(lang, 'wld_energy')) + '</div></div>'
	}
	wld_count := wld_cards.split('card').len - 1
	wld_panel := if wld_count > 0 {
		'<div class="panel">' + '<div class="panel-header"><h2 style="margin:0">' +
			h(locale.t(lang, 'wld_core')) + '</h2><span class="panel-badge">' +
			h(locale.tf(lang, 'wld_items', {
			'n': wld_count.str()
		})) + '</span></div>' +
			'<div class="cards" style="grid-template-columns:repeat(auto-fit,minmax(180px,1fr));margin:0">' +
			wld_cards + '</div>' + '</div>'
	} else {
		''
	}

	// Build page HTML
	mut sb := strings.new_builder(4096)
	sb.write_string('<h1> </h1>')
	sb.write_string('<p class="sub"><b>' + locale.t(lang, 'world_bank') + '</b> · <b>' +
		locale.t(lang, 'imf') + '</b> · ' + h(locale.t(lang, 'overview_sub')) + ' · ' +
		h(last_upd) + '</p>')
	sb.write_string('<div class="cards">')
	sb.write_string(
		'<div class="card"><div class="cv">${models.format_large(ws.total_gdp)}</div><div class="cl">' +
		h(locale.t(lang, 'card_world_gdp')) + '</div></div>')
	sb.write_string(
		'<div class="card"><div class="cv">${ws.total_countries}</div><div class="cl">' +
		h(locale.t(lang, 'card_countries')) + '</div></div>')
	sb.write_string(
		'<div class="card"><div class="cv">${models.format_large(ws.total_population)}</div><div class="cl">' +
		h(locale.t(lang, 'card_population')) + '</div></div>')
	sb.write_string(
		'<div class="card"><div class="cv">${fmt2(ws.avg_life)}</div><div class="cl">' +
		h(locale.t(lang, 'card_avg_life')) + '</div></div>')
	sb.write_string('</div>')

	// G20+ 主要国家表格
	home_countries := app.db.get_home_countries() or { []models.HomeCountry{} }
	if home_countries.len > 0 {
		sb.write_string('<div class="panel">')
		sb.write_string('<div class="panel-header"><h2 style="margin:0">' +
			h(locale.t(lang, 'home_g20_table')) + '</h2><span class="panel-badge">' +
			h(locale.tf(lang, 'wld_items', { 'n': home_countries.len.str() })) + '</span></div>')
		sb.write_string('<div class="table-wrap" style="overflow-x:auto">')
		sb.write_string('<table class="data-table">')
		sb.write_string('<thead><tr><th>' + locale.t(lang, 'rank') + '</th><th>' +
			locale.t(lang, 'country') + '</th>' +
			'<th class="num-cell">' + locale.t(lang, 'home_population') + '</th>' +
			'<th class="num-cell">' + locale.t(lang, 'home_area') + '</th>' +
			'<th class="num-cell">' + locale.t(lang, 'home_gdp') + '</th>' +
			'<th class="num-cell">' + locale.t(lang, 'home_gdp_ppp') + '</th>' +
			'<th class="num-cell">' + locale.t(lang, 'home_gdppc') + '</th>' +
			'<th class="num-cell">' + locale.t(lang, 'home_gdppc_ppp') + '</th>' +
			'<th class="num-cell">' + locale.t(lang, 'home_ppp_per_sqkm') + '</th>' +
			'<th>' + locale.t(lang, 'home_note') + '</th>' +
			'</tr></thead>')
		sb.write_string('<tbody>')
		for i, c in home_countries {
			rank := i + 1
			note := if c.note != '' { h(c.note) } else { '-' }
			sb.write_string('<tr>' +
				'<td style="font-weight:600;color:var(--text-muted)">' + rank.str() + '</td>' +
				'<td>' + h(c.name) + ' <a href="/country/' + a(c.iso2) +
				'" style="font-size:11px;color:var(--text-muted);font-weight:400">' + h(c.iso2) + '</a></td>' +
				'<td class="num-cell">' + models.format_large(c.population) + '</td>' +
				'<td class="num-cell">' + models.format_large(c.land_area) + '</td>' +
				'<td class="num-cell">' + models.format_large(c.gdp) + '</td>' +
				'<td class="num-cell">' + models.format_large(c.gdp_ppp) + '</td>' +
				'<td class="num-cell">' + models.format_large(c.gdp_per_capita) + '</td>' +
				'<td class="num-cell">' + models.format_large(c.gdp_ppc_ppp) + '</td>' +
				'<td class="num-cell">' + models.format_large(c.ppp_per_sqkm) + '</td>' +
				'<td style="font-size:12px;color:var(--text-muted)">' + note + '</td>' +
				'</tr>')
		}
		sb.write_string('</tbody></table>')
		sb.write_string('</div></div>')
	}

	sb.write_string('<div class="panel">')
	sb.write_string('<div class="panel-header"><h2 style="margin:0">' +
		h(locale.t(lang, 'gdp_top20')) + '</h2><span class="panel-badge"></span></div>')
	sb.write_string('<div class="table-wrap">')
	sb.write_string('<table class="data-table">')
	sb.write_string('<thead><tr><th>' + locale.t(lang, 'rank') + '</th><th>' +
		locale.t(lang, 'country') + '</th><th class="num-cell">' + locale.t(lang, 'gdp_usd') +
		'</th><th class="bar-cell"></th><th>' + locale.t(lang, 'year') + '</th></tr></thead>')
	sb.write_string('<tbody>' + rows + '</tbody>')
	sb.write_string('</table>')
	sb.write_string('</div>')
	sb.write_string('</div>')
	sb.write_string(wld_panel)
	sb.write_string('<div class="panel">')
	sb.write_string('<div class="panel-header"><h2 style="margin:0">' +
		h(locale.t(lang, 'imf_top20')) + '</h2><span class="panel-badge">' + locale.t(lang, 'api') +
		'</span></div>')
	sb.write_string('<canvas id="imfChart" height="140"></canvas>')
	sb.write_string('</div>')
	sb.write_string('<div class="panel" id="gdpChartPanel" style="display:none">')
	sb.write_string('<div class="panel-header"><h2 style="margin:0">' +
		h(locale.t(lang, 'gdp_chart')) + '</h2><span class="panel-badge">' +
		locale.t(lang, 'chartjs') + '</span></div>')
	sb.write_string('<canvas id="gdpChart" height="180"></canvas>')
	sb.write_string('</div>')
	sb.write_string('<script>')
	sb.write_string('window.addEventListener("DOMContentLoaded", () => {')
	sb.write_string(
		'  if (window.renderBarChart) window.renderBarChart("gdpChart", ' + labels + ', ' + values + ', "' + js_str(locale.t(lang, 'gdp_usd')) +
		'");')
	sb.write_string('  document.getElementById("gdpChartPanel").style.display = "block";')
	sb.write_string('  if (window.renderImfTop) window.renderImfTop("imfChart");')
	sb.write_string('});')
	sb.write_string('</script>')
	return sb.str()
}

// WorldBank 分类内容
fn wb_html(cat string, app &App, lang locale.Lang) string {
	mut indicator := 'NY.GDP.MKTP.CD'
	mut title := locale.t(lang, 'cat_wb_overview')
	mut unit := 'USD'
	mut icon := '🌍'
	match cat {
		'wb_gdp' {
			indicator = 'NY.GDP.MKTP.CD'
			title = locale.t(lang, 'cat_wb_gdp')
			unit = 'USD'
			icon = '💰'
		}
		'wb_social' {
			indicator = 'SP.DYN.LE00.IN'
			title = locale.t(lang, 'cat_wb_social')
			unit = 'years'
			icon = '👥'
		}
		'wb_energy' {
			indicator = 'EG.USE.PCAP.KG.OE'
			title = locale.t(lang, 'cat_wb_energy')
			unit = 'kg'
			icon = '🌱'
		}
		else {
			indicator = 'NY.GDP.MKTP.CD'
			title = locale.t(lang, 'cat_wb_overview')
			unit = 'USD'
			icon = '🌍'
		}
	}
	top := app.db.get_country_indicator_top('worldbank', indicator, 15) or { []models.CountryGdp{} }
	if top.len == 0 {
		return '
		<h1>${icon} ${h(title)}</h1>
		<p class="sub">' + locale.t(lang, 'data_source') +
			'：World Bank · ' + locale.t(lang, 'indicator_code') +
			'：<code>${h(indicator)}</code> · ' + locale.t(lang, 'unit') +
			'：${h(unit)}</p>
		<div class="empty-state"><div class="emoji">📭</div>
		<p>' +
			locale.t(lang, 'empty_data') + '</p>
		<p style="margin-top:6px;font-size:12px">' +
			locale.t(lang, 'retry_hint') + '</p>
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
			<td style="font-size:12px;color:var(--text-muted)">${item.year}${locale.t(lang,
			'year_unit')}</td>
			<td class="bar-cell"><div class="bar-wrap"><div class="bar" style="width:${pct_safe}%"></div></div>
			<div style="font-size:11px;color:var(--text-muted);margin-top:4px">${h(pct_safe)}% of #1</div></td>
		</tr>'
	}
	return '
	<h1>${icon} ${h(title)}</h1>
	<p class="sub">' + locale.t(lang, 'data_source') +
		'：World Bank · ' + locale.t(lang, 'indicator_code') +
		'：<code>${h(indicator)}</code> · ' + locale.t(lang, 'unit') + '：${h(unit)} · ' +
		h(locale.tf(lang, 'wb_sub_countries', {
		'n': top.len.str()
	})) +
		'</p>
	<div class="panel" style="padding:0;overflow:hidden">
	<div class="panel-header" style="padding:18px 20px 0"><h2 style="margin:0">' +
		locale.t(lang, 'ranking') + '</h2><span class="panel-badge">' +
		h(locale.tf(lang, 'top_n', {
		'n': top.len.str()
	})) +
		'</span></div>
	<div class="table-wrap" style="padding:0 4px 4px">
	<table class="data-table" style="border-radius:0">
		<thead><tr><th>#</th><th>' +
		locale.t(lang, 'country') + '</th><th class="num-cell">' + locale.t(lang, 'value') +
		'</th><th>' + locale.t(lang, 'year') + '</th><th>' + locale.t(lang, 'rel_share') +
		'</th></tr></thead>
		<tbody>${rows}</tbody>
	</table>
	</div>
	</div>'
}

// IMF 分类内容：imf_gdp -> NGDPD（GDP 现价美元）；imf_wEO -> NGDP_RPCH（实际增长预测）
fn imf_html(cat string, app &App, lang locale.Lang) string {
	code := if cat == 'imf_wEO' { 'NGDP_RPCH' } else { 'NGDPD' }
	title := if cat == 'imf_wEO' {
		locale.t(lang, 'cat_imf_weo')
	} else {
		locale.t(lang, 'cat_imf_gdp')
	}
	icon := if cat == 'imf_wEO' { '📈' } else { '🏛️' }
	note := if cat == 'imf_wEO' {
		locale.t(lang, 'imf_growth_note')
	} else {
		locale.t(lang, 'imf_usd_note')
	}
	top := app.db.get_indicator_top('imf', code, 15) or { []models.Indicator{} }
	if top.len == 0 {
		return '
		<h1>${icon} ${h(title)}</h1>
		<p class="sub">' + locale.t(lang, 'data_source') +
			'：IMF Data Mapper · <code>${h(code)}</code> · ' + note +
			'</p>
		<div class="empty-state"><div class="emoji">📭</div>
		<p>' +
			locale.t(lang, 'empty_imf') + '</p>
		<p style="margin-top:6px;font-size:12px">' +
			locale.t(lang, 'retry_hint') + '</p>
		</div>'
	}
	upd := top[0].updated_at
	mut rows := ''
	for i, ind in top {
		rank := (i + 1)
		mut pct := 0.0
		if top.len > 0 && top[0].value != 0 {
			if code == 'NGDP_RPCH' {
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
	<p class="sub">' + locale.t(lang, 'data_source') +
		'：IMF Data Mapper · <code>' + h(code) + '</code> · ' + note + ' · ' +
		h(locale.tf(lang, 'imf_updated', {
		'upd': upd
		'n':   top.len.str()
	})) +
		'</p>
	<div class="panel" style="padding:0;overflow:hidden">
	<div class="panel-header" style="padding:18px 20px 0"><h2 style="margin:0">' +
		locale.t(lang, 'ranking') + '</h2><span class="panel-badge">' +
		h(locale.tf(lang, 'top_n', {
		'n': top.len.str()
	})) +
		'</span></div>
	<div class="table-wrap" style="padding:0 4px 4px">
	<table class="data-table" style="border-radius:0">
		<thead><tr><th>#</th><th>' +
		locale.t(lang, 'country_code') + '</th><th>' + locale.t(lang, 'year') + '</th><th>' +
		locale.t(lang, 'value') + '</th><th style="min-width:200px">' + locale.t(lang, 'rel_dist') +
		'</th></tr></thead>
		<tbody>${rows}</tbody>
	</table>
	</div>
	</div>'
}

// OWID 分类内容：按主题 slug 列出各指标 Top N
fn owid_html(cat string, app &App, lang locale.Lang) string {
	mut inds := []models.OwidIndicator{}
	for ind in models.owid_indicators() {
		if ind.topic_slug == cat {
			inds << ind
		}
	}
	title := locale.t(lang, 'cat_' + cat)
	mut body := ''
	if inds.len == 0 {
		body = '
		<div class="empty-state"><div class="emoji">📭</div>
		<p>' +
			locale.t(lang, 'empty_owid') + '</p>
		<p style="margin-top:6px;font-size:12px">' +
			locale.t(lang, 'retry_hint') + '</p>
		</div>'
	} else {
		for ind in inds {
			top := app.db.get_owid_indicator_top(ind.slug, 15) or { []models.Indicator{} }
			body += '
			<div class="panel" style="padding:0;overflow:hidden;margin-bottom:18px">
			<div class="panel-header" style="padding:18px 20px 0"><h2 style="margin:0">' + h(ind.name(lang)) + '</h2><span class="panel-badge">' + locale.t(lang, 'owid_indicators') + '</span></div>
			<p class="sub">' + h(locale.tf(lang, 'owid_sub', {
				'slug': ind.slug
				'unit': ind.unit
			})) + '</p>'
			if top.len == 0 {
				body += '<p class="empty">' + locale.t(lang, 'empty_owid') + '</p>'
			} else {
				mut rows := ''
				for i, it in top {
					rank := i + 1
					rows += '<tr>
						<td style="font-weight:600;color:var(--text-muted)">#${rank}</td>
						<td><a href="/country/${a(it.country_iso)}">${h(it.country_iso)}</a></td>
						<td style="font-size:12px;color:var(--text-muted)">${h(it.year.str())}</td>
						<td class="num-cell" style="font-weight:600">${fmt2(it.value)} <span style="color:var(--text-muted);font-size:12px;font-weight:400">${h(it.unit)}</span></td>
					</tr>'
				}
				body +=
					'
				<div class="table-wrap" style="padding:0 4px 4px">
				<table class="data-table" style="border-radius:0">
					<thead><tr><th>#</th><th>' +
					locale.t(lang, 'country') + '</th><th>' + locale.t(lang, 'year') + '</th><th>' +
					locale.t(lang, 'value') + '</th></tr></thead>
					<tbody>' + rows +
					'</tbody>
				</table>
				</div>'
			}
			body += '</div>'
		}
	}
	return '
	<h1>📊 ${h(title)}</h1>
	<p class="sub">' + h(locale.t(lang, 'src_owid_full')) +
		'</p>
	${body}'
}

// 国家详情页
fn render_country(ws models.WorldStats, cats []models.Category, iso2 string, inds []models.Indicator, _app &App, lang locale.Lang) string {
	iso3 := models.iso2_to_iso3(iso2)
	flag := models.iso2_to_flag_emoji(iso2)
	iso2_safe := h(iso2)
	iso3_safe := h(iso3)
	page_title := locale.tf(lang, 'country_detail_title', {
		'iso': iso2_safe
	})
	if inds.len == 0 {
		sidebar := sidebar_html('wb_overview', '', cats, lang)
		main_html :=
			'
		<h1>${flag} ${h(locale.tf(lang, 'country_detail_title', {
			'iso': iso2_safe
		}))}${if iso3 != '' {
			' (' + iso3_safe + ')'
		} else {
			''
		}}</h1>
		<p class="sub">' + locale.t(lang, 'country_sub') +
			'</p>
		<div class="empty-state"><div class="emoji">📭</div>
		<p>' +
			locale.t(lang, 'country_nodata') + '</p>
		<p style="margin-top:6px;font-size:12px">' +
			locale.t(lang, 'country_retry') + '</p>
		</div>'
		return page_shell(page_title, ws, sidebar, main_html, lang)
	}
	// 按 source 分组
	mut groups := map[string][]models.Indicator{}
	for ind in inds {
		groups[ind.source] << ind
	}
	mut groups_html := ''
	source_label := {
		'worldbank': locale.t(lang, 'src_worldbank_full')
		'imf':       locale.t(lang, 'src_imf_full')
		'owid':      locale.t(lang, 'src_owid_full')
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
		groups_html +=
			'
		<div class="panel" style="padding:0;overflow:hidden;margin-bottom:18px">
		<div class="panel-header" style="padding:18px 20px 0">
			<h2 style="margin:0">${h(lb)}</h2><span class="panel-badge">' +
			h(locale.tf(lang, 'items_count', {
			'n': list.len.str()
		})) +
			'</span>
		</div>
		<div class="table-wrap" style="padding:0 4px 4px">
		<table class="data-table" style="border-radius:0">
			<thead><tr><th>' +
			locale.t(lang, 'ind_name') + '</th><th>' + locale.t(lang, 'ind_code') + '</th><th>' +
			locale.t(lang, 'year') + '</th><th>' + locale.t(lang, 'value') +
			'</th></tr></thead>
			<tbody>${rows}</tbody>
		</table>
		</div>
		</div>'
	}
	sidebar := sidebar_html('wb_overview', '', cats, lang)
	main_html := '
	<h1>${flag} ${h(locale.tf(lang, 'country_detail_title', {
		'iso': iso2_safe
	}))}${if iso3 != '' {
		' (' + iso3_safe + ')'
	} else {
		''
	}}</h1>
	<p class="sub">' + locale.t(lang, 'country_sub') + ' · ' + h(locale.tf(lang, 'records_count', {
		'n': inds.len.str()
	})) + '</p>
	${groups_html}'
	return page_shell(page_title, ws, sidebar, main_html, lang)
}

// market_title 各行情页标题与数据源说明
fn market_meta(market string, lang locale.Lang) (string, string) {
	title := match market {
		'cn' { locale.t(lang, 'mk_cn_full') }
		'hk' { locale.t(lang, 'mk_hk_full') }
		'us' { locale.t(lang, 'mk_us_full') }
		'index' { locale.t(lang, 'mk_index_full') }
		'fx' { locale.t(lang, 'mk_fx_full') }
		'commodity' { locale.t(lang, 'mk_commodity_full') }
		else { locale.t(lang, 'mk_default') }
	}
	sub := match market {
		'cn' { locale.t(lang, 'ds_cn') }
		'hk' { locale.t(lang, 'ds_cn') }
		'us' { locale.t(lang, 'ds_cn') }
		'index' { locale.t(lang, 'ds_index') }
		'fx' { locale.t(lang, 'ds_fx') }
		'commodity' { locale.t(lang, 'ds_commodity') }
		else { locale.t(lang, 'ds_multi') }
	}
	return title, locale.t(lang, 'data_source') + '：' + sub
}

// 所有 market 分类（用于 pill tabs 快速切换）
fn market_tabs(active string, lang locale.Lang) string {
	tabs := [
		models.Category{
			id:          'mk_cn'
			title:       locale.t(lang, 'mk_cn')
			source:      'market'
			icon:        '🇨🇳'
			description: ''
		},
		models.Category{
			id:          'mk_hk'
			title:       locale.t(lang, 'mk_hk')
			source:      'market'
			icon:        '🇭🇰'
			description: ''
		},
		models.Category{
			id:          'mk_us'
			title:       locale.t(lang, 'mk_us')
			source:      'market'
			icon:        '🇺🇸'
			description: ''
		},
		models.Category{
			id:          'mk_index'
			title:       locale.t(lang, 'mk_index')
			source:      'market'
			icon:        '📊'
			description: ''
		},
		models.Category{
			id:          'mk_fx'
			title:       locale.t(lang, 'mk_fx')
			source:      'market'
			icon:        '💱'
			description: ''
		},
		models.Category{
			id:          'mk_commodity'
			title:       locale.t(lang, 'mk_commodity')
			source:      'market'
			icon:        '🛢️'
			description: ''
		},
	]
	mut html := '<div class="market-tabs">'
	aid := 'mk_' + active
	for t in tabs {
		cls := if t.id == aid { ' active' } else { '' }
		html += '<a class="market-tab${cls}" href="/category/${a(t.id)}">${t.icon} ${h(t.title)}</a>'
	}
	html += '</div>'
	return html
}

// 市场行情内容片段（供分类页调用，不含外层 shell）
fn market_html(market string, app &App, lang locale.Lang) string {
	title, sub := market_meta(market, lang)
	quotes := app.db.get_market_quotes(market, '') or { []models.MarketQuote{} }
	tabs := market_tabs(market, lang)
	if quotes.len == 0 {
		return
			'
		<h1>${h(title)}</h1>
		<p class="sub">${h(sub)}</p>
		${tabs}
		<div class="empty-state"><div class="emoji">📭</div>
		<p>' +
			locale.t(lang, 'empty_market') + '</p>
		<p style="margin-top:6px;font-size:12px">' +
			locale.t(lang, 'retry_hint') + '</p>
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
		rows += '<tr class="${cls} market-row">
			<td><b>${h(q.name)}</b><div style="font-size:11px;color:var(--text-muted);margin-top:2px">${h(locale.t(lang,
			'data_source'))}: ${h(q.source)}</div></td>
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
	return
		'
	<h1>${h(title)}</h1>
	<p class="sub">${h(sub)}</p>
	${tabs}
	<div class="cards" style="grid-template-columns:repeat(auto-fit,minmax(140px,1fr));margin-bottom:18px">
		<div class="card"><div class="cv">${quotes.len}</div><div class="cl">' +
		h(locale.t(lang, 'mkt_count')) +
		'</div></div>
		<div class="card"><div class="cv" style="color:var(--up)">${up_count}</div><div class="cl">' +
		h(locale.t(lang, 'mkt_up')) +
		'</div></div>
		<div class="card"><div class="cv" style="color:var(--down)">${down_count}</div><div class="cl">' +
		h(locale.t(lang, 'mkt_down')) +
		'</div></div>
		<div class="card"><div class="cv" style="color:${avg_pct_color}">${avg_pct_sign}${fmt2(avg_pct)}%</div><div class="cl">' +
		h(locale.tf(lang, 'mkt_avg', {
		'up': up_pct.str()
	})) +
		'</div></div>
	</div>
	<div class="panel" style="padding:0;overflow:hidden">
	<div class="table-wrap">
	<table class="data-table market" style="border-radius:0">
		<thead><tr><th>' +
		locale.t(lang, 'quote_name') + '</th><th>' + locale.t(lang, 'code') + '</th><th>' +
		locale.t(lang, 'quote_price') + '</th><th>' + locale.t(lang, 'quote_chg') + '</th><th>' +
		locale.t(lang, 'quote_chg_pct') + '</th><th>' + locale.t(lang, 'volume') +
		'</th></tr></thead>
		<tbody>${rows}</tbody>
	</table>
	</div>
	</div>'
}

// 市场页（独立 shell）
fn render_market(ws models.WorldStats, cats []models.Category, market string, _quotes []models.MarketQuote, app &App, lang locale.Lang) string {
	sidebar := sidebar_html('mk_' + market, '', cats, lang)
	main_html := market_html(market, app, lang)
	return page_shell(locale.t(lang, 'market_title'), ws, sidebar, main_html, lang)
}
