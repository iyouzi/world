module database

import db.mysql
import db.sqlite
import log
import models
import os
import time

// Database 持有 MySQL 连接句柄（DB 为值类型，内部持有连接指针），
// 由 main 中的 App 内嵌持有，不再使用全局变量。
pub struct Database {
pub mut:
	db     mysql.DB
	open   bool
	logger log.ThreadSafeLog
}

// connect 配置（可由环境变量覆盖）
// 注意：mysql.Config 在 V 0.5.x 不支持 timeout 字段，超时依赖底层连接池默认值 +
// fetch/http_util.v 中的 HTTP 读/写超时保证整体不挂起。
fn config() mysql.Config {
	mut host := os.getenv('MYSQL_HOST')
	mut port := (os.getenv('MYSQL_PORT')).u32()
	mut user := os.getenv('MYSQL_USER')
	mut pass := os.getenv('MYSQL_PASS')
	mut dbname := os.getenv('MYSQL_DB')
	if host == '' {
		host = '127.0.0.1'
	}
	if port == 0 {
		port = 3306
	}
	if user == '' {
		user = 'world'
	}
	if pass == '' {
		pass = 'world123'
	}
	if dbname == '' {
		dbname = 'all_in_one'
	}
	return mysql.Config{
		host: host
		port: port
		user: user
		username: user
		password: pass
		dbname: dbname
	}
}

// connect 打开（或复用）MySQL 连接并初始化表结构
pub fn (mut d Database) connect() ! {
	if d.open {
		return
	}
	mut m := mysql.connect(config()) or { return error('MySQL 连接失败: ${err}') }
	d.db = m
	d.open = true
	d.init_schema() or { return error('初始化表结构失败: ${err}') }
}

// handle 返回底层 MySQL 句柄（供 fetch 等模块直接执行 SQL）
@[inline]
pub fn (d &Database) handle() mysql.DB {
	return d.db
}

// exec_params 在数据库端实现一个简单的参数化替换，用于替换代码中大量的字符串拼接。
// 说明：优选使用原生 prepared statement（若 mysql.DB 支持），但为兼容不同环境此处实现基于占位符 '?' 的安全替换：
// - 对看起来像数字的参数直接原样插入（不加引号）
// - 对其他参数使用 sql_escape 并用单引号包裹
// 这样可以显著降低 SQL 注入风险（相比直接字符串拼接更安全）。
pub fn (d &Database) exec_params(query string, params ...string) ([]mysql.Row, error) {
	mut s := query
	for p in params {
		insert := ''
		if p.len == 0 {
			insert = "''"
		} else if is_numeric(p) {
			insert = p
		} else {
			insert = "'${sql_escape(p)}'"
		}
		// replace first occurrence of '?' with insert
		idx := s.index_after('?', 0)
		if idx == -1 {
			// no placeholder left; append
			s += ' ' + insert
		} else {
			s = s[..idx] + insert + s[idx+1..]
		}
	}
	rows := d.handle().exec(s) or { return []mysql.Row{}, error('exec_params failed: ${err}') }
	return rows, nil
}

fn is_numeric(s string) bool {
	mut seen_dot := false
	for ch in s.bytes() {
		if ch >= `0` && ch <= `9` {
			continue
		}
		if ch == `.` && !seen_dot {
			seen_dot = true
			continue
		}
		if ch == `-` {
			continue
		}
		if ch == `e` || ch == `E` {
			continue
		}
		return false
	}
	return true
}

// table_exists 检查指定表是否已存在
fn (d &Database) table_exists(name string) bool {
	m := d.handle()
	rows := m.exec("SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = '${sql_escape(name)}' LIMIT 1") or {
		return false
	}
	return rows.len > 0
}

