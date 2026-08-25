module fetch

import database
import encoding.iconv
import models
import time

// 市场行情抓取：整合 world_market_shows 中的多源 API（腾讯 / 新浪 / 网易），
// 另加外汇汇率（open.er-api.com）与大宗商品（stooq.com）。
// 抓取结果统一写入 market_quotes 表；market 字段区分 cn/us/hk/index/fx/commodity。

// 默认关注标的（可在页面 / 配置中扩展）
fn default_symbols() []models.MarketSymbol {
	return [
		// A股
		models.MarketSymbol{
			symbol: 'sh000001'
			name:   '上证指数'
			market: 'index'
		},
		models.MarketSymbol{
			symbol: 'sz399001'
			name:   '深证成指'
			market: 'index'
		},
		models.MarketSymbol{
			symbol: 'sh600519'
			name:   '贵州茅台'
			market: 'cn'
		},
		models.MarketSymbol{
			symbol: 'sz000001'
			name:   '平安银行'
			market: 'cn'
		},
		models.MarketSymbol{
			symbol: 'sh601318'
			name:   '中国平安'
			market: 'cn'
		},
		// 港股
		models.MarketSymbol{
			symbol: 'hk00700'
			name:   '腾讯控股'
			market: 'hk'
		},
		models.MarketSymbol{
			symbol: 'hk09988'
			name:   '阿里巴巴'
			market: 'hk'
		},
		// 美股
		models.MarketSymbol{
			symbol: 'usAAPL'
			name:   'Apple'
			market: 'us'
		},
		models.MarketSymbol{
			symbol: 'usMSFT'
			name:   'Microsoft'
			market: 'us'
		},
		models.MarketSymbol{
			symbol: 'usNVDA'
			name:   'NVIDIA'
			market: 'us'
		},
	]
}

// upsert_quote 写入/更新一条行情。注意表列名是 chg / chg_pct（change 是 MySQL 保留字）。
fn upsert_quote(dbconn &database.Database, q models.MarketQuote) bool {
	mut m := dbconn.handle()
	m.exec("INSERT INTO market_quotes (symbol, name, market, price, prev_close, chg, chg_pct, volume, source) VALUES ('${esc(q.symbol)}', '${esc(q.name)}', '${esc(q.market)}', ${q.price}, ${q.prev_close}, ${q.change}, ${q.change_pct}, ${q.volume}, '${esc(q.source)}') ON DUPLICATE KEY UPDATE name=VALUES(name), market=VALUES(market), price=VALUES(price), prev_close=VALUES(prev_close), chg=VALUES(chg), chg_pct=VALUES(chg_pct), volume=VALUES(volume), source=VALUES(source), updated_at=CURRENT_TIMESTAMP") or {
		database.log_line('market', '写入行情失败 ${q.symbol}: ${err}')
		return false
	}
	return true
}

pub fn fetch_market(dbconn &database.Database) !int {
	symbols := default_symbols()
	mut n := 0
	start := time.now()
	for s in symbols {
		q := fetch_one(s)
		if q.symbol == '' {
			continue
		}
		if upsert_quote(dbconn, q) {
			n++
		}
	}
	dur := int(time.now().unix_milli() - start.unix_milli())
	if n == 0 {
		dbconn.log_fetch('market', 'failed',
			'全部 ${symbols.len} 个标的抓取失败（网络不可用？）', 0, dur)
		return error('market: 所有标的均抓取失败')
	}
	if n < symbols.len {
		dbconn.log_fetch('market', 'partial', '更新 ${n}/${symbols.len} 个行情标的', n, dur)
	} else {
		dbconn.log_fetch('market', 'success', '更新 ${n} 个行情标的', n, dur)
	}
	return n
}

// ============ 外汇汇率 ============
// 数据源 open.er-api.com（免 key）：https://open.er-api.com/v6/latest/USD
// 返回 1 USD 兑各币种汇率。xxxUSD 形式的货币对取倒数换算。

