module main

import veb
import time
import os
import net.http
import models
import database
import fetch
import locale
import sync

// 编译期嵌入静态资源：单二进制即可独立部署，运行时不依赖源码目录的 static/
const embedded_css = $embed_file('static/css/style.css').to_string()

const embedded_js = $embed_file('static/js/app.js').to_string()

// release_asset 把嵌入的资源释放到程序目录 .assets/ 下，返回绝对路径供 veb 静态服务使用
fn release_asset(fname string, content string) string {
	dir := os.join_path(os.dir(os.executable()), '.assets')
	os.mkdir_all(dir) or {}
	path := os.join_path(dir, fname)
	os.write_file(path, content) or {
		database.log_line('boot', '释放资源失败 ${fname}: ${err}')
		return ''
	}
	return path
}

fn main() {
	css_path := release_asset('style.css', embedded_css)
	js_path := release_asset('app.js', embedded_js)
	mut app := &App{
		static_files: {}
	}
	if css_path != '' {
		app.static_files['/static/css/style.css'] = css_path
	}
	if js_path != '' {
		app.static_files['/static/js/app.js'] = js_path
	}

	// 0. 初始化日志（V log 模块，UTF-8 编码）
	app.db.init_log()

	// 1. 初始化 MySQL + 表结构（数据库不存在时自动创建，支持全新部署）
	database.log_line('boot', '初始化 MySQL...')
	database.ensure_database() or {
		database.log_line('boot', '预创建数据库失败（若库已存在可忽略）: ${err}')
	}
	app.db.connect() or {
		database.log_line('boot', '数据库初始化失败: ${err}')
		return
	}
	database.log_line('boot', 'MySQL 连接成功')

	// 修复历史导入遗留的空 iso3（源 SQLite 的 iso3_code 本身全为空）
	fixed := app.db.backfill_iso3()
	if fixed > 0 {
		database.log_line('boot', '已回填 ${fixed} 个国家的 iso3 代码')
	}

	// 2. SQLite 导入为可选项：设置 WA_IMPORT_SQLITE=1 才会从示例项目导入初始数据。
	// 默认不依赖任何外部目录——首次运行由后台刷新直接从各公开 API 抓取真实数据。
	app.maybe_import_sqlite()

	println('============================================')
	println('  World App - 全面展示我们的世界数据')
	println('  数据源: WorldBank + IMF + Market + OWID')
	println('  数据库: MySQL (all_in_one)')
	println('  访问: http://localhost:3003')
	println('============================================')

	// 3. 后台自动抓取/更新：所有 HTTP 请求带超时（fetch/http_util.v），
	// 无外网时快速失败并写日志，不会阻塞服务器启动。
	// OWID 数据从本地 CSV 导入，无需网络请求。
	go app.background_refresh()

	// 4. 启动 9 秒后自动打开浏览器展示首页（此时服务器已就绪）
	go open_browser_later()

	veb.run_at[App, Context](mut app, port: 3003) or { eprintln('服务器启动失败: $err') }
}

// open_browser_later 启动 9 秒后用系统默认浏览器打开首页。
// 优先 os.open_uri（自动适配 windows/macos/linux 多种 opener）；
// WSL 下若未装任何 Linux opener（xdg-open 等），回退用 cmd.exe 调起 Windows 默认浏览器。
fn open_browser_later() {
	if os.getenv('WA_NO_BROWSER') != '' {
		database.log_line('boot', 'WA_NO_BROWSER 已设置，跳过自动打开浏览器')
		return
	}
	url := 'http://localhost:3003'
	time.sleep(9 * time.second)
	os.open_uri(url) or {
		if is_wsl() && os.execute('cmd.exe /c start "${url}"').exit_code == 0 {
			database.log_line('boot', '已通过 cmd.exe 打开浏览器: ${url}')
			return
		}
		database.log_line('boot', '自动打开浏览器失败: ${err}，请手动访问 ${url}')
	}
}