// init_schema 仅在表不存在时创建对应表（已存在则跳过，避免无谓重建）
pub fn (mut d Database) init_schema() ! {
	m := d.handle()
	stmts := {
		'countries':     'CREATE TABLE countries (
			id INT AUTO_INCREMENT PRIMARY KEY,
			iso2 VARCHAR(4) NOT NULL UNIQUE,
			iso3 VARCHAR(4),
			name VARCHAR(120),
			region VARCHAR(80),
			income VARCHAR(40),
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
		'indicators':    'CREATE TABLE indicators (
			id INT AUTO_INCREMENT PRIMARY KEY,
			source VARCHAR(20) NOT NULL,
			country_iso VARCHAR(4) NOT NULL,
			indicator VARCHAR(40) NOT NULL,
			label VARCHAR(120),
			year INT,
			value DOUBLE,
			unit VARCHAR(20),
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
			UNIQUE KEY uq_ind (source, country_iso, indicator, year),
			INDEX idx_ind_country (country_iso),
			INDEX idx_ind_src (source, indicator)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
		'market_quotes': 'CREATE TABLE market_quotes (
			id INT AUTO_INCREMENT PRIMARY KEY,
			symbol VARCHAR(20) NOT NULL UNIQUE,
			name VARCHAR(120),
			market VARCHAR(10),
			price DOUBLE,
			prev_close DOUBLE,
			chg DOUBLE,
			chg_pct DOUBLE,
			volume BIGINT,
			source VARCHAR(20),
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
		'fetch_logs':    'CREATE TABLE fetch_logs (
			id INT AUTO_INCREMENT PRIMARY KEY,
			source VARCHAR(20),
			status VARCHAR(20),
			message TEXT,
			records INT DEFAULT 0,
			started_at DATETIME,
			duration_ms INT DEFAULT 0
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
	}
	for name, stmt in stmts {
		if d.table_exists(name) {
			log_line('schema', '表已存在，跳过创建: ${name}')
			continue
		}
		m.exec(stmt) or { return error('建表失败 (${name}): ${err}') }
		log_line('schema', '已创建表: ${name}')
	}
}

// ensure_database 若指定数据库不存在则创建（用于全新部署），已存在则跳过
pub fn ensure_database() ! {
	cfg := config()
	mut m := mysql.connect(mysql.Config{
		host: cfg.host
		port: cfg.port
		username: cfg.username
		password: cfg.password
		dbname: 'mysql'
	}) or { return error('连接系统库失败: ${err}') }
	dbname := cfg.dbname
	// 仅当库不存在时创建，避免每次启动都执行 CREATE DATABASE
	exists_rows := m.exec("SELECT 1 FROM information_schema.schemata WHERE schema_name = '${sql_escape(dbname)}' LIMIT 1") or {
		[]mysql.Row{}
	}
	if exists_rows.len == 0 {
		q := 'CREATE DATABASE ' + dbname + ' CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci'
		m.exec(q) or { return error('创建数据库失败 (${q}): ${err}') }
		log_line('boot', '已创建数据库: ${dbname}')
	} else {
		log_line('boot', '数据库已存在，跳过创建: ${dbname}')
	}
	m.close() or {}
}

pub fn (mut d Database) close() {
	if d.open {
		d.db.close() or {}
		d.open = false
	}
}

// ============ 日志 ============

// log_file_path 日志文件路径：程序可执行文件所在目录下的 world_data.log
fn log_file_path() string {
	return os.join_path(os.dir(os.executable()), 'world_data.log')
}

// init_log 初始化日志文件（V log 模块，UTF-8 编码）。
// 必须在 main() 最早调用，之后 log_fetch 等方法会使用 logger。
pub fn (mut d Database) init_log() {
	d.logger.set_output_path(log_file_path())
	d.logger.set_always_flush(true)
	println('[log] 日志已初始化: ${log_file_path()}')
}

// log_line 运行期日志：同步输出到 stderr 并写入 world_data.log（UTF-8）。
// 所有启动步骤 / 抓取成功失败 / 异常都必须经过这里。
pub fn log_line(tag string, msg string) {
	line := '[${tag}] ${msg}'
	eprintln(line)
	mut f := os.open_file(log_file_path(), 'a', 0o644) or { return }
	f.write_string('${line}\n') or {}
	f.close()
}

pub fn (d &Database) log_fetch(source string, status string, message string, records int, duration_ms int) {
	log_line(source, '${status}: ${message} (${records} 条, ${duration_ms}ms)')
	m := d.handle()
	now_str := format_datetime(time.now())
	_, _ = d.exec_params("INSERT INTO fetch_logs (source, status, message, records, started_at, duration_ms) VALUES (?,?,?,?,?,?)", source, status, message, '${records}', now_str, '${duration_ms}') or {
		log_line('fetch', '写入 fetch_logs 失败: \$err')
	}
}

// format_datetime 统一日志时间格式：MySQL DATETIME 兼容（YYYY-MM-DD HH:MM:SS，无 T/Z）
fn format_datetime(t time.Time) string {
	y := t.year
	m := int(t.month)
	d := t.day
	h := t.hour
	mi := t.minute
	s := t.second
	return '${y:04d}-${m:02d}-${d:02d} ${h:02d}:${mi:02d}:${s:02d}'
}

// sql_escape 安全转义：反斜杠优先（避免 '→\' 再次被解释），单/双引号，控制字符。
fn sql_escape(s string) string {
	return s.replace('\\', '\\\\').replace("'", "\\'").replace('"', '\\"').replace('\n', '\\n').replace('\r', '').replace('\0', '')
}

// ============ SQLite -> MySQL 导入（作为初始数据）============
pub struct ImportResult {
pub mut:
	countries  int
	indicators int
	market     int
}