fn fx_pairs() []models.MarketSymbol {
	return [
		models.MarketSymbol{
			symbol: 'USDCNY'
			name:   '美元/人民币'
			market: 'fx'
		},
		models.MarketSymbol{
			symbol: 'USDJPY'
			name:   '美元/日元'
			market: 'fx'
		},
		models.MarketSymbol{
			symbol: 'USDHKD'
			name:   '美元/港元'
			market: 'fx'
		},
		models.MarketSymbol{
			symbol: 'USDKRW'
			name:   '美元/韩元'
			market: 'fx'
		},
		models.MarketSymbol{
			symbol: 'USDINR'
			name:   '美元/卢比'
			market: 'fx'
		},
		models.MarketSymbol{
			symbol: 'USDBRL'
			name:   '美元/雷亚尔'
			market: 'fx'
		},
		models.MarketSymbol{
			symbol: 'USDMXN'
			name:   '美元/比索'
			market: 'fx'
		},
		models.MarketSymbol{
			symbol: 'USDSGD'
			name:   '美元/新加坡元'
			market: 'fx'
		},
		models.MarketSymbol{
			symbol: 'EURUSD'
			name:   '欧元/美元'
			market: 'fx'
		},
		models.MarketSymbol{
			symbol: 'GBPUSD'
			name:   '英镑/美元'
			market: 'fx'
		},
		models.MarketSymbol{
			symbol: 'AUDUSD'
			name:   '澳元/美元'
			market: 'fx'
		},
	]
}

pub fn fetch_fx(dbconn &database.Database) !int {
	start := time.now()
	body := http_get('https://open.er-api.com/v6/latest/USD', '') or {
		dbconn.log_fetch('fx', 'failed', '汇率源请求失败: ${err}', 0, 0)
		return error('fx: ${err}')
	}
	rates := json_rates_section(body)
	if rates == '' {
		dbconn.log_fetch('fx', 'failed', '汇率响应中未找到 rates 对象', 0,
			int(time.now().unix_milli() - start.unix_milli()))
		return error('fx: 响应缺少 rates')
	}
	mut n := 0
	for p in fx_pairs() {
		base := p.symbol[0..3]
		quote := p.symbol[3..6]
		// USDxxx：直接取 1 USD 兑该币的汇率；xxxUSD（如 EURUSD）：用 1/rate(base) 换算
		price := if base == 'USD' { json_rate(rates, quote) } else { 1.0 / json_rate(rates, base) }
		if price <= 0 {
			continue
		}
		ok := upsert_quote(dbconn, models.MarketQuote{
			symbol:     p.symbol
			name:       p.name
			market:     'fx'
			price:      price
			prev_close: price
			change:     0.0
			change_pct: 0.0
			volume:     0
			source:     'er-api'
		})
		if ok {
			n++
		}
	}
	dur := int(time.now().unix_milli() - start.unix_milli())
	if n == 0 {
		dbconn.log_fetch('fx', 'failed', '未解析到任何货币对', 0, dur)
		return error('fx: 未解析到任何货币对')
	}
	dbconn.log_fetch('fx', 'success', '更新 ${n} 个货币对汇率', n, dur)
	return n
}

// json_rates_section 从 er-api 响应中截取 "rates":{...} 对象（含花括号配对）
fn json_rates_section(body string) string {
	key := body.index('"rates"') or { return '' }
	st := body.index_after('{', key) or { return '' }
	mut depth := 0
	for i := st; i < body.len; i++ {
		if body[i] == `{` {
			depth++
		} else if body[i] == `}` {
			depth--
			if depth == 0 {
				return body[st..i + 1]
			}
		}
	}
	return ''
}

// json_rate 在 rates 对象中读取某币种的数值（如 "CNY":7.24）
fn json_rate(rates string, code string) f64 {
	search := '"${code}":'
	st := rates.index(search) or { return 0.0 }
	vp := st + search.len
	mut e := vp
	for e < rates.len && rates[e] != `,` && rates[e] != `}` {
		e++
	}
	v := rates[vp..e].trim(' \t\n\r').f64()
	return if v > 0 { v } else { 0.0 }
}

// ============ 大宗商品期货 ============
// 数据源新浪外盘期货（免 key，GBK 编码，需 Referer）：
// https://hq.sinajs.cn/list=hf_GC
// 字段：0=现价 4=最高 5=最低 6=时间 7=昨结算 8=开盘 9=持仓量 13=名称