// is_wsl 判断是否运行在 WSL 环境
fn is_wsl() bool {
	v := os.read_file('/proc/version') or { return false }
	return v.to_lower().contains('microsoft')
}

// maybe_import_sqlite 可选从 SQLite 文件导入初始数据（仅首次运行时，库为空时生效）。
// 默认不依赖任何外部目录——完全由公开 API 抓取真实数据。
// 调试时可通过 WA_SQLITE_PATHS 环境变量指定多个 SQLite 文件路径（逗号分隔）；
// 例如：WA_SQLITE_PATHS="/path/to/data.db,/path/to/market.db" ./world_data
fn (mut app App) maybe_import_sqlite() {
	cnt := app.db.count_countries('') or { 0 }
	mq := app.db.count_market_quotes() or { 0 }
	if cnt > 0 || mq > 0 {
		database.log_line('import',
			'库中已有数据 (countries=${cnt}, quotes=${mq})，跳过 SQLite 导入')
		return
	}
	paths_str := os.getenv('WA_SQLITE_PATHS')
	if paths_str == '' {
		database.log_line('import',
			'未设置 WA_SQLITE_PATHS，跳过 SQLite 导入（后台将从公开 API 抓取数据填充）')
		return
	}
	database.log_line('import', 'WA_SQLITE_PATHS 已设置，开始导入初始数据...')
	mut candidates := []string{}
	for p in paths_str.split(',') {
		trimmed := p.trim(' \t')
		if trimmed != '' {
			candidates << trimmed
		}
	}
	for c in candidates {
		if res := app.db.import_from_sqlite(c) {
			database.log_line('import',
				'已从 ${c} 导入: indicators=${res.indicators}, market=${res.market}')
		}
	}
}

// 后台定时刷新：启动即全量抓取一次；之后每 10 分钟刷新行情/汇率/商品，
// 每 72 个周期（12 小时）做一次全量刷新。
fn (mut app App) background_refresh() {
	app.trigger_fetch_all()
	mut cycles := 0
	for {
		time.sleep(10 * time.minute)
		cycles++
		if cycles % 72 == 0 {
			app.trigger_fetch_all()
		} else {
			app.trigger_fetch_quotes()
		}
	}
}

// run_fetch 统一包装：调用 fn() !int，返回 (ok bool, n int) 并把 error 输出给背景日志。
// 避免 V 的 `if n := foo() { ... } else { fail++; log err }` 在 `else` 块里访问不到 `err` 的陷阱。
fn run_fetch(label string, f fn () !int) (bool, int) {
	n := f() or {
		database.log_line('background', '${label} 失败: ${err}')
		return false, 0
	}
	database.log_line('background', '${label} 完成: ${n}')
	return true, n
}