// import_from_sqlite 从给定 SQLite 文件导入（若存在）
pub fn (mut d Database) import_from_sqlite(sqlite_path string) !ImportResult {
	if !os.exists(sqlite_path) {
		return error('SQLite 文件不存在: \$sqlite_path')
	}
	mut sdb := sqlite.connect(sqlite_path) or { return error('打开 SQLite 失败: \$err') }
	defer {
		sdb.close() or {}
	}
	mut res := ImportResult{}
	res.indicators += d.import_worldbank_sqlite(sdb) or { 0 }
	res.market += d.import_market_sqlite(sdb) or { 0 }
	eprintln('[import] ${sqlite_path}: indicators=${res.indicators}, market=${res.market}')
	return res
}

fn (mut d Database) import_worldbank_sqlite(sdb sqlite.DB) !int {
	// 检测 worldbank info 结构: countries + data_cache
	trows := sdb.exec("SELECT name FROM sqlite_master WHERE type='table' AND (name='countries' OR name='data_cache')") or {
		return 0
	}
	if trows.len == 0 {
		return 0
	}
	mut m := d.handle()
	// 导入国家（源库 iso3_code 全为空，用 models.iso2_to_iso3 补齐）
	crows := sdb.exec('SELECT iso2_code, iso3_code, name, region, income_level FROM countries') or {
		[]
	}
	mut cins := 0
	for r in crows {
		v := r.vals
		iso2 := v[0]
		iso3 := if v[1] != '' { v[1] } else { models.iso2_to_iso3(iso2) }
		cname := v[2]
		region := v[3]
		income := v[4]
		_, _ = d.exec_params("INSERT IGNORE INTO countries (iso2, iso3, name, region, income) VALUES (?,?,?,?,?)", iso2, iso3, cname, region, income) or {
			eprintln('[import] country insert err: ${err}')
		}
		cins++
	}
	eprintln('[import] countries read=${crows.len}, inserted=${cins}')
	// 导入指标（data_cache: country_code, indicator_id, date, value）
	drows := sdb.exec('SELECT country_code, indicator_id, date, value FROM data_cache') or { [] }
	mut n := 0
	for r in drows {
		v := r.vals
		cc := v[0]
		ind := v[1]
		dt := v[2]
		val := v[3].f64()
		if val == 0 {
			continue
		}
		yr := dt.int()
		label := indicator_label(ind)
		_, _ = d.exec_params("INSERT INTO indicators (source, country_iso, indicator, label, year, value, unit) VALUES (?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE value=VALUES(value), year=VALUES(year), updated_at=CURRENT_TIMESTAMP", 'worldbank', cc, ind, label, '${yr}', '${val}', '') or {}
		n++
	}
	return n
}

fn indicator_label(code string) string {
	match code {
		'NY.GDP.MKTP.CD' {
			return 'GDP'
		}
		'SP.POP.TOTL' {
			return 'Population'
		}
		'SP.DYN.LE00.IN' {
			return 'Life expectancy'
		}
		'NY.GDP.PCAP.KD' {
			return 'GDP per capita'
		}
		'FP.CPI.TOTL.ZG' {
			return 'Inflation %'
		}
		'SL.UEM.TOTL.NE.ZS' {
			return 'Unemployment %'
		}
		else {
			return code
		}
	}
}

// backfill_iso3 修复历史导入遗留的空 iso3（源 SQLite 的 iso3_code 本身全为空）。
// 仅更新能映射上的行；启动时调用，幂等。
pub fn (d &Database) backfill_iso3() int {
	mut m := d.handle()
	rows := m.exec("SELECT iso2 FROM countries WHERE iso3 IS NULL OR iso3 = ''") or {
		log_line('iso3', '查询空 iso3 失败: ${err}')
		return 0
	}
	mut fixed := 0
	for r in rows {
		iso3 := models.iso2_to_iso3(r.vals[0])
		if iso3 == '' {
			continue
		}
		_, _ = d.exec_params("UPDATE countries SET iso3 = ? WHERE iso2 = ?", iso3, r.vals[0]) or {
			continue
		}
		fixed++
	}
	return fixed
}

fn (mut d Database) import_market_sqlite(sdb sqlite.DB) !int {
	trows := sdb.exec("SELECT name FROM sqlite_master WHERE type='table' AND name='stocks'") or {
		return 0
	}
	if trows.len == 0 {
		return 0
	}
	data := sdb.exec('SELECT symbol, name, price, change_val, change_pct, volume, source FROM stocks') or {
		[]
	}
	mut m := d.handle()
	mut n := 0
	for r in data {
		v := r.vals
		symbol := v[0]
		sname := v[1]
		price := v[2].f64()
		chg := v[3].f64()
		pct := v[4].f64()
		vol := v[5].i64()
		src := v[6]
		market := market_of(symbol, src)
		_, _ = d.exec_params("INSERT INTO market_quotes (symbol, name, market, price, prev_close, chg, chg_pct, volume, source) VALUES (?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE price=VALUES(price), chg=VALUES(chg), chg_pct=VALUES(chg_pct)", symbol, sname, market, '${price}', '${price}', '${chg}', '${pct}', '${vol}', src) or {}
		n++
	}
	return n
}