struct CommodityDef {
	symbol string // 新浪代码，如 hf_GC
	name   string
}

fn commodity_defs() []CommodityDef {
	return [
		CommodityDef{
			symbol: 'hf_GC'
			name:   '黄金 (COMEX)'
		},
		CommodityDef{
			symbol: 'hf_SI'
			name:   '白银 (COMEX)'
		},
		CommodityDef{
			symbol: 'hf_CL'
			name:   'WTI 原油 (NYMEX)'
		},
		CommodityDef{
			symbol: 'hf_OIL'
			name:   '布伦特原油 (IPE)'
		},
		CommodityDef{
			symbol: 'hf_NG'
			name:   '天然气 (NYMEX)'
		},
		CommodityDef{
			symbol: 'hf_CAD'
			name:   '铜 (LME)'
		},
		CommodityDef{
			symbol: 'hf_PL'
			name:   '铂金 (NYMEX)'
		},
		CommodityDef{
			symbol: 'hf_PA'
			name:   '钯金 (NYMEX)'
		},
	]
}

pub fn fetch_commodity(dbconn &database.Database) !int {
	defs := commodity_defs()
	start := time.now()
	mut n := 0
	for def in defs {
		q := fetch_sina_futures(def)
		if q.symbol == '' {
			continue
		}
		if upsert_quote(dbconn, q) {
			n++
		}
	}
	dur := int(time.now().unix_milli() - start.unix_milli())
	if n == 0 {
		dbconn.log_fetch('commodity', 'failed', '全部 ${defs.len} 个商品品种抓取失败',
			0, dur)
		return error('commodity: 所有品种均抓取失败')
	}
	if n < defs.len {
		dbconn.log_fetch('commodity', 'partial', '更新 ${n}/${defs.len} 个商品品种', n, dur)
	} else {
		dbconn.log_fetch('commodity', 'success', '更新 ${n} 个商品品种', n, dur)
	}
	return n
}

// fetch_sina_futures 抓取单个新浪外盘期货合约；失败返回空 quote（symbol == ''）
fn fetch_sina_futures(def CommodityDef) models.MarketQuote {
	url := 'https://hq.sinajs.cn/list=${def.symbol}'
	body := gbk_to_utf8(http_get(url, 'https://finance.sina.com.cn') or {
		return models.MarketQuote{}
	}.bytes())
	return parse_sina_futures_body(def, body)
}

// parse_sina_futures_body 解析新浪外盘响应体；价格非法返回空 quote
fn parse_sina_futures_body(def CommodityDef, body string) models.MarketQuote {
	eq := body.index('="') or { return models.MarketQuote{} }
	en := body.last_index('";') or { return models.MarketQuote{} }
	if eq + 2 >= en {
		return models.MarketQuote{}
	}
	fields := body[eq + 2..en].split(',')
	if fields.len < 10 {
		return models.MarketQuote{}
	}
	price := fields[0].f64()
	prev_close := fields[7].f64()
	if price <= 0 || prev_close <= 0 {
		return models.MarketQuote{}
	}
	chg := price - prev_close
	vol := fields[9].i64()
	return models.MarketQuote{
		symbol:     def.symbol[3..].to_upper()
		name:       def.name
		market:     'commodity'
		price:      price
		prev_close: prev_close
		change:     chg
		change_pct: if prev_close != 0 { chg / prev_close * 100.0 } else { 0.0 }
		volume:     vol
		source:     'sina-futures'
	}
}

// fetch_one 依次尝试腾讯 / 新浪 / 网易，返回首个成功的行情
fn fetch_one(s models.MarketSymbol) models.MarketQuote {
	if q := fetch_tencent(s) {
		return q
	}
	if q := fetch_sina(s) {
		return q
	}
	if q := fetch_netease(s) {
		return q
	}
	return models.MarketQuote{}
}