// trigger_fetch_all 抓取全部数据源（worldbank / imf / market / fx / commodity / owid）
fn (mut app App) trigger_fetch_all() {
	app.mu.lock()
	if app.refresh_running {
		app.mu.unlock()
		database.log_line('background', '抓取已在运行，跳过重复触发')
		return
	}
	app.refresh_running = true
	app.mu.unlock()
	defer {
		app.refresh_running = false
	}
	database.log_line('background', '开始抓取全部数据源...')
	start := time.now()
	total_sources := 7
	mut fail := 0
	// 3 个高频源
	ok_m, _ := run_fetch('market', fn [app] () !int {
		return fetch.fetch_market(app.db)
	})
	if !ok_m { fail++ }
	ok_f, _ := run_fetch('fx', fn [app] () !int {
		return fetch.fetch_fx(app.db)
	})
	if !ok_f { fail++ }
	ok_c, _ := run_fetch('commodity', fn [app] () !int {
		return fetch.fetch_commodity(app.db)
	})
	if !ok_c { fail++ }
	// 2 个宏观源
	ok_w, nw := run_fetch('worldbank(国)', fn [app] () !int {
		return fetch.fetch_worldbank(app.db, 0)
	})
	if !ok_w {
		fail++
	} else {
		database.log_line('background', 'worldbank 完成: ${nw} 个国家')
	}
	ok_i, ni := run_fetch('imf(条)', fn [app] () !int {
		return fetch.fetch_imf(app.db, 0)
	})
	if !ok_i {
		fail++
	} else {
		database.log_line('background', 'imf 完成: ${ni} 条记录')
	}
	// WLD 世界汇总（GDP/人口/预期寿命）
	ok_wld, nwld := run_fetch('worldbank(WLD)', fn [app] () !int {
		return fetch.fetch_wld(app.db)
	})
	if !ok_wld {
		fail++
		database.log_line('background', 'WLD 数据抓取失败（忽略，使用历史数据）')
	} else {
		database.log_line('background', 'WLD 完成: ${nwld} 个指标')
	}
	// OWID 本地 CSV 导入（无需网络）
	ok_owid, nowid := run_fetch('owid', fn [app] () !int {
		return fetch.fetch_owid(app.db)
	})
	if !ok_owid {
		fail++
		database.log_line('background', 'OWID 导入失败（忽略，使用历史数据）')
	} else {
		database.log_line('background', 'OWID 完成: ${nowid} 条记录')
	}
	database.log_line('background',
		'全量抓取结束: ${total_sources - fail}/${total_sources} 个数据源成功, 耗时 ${elapsed_ms(start)}ms')
}

// trigger_fetch_quotes 仅刷新高频数据（股票 / 指数 / 汇率 / 大宗商品）
fn (mut app App) trigger_fetch_quotes() {
	start := time.now()
	mut fail := 0
	ok_m, _ := run_fetch('market', fn [app] () !int {
		return fetch.fetch_market(app.db)
	})
	if !ok_m { fail++ }
	ok_f, _ := run_fetch('fx', fn [app] () !int {
		return fetch.fetch_fx(app.db)
	})
	if !ok_f { fail++ }
	ok_c, _ := run_fetch('commodity', fn [app] () !int {
		return fetch.fetch_commodity(app.db)
	})
	if !ok_c { fail++ }
	database.log_line('background',
		'行情抓取结束: ${3 - fail}/3 成功, 耗时 ${elapsed_ms(start)}ms')
}

// elapsed_ms 自 start 起经过的毫秒数（用于统一日志格式）
// 时钟回拨时防负值（WSL/NTP 同步常见）
fn elapsed_ms(start time.Time) int {
	d := int(time.now().unix_milli() - start.unix_milli())
	return if d > 0 { d } else { 0 }
}

// ============ veb 应用 ============

@[post_init]
pub fn (mut app App) init() {
}

pub struct App {
	veb.Context
pub mut:
	// 以下字段需为 pub mut 才能满足 veb 的 StaticApp 接口，
	// 否则静态文件路由不会生效（/static/* 一律 404）
	static_files                  map[string]string
	static_mime_types             map[string]string
	static_hosts                  map[string]string
	static_prefixes               []string
	enable_static_gzip            bool
	enable_static_zstd            bool
	enable_static_compression     bool
	static_compression_max_size   int
	static_compression_mime_types []string
	enable_markdown_negotiation   bool
	db                            database.Database
	refresh_running               bool
	mu                            sync.Mutex
}

// Context 是 veb 的每请求上下文类型（作为泛型 X 传入 run_at）
struct Context {
	veb.Context
}

pub fn (mut app App) before_request() {
}

// resolve_lang 根据 ?lang= 覆盖 > lang cookie > 默认中文，确定界面语言；
// 若请求中带 ?lang= 则同时写回 cookie，便于后续无参访问保持语言。
fn (mut app App) resolve_lang(mut ctx Context) locale.Lang {
	q := ctx.query['lang'] or { '' }
	if q != '' {
		lang := locale.parse_lang(q)
		ctx.set_cookie(http.Cookie{
			name:    'lang'
			value:   lang.str()
			path:    '/'
			max_age: 86400 * 365
		})
		return lang
	}
	c := ctx.get_cookie('lang') or { '' }
	return locale.parse_lang(c)
}