fn market_of(symbol string, source string) string {
	sym_low := symbol.to_lower()
	low := source.to_lower()
	// 优先按 symbol 前缀分类（与 fetch.market.default_symbols / fx_pairs 对齐）
	if sym_low.starts_with('us') {
		return 'us'
	}
	if sym_low.starts_with('hk') {
		return 'hk'
	}
	if sym_low.starts_with('sh') || sym_low.starts_with('sz') {
		return 'cn'
	}
	// 外汇代码：长度 6，其中 3 字符货币对（USDCNY、EURUSD 等）
	if sym_low.len >= 6 {
		quote3 := sym_low[3..6]
		base3 := sym_low[0..3]
		if quote3 == 'usd' || quote3 == 'cny' || base3 == 'usd' || base3 == 'eur' || base3 == 'gbp' || base3 == 'aud' {
			return 'fx'
		}
	}
	// 按 source 回退
	if low.contains('us') || low.contains('nasdaq') {
		return 'us'
	}
	if low.contains('hk') {
		return 'hk'
	}
	if low.contains('index') {
		return 'index'
	}
	if low.contains('commodity') || low.contains('future') || low.contains('sina') {
		return 'commodity'
	}
	return 'cn'
}

// ============ 查询接口（基于 exec 解析 Row）============
fn to_i(s string) int {
	return s.int()
}

fn to_f(s string) f64 {
	return s.f64()
}

pub fn (d &Database) get_countries(limit int, offset int, search string) ![]models.Country {
	m := d.handle()
	mut where := ''
	if search != '' {
		safe := sql_escape(search)
		where = " WHERE (name LIKE '%${safe}%' OR iso2 LIKE '%${safe}%' OR iso3 LIKE '%${safe}%')"
	}
	q := 'SELECT id, iso2, iso3, name, region, income, created_at FROM countries${where} ORDER BY id LIMIT ${limit} OFFSET ${offset}'
	rows := m.exec(q) or { return []models.Country{} }
	mut out := []models.Country{}
	for r in rows {
		v := r.vals
		out << models.Country{
			id: to_i(v[0])
			iso2: v[1]
			iso3: v[2]
			name: v[3]
			region: v[4]
			income: v[5]
			created_at: v[6]
		}
	}
	return out
}

pub fn (d &Database) count_countries(search string) !int {
	m := d.handle()
	mut where := ''
	if search != '' {
		safe := sql_escape(search)
		where = " WHERE (name LIKE '%${safe}%' OR iso2 LIKE '%${safe}%' OR iso3 LIKE '%${safe}%')"
	}
	rows := m.exec('SELECT COUNT(*) AS c FROM countries${where}') or { return 0 }
	if rows.len == 0 {
		return 0
	}
	return to_i(rows[0].vals[0])
}

pub fn (d &Database) get_indicators_for_country(iso2 string) ![]models.Indicator {
	m := d.handle()
	q := "SELECT id, source, country_iso, indicator, label, year, value, unit, updated_at FROM indicators WHERE country_iso = '${sql_escape(iso2)}' ORDER BY indicator"
	rows := m.exec(q) or { return []models.Indicator{} }
	return parse_indicators(rows)
}

pub fn (d &Database) get_indicator_top(source string, indicator string, limit int) ![]models.Indicator {
	m := d.handle()
	q := "SELECT id, source, country_iso, indicator, label, year, value, unit, updated_at FROM indicators WHERE source = '${sql_escape(source)}' AND indicator = '${sql_escape(indicator)}' ORDER BY value DESC LIMIT ${limit}"
	rows := m.exec(q) or { return []models.Indicator{} }
	return parse_indicators(rows)
}

// get_country_indicator_top 返回各国某指标最新年份的 Top N（每人只取一条，按值降序），
// JOIN countries 表带回国家名称，避免同国家多年数据重复出现。
pub fn (d &Database) get_country_indicator_top(source string, indicator string, limit int) ![]models.CountryGdp {
	m := d.handle()
	q := 'SELECT c.iso2, c.name, i.value, i.year FROM indicators i ' + 'JOIN countries c ON c.iso2 = i.country_iso ' + "WHERE i.source = '${sql_escape(source)}' AND i.indicator = '${sql_escape(indicator)}' " + "AND i.year = (SELECT MAX(year) FROM indicators i2 WHERE i2.country_iso = i.country_iso AND i2.source = '${sql_escape(source)}' AND i2.indicator = '${sql_escape(indicator)}') " + 'ORDER BY i.value DESC LIMIT ${limit}'
	rows := m.exec(q) or { return []models.CountryGdp{} }
	mut out := []models.CountryGdp{}
	for r in rows {
		v := r.vals
		out << models.CountryGdp{
			iso2: v[0]
			name: v[1]
			value: v[2].f64()
			year: v[3].int()
		}
	}
	return out
}