// 腾讯接口：qt.gtimg.cn/q=sh600519  （GBK 编码）
fn fetch_tencent(s models.MarketSymbol) ?models.MarketQuote {
	raw := s.symbol.replace('hk', 'hk').replace('us', 'us').replace('sh', 'sh').replace('sz', 'sz')
	url := 'https://qt.gtimg.cn/q=${raw}'
	body := gbk_to_utf8(http_get(url, '') or { return none }.bytes())
	// 格式：v_sh600519="1~贵州茅台~600519~...~price~prevclose~...~volume~..."
	eq := body.index('="') or { return none }
	en := body.last_index('";') or { return none }
	if eq + 2 >= en {
		return none
	}
	fields := body[eq + 2..en].split('~')
	if fields.len < 32 {
		return none
	}
	price := fields[3].f64()
	prev_close := fields[4].f64()
	if price <= 0 || prev_close <= 0 {
		return none
	}
	// 成交量（手）在 fields[6]
	volume := fields[6].i64()
	change := price - prev_close
	change_pct := if prev_close != 0 { (change / prev_close) * 100 } else { 0.0 }
	return models.MarketQuote{
		symbol:     s.symbol
		name:       fields[1]
		market:     s.market
		price:      price
		prev_close: prev_close
		change:     change
		change_pct: change_pct
		volume:     volume
		source:     'tencent'
	}
}

// 新浪接口：hq.sinajs.cn/list=sh600519 （GBK 编码，必须带 Referer）
fn fetch_sina(s models.MarketSymbol) ?models.MarketQuote {
	url := 'https://hq.sinajs.cn/list=${s.symbol}'
	body := gbk_to_utf8(http_get(url, 'https://finance.sina.com.cn') or { return none }.bytes())
	eq := body.index('="') or { return none }
	en := body.last_index('";') or { return none }
	if eq + 2 >= en {
		return none
	}
	fields := body[eq + 2..en].split(',')
	if fields.len < 32 {
		return none
	}
	price := fields[3].f64()
	prev_close := fields[2].f64()
	if price <= 0 || prev_close <= 0 {
		return none
	}
	volume := fields[8].i64()
	change := price - prev_close
	change_pct := if prev_close != 0 { (change / prev_close) * 100 } else { 0.0 }
	return models.MarketQuote{
		symbol:     s.symbol
		name:       fields[0]
		market:     s.market
		price:      price
		prev_close: prev_close
		change:     change
		change_pct: change_pct
		volume:     volume
		source:     'sina'
	}
}

// 网易接口：api.money.126.net/data/feed/0600519,money.api
fn fetch_netease(s models.MarketSymbol) ?models.MarketQuote {
	code := s.symbol.replace('sh', '0').replace('sz', '1').replace('hk', '').replace('us', '')
	url := 'https://api.money.126.net/data/feed/${code},money.api'
	body := http_get(url, 'https://money.163.com') or { return none }
	st := body.index('{') or { return none }
	en := body.last_index('}') or { return none }
	if st >= en {
		return none
	}
	data := body[st..en + 1]
	price := json_field(data, 'price').f64()
	yest := json_field(data, 'yestclose').f64()
	if price <= 0 || yest <= 0 {
		return none
	}
	volume := json_field(data, 'volume').i64()
	change := price - yest
	change_pct := if yest != 0 { (change / yest) * 100 } else { 0.0 }
	return models.MarketQuote{
		symbol:     s.symbol
		name:       json_field(data, 'name')
		market:     s.market
		price:      price
		prev_close: yest
		change:     change
		change_pct: change_pct
		volume:     volume
		source:     'netease'
	}
}

fn json_field(data string, key string) string {
	search := '"${key}":'
	st := data.index(search) or { return '' }
	vp := st + search.len
	// 跳过空白
	mut i := vp
	for i < data.len && (data[i] == ` ` || data[i] == `\t`) {
		i++
	}
	if i < data.len && data[i] == `"` {
		// 字符串值
		j := data.index_after('"', i + 1) or { return '' }
		return data[i + 1..j]
	}
	// 数值
	mut e := i
	for e < data.len && data[e] != `,` && data[e] != `}` {
		e++
	}
	return data[i..e].trim(' \t\n\r')
}

fn gbk_to_utf8(bytes []u8) string {
	// 注意：必须用普通 import encoding.iconv，不要用编译期 $if encoding.iconv ?
	// 探测写法——v fmt 会自动补 import 导致编译失败（历史踩坑）。
	return iconv.encoding_to_vstring(bytes, 'gbk') or { bytes.bytestr() }
}