// 首页：概览 + 右侧栏
@['/']
pub fn (mut app App) index(mut ctx Context) veb.Result {
	lang := app.resolve_lang(mut ctx)
	ws := app.db.get_world_stats() or { models.WorldStats{} }
	cats := models.all_categories()
	html := render_page('overview', ws, cats, '', app, lang)
	return ctx.html(html)
}

// 分类页面：右侧栏点击进入
@['/category/:id']
pub fn (mut app App) category_view(mut ctx Context, id string) veb.Result {
	lang := app.resolve_lang(mut ctx)
	ws := app.db.get_world_stats() or { models.WorldStats{} }
	cats := models.all_categories()
	search := ctx.query['search'] or { '' }
	html := render_page(id, ws, cats, search, app, lang)
	return ctx.html(html)
}

// 国家详情（含该国全部指标）
@['/country/:iso2']
pub fn (mut app App) country_detail(mut ctx Context, iso2 string) veb.Result {
	lang := app.resolve_lang(mut ctx)
	ws := app.db.get_world_stats() or { models.WorldStats{} }
	cats := models.all_categories()
	// 获取 WorldBank + IMF 指标
	inds := app.db.get_indicators_for_country(iso2) or { []models.Indicator{} }
	// 获取 OWID 指标
	owid_inds := app.db.get_owid_country_indicators(iso2) or { []models.Indicator{} }
	// 合并
	mut all_inds := []models.Indicator{}
	all_inds << inds
	all_inds << owid_inds
	html := render_country(ws, cats, iso2, all_inds, app, lang)
	return ctx.html(html)
}

// 市场行情页面
@['/market/:market']
pub fn (mut app App) market_view(mut ctx Context, market string) veb.Result {
	lang := app.resolve_lang(mut ctx)
	ws := app.db.get_world_stats() or { models.WorldStats{} }
	cats := models.all_categories()
	quotes := app.db.get_market_quotes(market, '') or { []models.MarketQuote{} }
	html := render_market(ws, cats, market, quotes, app, lang)
	return ctx.html(html)
}

// 搜索接口（右侧栏搜索）
@['/search']
pub fn (mut app App) search_api(mut ctx Context) veb.Result {
	q := ctx.query['q'] or { '' }
	mut result := SearchResult{}
	result.countries = app.db.get_countries(20, 0, q) or { []models.Country{} }
	result.quotes = app.db.get_market_quotes('', q) or { []models.MarketQuote{} }
	return ctx.json(result)
}

// 状态接口（供前端自动刷新轮询）
@['/api/stats']
pub fn (mut app App) api_stats(mut ctx Context) veb.Result {
	ws := app.db.get_world_stats() or { models.WorldStats{} }
	logs := app.db.recent_logs(5) or { []models.FetchLog{} }
	app.mu.lock()
	fetching := app.refresh_running
	app.mu.unlock()
	return ctx.json(ApiStats{ stats: ws, logs: logs, fetching: fetching })
}

// 手动触发刷新
@['/api/refresh']
pub fn (mut app App) api_refresh(mut ctx Context) veb.Result {
	go app.trigger_fetch_all()
	return ctx.json(RefreshResp{ status: 'started' })
}

struct RefreshResp {
	status string
}

@['/api/imf_top']
pub fn (mut app App) api_imf_top(mut ctx Context) veb.Result {
	top := app.db.get_indicator_top('imf', 'NGDPD', 20) or { []models.Indicator{} }
	mut labels := []string{}
	mut values := []f64{}
	for ind in top {
		labels << ind.country_iso
		values << ind.value
	}
	return ctx.json(ImfTop{ labels: labels, values: values })
}

struct ImfTop {
	labels []string
	values []f64
}

struct SearchResult {
pub mut:
	countries []models.Country
	quotes    []models.MarketQuote
}

struct ApiStats {
	stats    models.WorldStats
	logs     []models.FetchLog
	fetching bool
}