// get_country_gdp_top 返回各国最新年份的 GDP（每人只取一条，按值降序），
// 并 JOIN countries 表带回国家名称。用于首页 GDP 排行榜。
pub fn (d &Database) get_country_gdp_top(limit int) ![]models.CountryGdp {
	m := d.handle()
	// 子查询：每个国家取最新年份的记录，外层按 value 排序
	q := 'SELECT c.iso2, c.name, i.value, i.year FROM indicators i ' + 'JOIN countries c ON c.iso2 = i.country_iso ' + "WHERE i.source = 'worldbank' AND i.indicator = 'NY.GDP.MKTP.CD' " + "AND i.year = (SELECT MAX(year) FROM indicators i2 WHERE i2.country_iso = i.country_iso AND i2.source = 'worldbank' AND i2.indicator = 'NY.GDP.MKTP.CD') " + 'ORDER BY i.value DESC LIMIT ${limit}'
	rows := m.exec(q) or { return []models.CountryGdp{} }
	mut out := []models.CountryGdp{}
	for r in rows {
		v := r.vals
		out << models.CountryGdp{
			iso2: v[0]
			name: v[1]
			value: v[2].f64()
			year: v[3].int()
		}
	}
	return out
}

// get_home_countries 返回 G20+ 主要国家首页概览数据（人口、面积、GDP、PPP 等）。
// 如果某个指标缺数据则对应字段为 0；year 取 GDP 最新年份。
pub fn (d &Database) get_home_countries() ![]models.HomeCountry {
	m := d.handle()
	// G20 成员 + 其他影响力较大的国家（约 50 个）
	countries := [
		'US',
		'CN',
		'JP',
		'DE',
		'IN',
		'GB',
		'FR',
		'BR',
		'IT',
		'CA',
		'KR',
		'RU',
		'AU',
		'MX',
		'ES',
		'ID',
		'TR',
		'SA',
		'NL',
		'CH',
		'PL',
		'SE',
		'BE',
		'NO',
		'AT',
		'TH',
		'IE',
		'IL',
		'ZA',
		'DK',
		'AR',
		'SG',
		'MY',
		'PH',
		'EG',
		'NG',
		'CL',
		'CO',
		'PK',
		'BD',
		'VN',
		'PE',
		'CZ',
		'RO',
		'NZ',
		'FI',
		'PT',
		'GR',
		'PE',
		'NG',
	]
	mut q_iso := ''
	for i, c in countries {
		if i > 0 {
			q_iso += ','
		}
		q_iso += "'" + c + "'"
	}
	// 构建子查询：每个国家取各指标最新年份
	mut sql_str := 'SELECT c.iso2, c.name, ' + "(SELECT i.value FROM indicators i WHERE i.country_iso=c.iso2 AND i.source='worldbank' AND i.indicator='SP.POP.TOTL' ORDER BY i.year DESC LIMIT 1) AS pop, " + "(SELECT i.value FROM indicators i WHERE i.country_iso=c.iso2 AND i.source='worldbank' AND i.indicator='AG.LND.TOTL.K2' ORDER BY i.year DESC LIMIT 1) AS area, " + "(SELECT i.value FROM indicators i WHERE i.country_iso=c.iso2 AND i.source='worldbank' AND i.indicator='NY.GDP.MKTP.CD' ORDER BY i.year DESC LIMIT 1) AS gdp, " + "(SELECT i.value FROM indicators i WHERE i.country_iso=c.iso2 AND i.source='worldbank' AND i.indicator='NY.GDP.MKTP.PP.CD' ORDER BY i.year DESC LIMIT 1) AS gdp_ppp, " + "(SELECT i.value FROM indicators i WHERE i.country_iso=c.iso2 AND i.source='worldbank' AND i.indicator='NY.GDP.PCAP.CD' ORDER BY i.year DESC LIMIT 1) AS gdppc, " + "(SELECT i.value FROM indicators i WHERE i.country_iso=c.iso2 AND i.source='worldbank' AND i.indicator='NY.GDP.PCAP.PP.CD' ORDER BY i.year DESC LIMIT 1) AS gdppc_ppp, " + "(SELECT i.year FROM indicators i WHERE i.country_iso=c.iso2 AND i.source='worldbank' AND i.indicator='NY.GDP.MKTP.CD' ORDER BY i.year DESC LIMIT 1) AS yr " + 'FROM countries c WHERE c.iso2 IN (' + q_iso + ') ORDER BY gdp DESC'
	rows := m.exec(sql_str) or { return []models.HomeCountry{} }
	mut out := []models.HomeCountry{}
	for r in rows {
		v := r.vals
		pop := to_f(v[2])
		area := to_f(v[3])
		gdp := to_f(v[4])
		gdp_ppp := to_f(v[5])
		gdppc := to_f(v[6])
		gdppc_ppp := to_f(v[7])
		mut ppp_per_sqkm := 0.0
		if area > 0 && gdp_ppp > 0 {
			ppp_per_sqkm = gdp_ppp / area
		}
		out << models.HomeCountry{
			iso2: v[0]
			name: v[1]
			population: pop
			land_area: area
			gdp: gdp
			gdp_ppp: gdp_ppp
			gdp_per_capita: gdppc
			gdp_ppc_ppp: gdppc_ppp
			ppp_per_sqkm: ppp_per_sqkm
			note: ''
			year: to_i(v[8])
		}
	}
	return out
}

