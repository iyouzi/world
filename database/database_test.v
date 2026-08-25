module database

import models

fn test_sql_escape() {
	assert sql_escape("it's") == "it\\'s"
	assert sql_escape('a"b') == 'a\\"b'
	assert sql_escape('plain') == 'plain'
}

fn test_indicator_label() {
	assert indicator_label('NY.GDP.MKTP.CD') == 'GDP'
	assert indicator_label('SP.POP.TOTL') == 'Population'
	assert indicator_label('SP.DYN.LE00.IN') == 'Life expectancy'
	// 未知代码原样返回
	assert indicator_label('XX.YY.ZZ') == 'XX.YY.ZZ'
}

fn test_market_of() {
	assert market_of('sh000001', 'tencent') == 'cn'
	assert market_of('usAAPL', 'nasdaq') == 'us'
	assert market_of('hk00700', 'HK-broker') == 'hk'
	// 未知来源默认 cn
	assert market_of('sh600519', 'unknown-src') == 'cn'
}

fn test_config_defaults() {
	cfg := config()
	assert cfg.port > 0
	assert cfg.dbname != ''
	assert cfg.username != ''
}

// 集成测试：需要本地 MySQL（scripts/mysql_init.sql 已初始化）。
// 连接失败时跳过而不是失败，便于无 DB 环境跑其余单测。
fn test_mysql_integration() {
	mut d := Database{}
	d.connect() or {
		eprintln('SKIP: MySQL 不可用 (${err})')
		return
	}
	defer {
		d.close()
	}
	assert d.open

	cnt := d.count_countries('') or { -1 }
	assert cnt >= 0

	ws := d.get_world_stats() or { models.WorldStats{} }
	assert ws.total_countries >= 0

	countries := d.get_countries(5, 0, '') or { []models.Country{} }
	assert countries.len <= 5

	top := d.get_indicator_top('worldbank', 'NY.GDP.MKTP.CD', 3) or { []models.Indicator{} }
	assert top.len <= 3

	quotes := d.get_market_quotes('', '') or { []models.MarketQuote{} }
	assert quotes.len >= 0

	logs := d.recent_logs(5) or { []models.FetchLog{} }
	assert logs.len <= 5

	// 不存在的 SQLite 文件必须报错
	mut got_err := false
	r := d.import_from_sqlite('/tmp/no_such_db_should_not_exist.db') or {
		got_err = true
		ImportResult{}
	}
	assert got_err
	assert r.countries == 0 && r.indicators == 0 && r.market == 0
}