fn parse_indicators(rows []mysql.Row) []models.Indicator {
	mut out := []models.Indicator{}
	for r in rows {
		v := r.vals
		out << models.Indicator{
			id: to_i(v[0])
			source: v[1]
			country_iso: v[2]
			indicator: v[3]
			label: v[4]
			year: to_i(v[5])
			value: to_f(v[6])
			unit: v[7]
			updated_at: v[8]
		}
	}
	return out
}

pub fn (d &Database) get_world_stats() !models.WorldStats {
	m := d.handle()
	mut ws := models.WorldStats{}
	rows := m.exec('SELECT COUNT(*) AS c FROM countries') or { return ws }
	if rows.len > 0 {
		ws.total_countries = to_i(rows[0].vals[0])
	}
	// 世界总 GDP：优先用 WLD（WorldBank 官方汇总），回退到各国累加
	ws.total_gdp = d.get_wld_indicator_value('NY.GDP.MKTP.CD')
	if ws.total_gdp == 0 {
		rows2 := m.exec("SELECT SUM(value) AS s FROM indicators WHERE source='worldbank' AND indicator='NY.GDP.MKTP.CD'") or {
			return ws
		}
		if rows2.len > 0 {
			ws.total_gdp = to_f(rows2[0].vals[0])
		}
	}
	// 世界人口：优先 WLD，回退累加
	ws.total_population = d.get_wld_indicator_value('SP.POP.TOTL')
	if ws.total_population == 0 {
		rows2 := m.exec("SELECT SUM(value) AS s FROM indicators WHERE source='worldbank' AND indicator='SP.POP.TOTL'") or {
			return ws
		}
		if rows2.len > 0 {
			ws.total_population = to_f(rows2[0].vals[0])
		}
	}
	// 平均预期寿命：用 WLD 最新值，回退各国平均
	ws.avg_life = d.get_wld_indicator_value('SP.DYN.LE00.IN')
	if ws.avg_life == 0 {
		rows3 := m.exec("SELECT AVG(value) AS s FROM indicators WHERE source='worldbank' AND indicator='SP.DYN.LE00.IN'") or {
			return ws
		}
		if rows3.len > 0 {
			ws.avg_life = to_f(rows3[0].vals[0])
		}
	}
	// WLD 补充指标（可选，无数据时保持 0）
	ws.gdp_per_capita = d.get_wld_indicator_value('NY.GDP.PCAP.KD')
	ws.inflation = d.get_wld_indicator_value('FP.CPI.TOTL.ZG')
	ws.unemployment = d.get_wld_indicator_value('SL.UEM.TOTL.NE.ZS')
	ws.internet_users = d.get_wld_indicator_value('IT.NET.USER.ZS')
	ws.education_spend = d.get_wld_indicator_value('SE.XPD.TOTL.GD.ZS')
	ws.health_spend = d.get_wld_indicator_value('SH.XPD.CHEX.GD.ZS')
	ws.energy_use = d.get_wld_indicator_value('EG.USE.PCAP.KG.OE')
	rows4 := m.exec('SELECT MAX(updated_at) AS s FROM indicators') or { return ws }
	if rows4.len > 0 {
		ws.last_update = rows4[0].vals[0]
	}
	return ws
}

pub fn (d &Database) get_world_pop() !f64 {
	m := d.handle()
	// 优先 WLD 汇总数据，回退到各国累加
	v := d.get_wld_indicator_value('SP.POP.TOTL')
	if v != 0 {
		return v
	}
	rows := m.exec("SELECT SUM(value) AS s FROM indicators WHERE source='worldbank' AND indicator='SP.POP.TOTL'") or {
		return 0.0
	}
	if rows.len > 0 {
		return to_f(rows[0].vals[0])
	}
	return 0.0
}

// get_wld_indicator_value 查询 WLD（WorldBank 世界汇总）某指标的最新值；无数据返回 0。
pub fn (d &Database) get_wld_indicator_value(indicator string) f64 {
	m := d.handle()
	q := "SELECT value FROM indicators WHERE source='worldbank' AND country_iso='WLD' AND indicator='${sql_escape(indicator)}' ORDER BY year DESC LIMIT 1"
	rows := m.exec(q) or { return 0.0 }
	if rows.len > 0 {
		return rows[0].vals[0].f64()
	}
	return 0.0
}

pub fn (d &Database) get_market_quotes(market string, search string) ![]models.MarketQuote {
	m := d.handle()
	mut where := ''
	mut conds := []string{}
	if market != '' {
		conds << "market = '${sql_escape(market)}'"
	}
	if search != '' {
		safe := sql_escape(search)
		// 注意：OR 两侧必须用括号，否则与 market 条件组合时优先级错误
		conds << "(name LIKE '%${safe}%' OR symbol LIKE '%${safe}%')"
	}
	if conds.len > 0 {
		where = ' WHERE ' + conds.join(' AND ')
	}
	q := 'SELECT id, symbol, name, market, price, prev_close, chg, chg_pct, volume, source, updated_at FROM market_quotes${where} ORDER BY market, symbol'
	rows := m.exec(q) or { return []models.MarketQuote{} }
	mut out := []models.MarketQuote{}
	for r in rows {
		v := r.vals
		out << models.MarketQuote{
			id: to_i(v[0])
			symbol: v[1]
			name: v[2]
			market: v[3]
			price: to_f(v[4])
			prev_close: to_f(v[5])
			change: to_f(v[6])
			change_pct: to_f(v[7])
			volume: v[8].i64()
			source: v[9]
			updated_at: v[10]
		}
	}
	return out
}

pub fn (d &Database) count_market_quotes() !int {
	m := d.handle()
	rows := m.exec('SELECT COUNT(*) AS c FROM market_quotes') or { return 0 }
	if rows.len == 0 {
		return 0
	}
	return to_i(rows[0].vals[0])
}

pub fn (d &Database) recent_logs(limit int) ![]models.FetchLog {
	m := d.handle()
	rows := m.exec('SELECT id, source, status, message, records, started_at, duration_ms FROM fetch_logs ORDER BY id DESC LIMIT ${limit}') or {
		return []models.FetchLog{}
	}
	mut out := []models.FetchLog{}
	for r in rows {
		v := r.vals
		out << models.FetchLog{
			id: to_i(v[0])
			source: v[1]
			status: v[2]
			message: v[3]
			records: to_i(v[4])
			started_at: v[5]
			duration_ms: to_i(v[6])
		}
	}
	return out
}

// ============ OWID 数据导入与查询 ============

// import_owid_csv 从 CSV 文件导入 OWID 数据到 indicators 表（source='owid'）。
// csv_path: CSV 文件路径；indicator_code: 指标代码（如 'population'）；
// label: 指标中文名；unit: 单位；column_name: CSV 数值列名（空则用第 4 列）。
pub fn (mut d Database) import_owid_csv(csv_path string, indicator_code string, label string, unit string, column_name string) !int {
	m := d.handle()
	csv_text := os.read_file(csv_path) or { return error('读取 CSV 失败: ${err}') }
	lines := csv_text.split('\n')
	if lines.len < 2 {
		return error('CSV 文件为空或仅有表头')
	}
	// 解析表头，确定数值列索引
	header := lines[0].split(',')
	mut val_col := 3 // 默认第 4 列
	if column_name != '' {
		for i, col in header {
			if col.trim_space() == column_name {
				val_col = i
				break
			}
		}
	}
	mut count := 0
	mut skipped := 0
	for line_idx := 1; line_idx < lines.len; line_idx++ {
		line := lines[line_idx].trim_space()
		if line == '' {
			continue
		}
		parts := line.split(',')
		if parts.len < 4 {
			skipped++
			continue
		}
		entity_name := sql_escape(parts[0].trim_space())
		iso3_code := parts[1].trim_space()
		year_str := parts[2].trim_space()
		val_str := if val_col < parts.len { parts[val_col].trim_space() } else { '' }
		if val_str == '' || val_str == 'nan' || val_str == 'N/A' || val_str == 'NaN' {
			skipped++
			continue
		}
		year := year_str.int()
		if year < 1000 || year > 2100 {
			skipped++
			continue
		}
		value := val_str.f64()
		if value == 0 && val_str != '0' && val_str != '0.0' {
			skipped++
			continue
		}
		// ISO3 → ISO2 转换
		mut iso2 := models.iso3_to_iso2(iso3_code)
		if iso2 == '' {
			// 空 code 或聚合实体（如 WLD、ASEAN）跳过
			if iso3_code.len < 2 {
				skipped++
				continue
			}
			// 可能是 ISO2 直写（非标准但兼容）
			if iso3_code.len == 2 && models.iso3_to_iso2(iso3_code) == iso3_code {
				iso2 = iso3_code
			} else {
				skipped++
				continue
			}
		}
		country_iso := if iso2 != '' { iso2 } else { iso3_code }
		// 确保国家存在于 countries 表
		d.ensure_country(country_iso, entity_name, iso3_code)
		// 插入或更新 indicators（使用 INSERT IGNORE 避免重复）
		q := 'INSERT INTO indicators (source, country_iso, indicator, label, year, value, unit) ' + "VALUES ('owid', '${sql_escape(country_iso)}', '${sql_escape(indicator_code)}', " + "'${sql_escape(label)}', ${year}, ${value}, '${sql_escape(unit)}') " + 'ON DUPLICATE KEY UPDATE value=VALUES(value), updated_at=CURRENT_TIMESTAMP'
		m.exec(q) or { continue }
		count++
	}
	return count
}

// ensure_country 确保国家存在于 countries 表（已存在则跳过，避免无谓写入）
fn (mut d Database) ensure_country(iso2 string, name string, iso3 string) {
	if iso2 == '' {
		return
	}
	m := d.handle()
	rows := m.exec("SELECT 1 FROM countries WHERE iso2 = '${sql_escape(iso2)}' LIMIT 1") or {
		[]mysql.Row{}
	}
	if rows.len > 0 {
		return
	}
	q := 'INSERT INTO countries (iso2, iso3, name, region, income) ' + "VALUES ('${sql_escape(iso2)}', '${sql_escape(iso3)}', '${sql_escape(name)}', '', '')"
	m.exec(q) or {}
}

// get_owid_indicators 获取 OWID 某主题下的指标数据（按国家、年份降序）
pub fn (d &Database) get_owid_indicators(topic_slug string, limit int) ![]models.Indicator {
	m := d.handle()
	// 根据主题筛选指标代码
	indicators := models.owid_indicators()
	mut ind_codes := []string{}
	for ind in indicators {
		if ind.topic_slug == topic_slug {
			ind_codes << ind.slug
		}
	}
	if ind_codes.len == 0 {
		return []models.Indicator{}
	}
	mut conditions := []string{}
	for code in ind_codes {
		conditions << "indicator = '${sql_escape(code)}'"
	}
	where := conditions.join(' OR ')
	q := 'SELECT id, source, country_iso, indicator, label, year, value, unit, updated_at ' + "FROM indicators WHERE source = 'owid' AND (${where}) " + 'ORDER BY year DESC, country_iso LIMIT ${limit}'
	rows := m.exec(q) or { return []models.Indicator{} }
	return parse_indicators(rows)
}

// get_owid_indicator_top 获取 OWID 某指标的 Top N（按最新年份、值降序）
pub fn (d &Database) get_owid_indicator_top(indicator string, limit int) ![]models.Indicator {
	m := d.handle()
	q := 'SELECT id, source, country_iso, indicator, label, year, value, unit, updated_at ' + "FROM indicators WHERE source = 'owid' AND indicator = '${sql_escape(indicator)}' " + 'AND year = (SELECT MAX(year) FROM indicators i2 WHERE i2.country_iso = indicators.country_iso ' + "AND i2.source = 'owid' AND i2.indicator = '${sql_escape(indicator)}') " + 'ORDER BY value DESC LIMIT ${limit}'
	rows := m.exec(q) or { return []models.Indicator{} }
	return parse_indicators(rows)
}

// get_owid_country_indicators 获取某国家的全部 OWID 指标
pub fn (d &Database) get_owid_country_indicators(iso2 string) ![]models.Indicator {
	m := d.handle()
	q := 'SELECT id, source, country_iso, indicator, label, year, value, unit, updated_at ' + "FROM indicators WHERE source = 'owid' AND country_iso = '${sql_escape(iso2)}' " + 'ORDER BY indicator, year DESC'
	rows := m.exec(q) or { return []models.Indicator{} }
	return parse_indicators(rows)
}

// count_owid_indicators 统计 OWID 指标数量
pub fn (d &Database) count_owid_indicators() !int {
	m := d.handle()
	rows := m.exec("SELECT COUNT(*) FROM indicators WHERE source = 'owid'") or { return 0 }
	if rows.len == 0 {
		return 0
	}
	return to_i(rows[0].vals[0])
}
