module fetch

fn test_esc() {
	assert esc("a'b") == "a\\'b"
	assert esc('plain') == 'plain'
}

// GBK 处理函数对 ASCII 输入必须原样透传（行情数值字段依赖此行为）
fn test_gbk_to_utf8_ascii_passthrough() {
	src := 'v_sh600519="1~600519~47.00~46.50";'
	assert gbk_to_utf8(src.bytes()) == src
}

fn test_json_field() {
	data := '{"name":"贵州茅台","price":1700.5,"volume":12345}'
	assert json_field(data, 'name') == '贵州茅台'
	assert json_field(data, 'price') == '1700.5'
	assert json_field(data, 'volume') == '12345'
	// 缺失键返回空串
	assert json_field(data, 'missing') == ''
}

// 世界银行 JSON 解析：跳过 null，取第一个非空值及其年份
fn test_parse_wb_picks_first_non_null() {
	body := '[{"date":"2023","value":null},{"date":"2022","value":2546000.5}]'
	val, yr := parse_wb(body)
	assert yr == 2022
	assert val == 2546000.5
}

fn test_parse_wb_empty_body() {
	val, yr := parse_wb('[]')
	assert yr == 0
	assert val == 0.0
}

fn test_iso3_to_iso2() {
	assert iso3_to_iso2('USA') == 'US'
	assert iso3_to_iso2('CHN') == 'CN'
	// 映射表外的代码截取前两位
	assert iso3_to_iso2('ZZZ') == 'ZZ'
}

// er-api 响应解析：截取 rates 对象并读取币种数值
fn test_json_rates_section_and_rate() {
	body := '{"result":"success","rates":{"USD":1,"CNY":7.24,"EUR":0.92}}'
	rates := json_rates_section(body)
	assert rates.contains('"CNY":7.24')
	assert json_rate(rates, 'CNY') == 7.24
	// 缺失 / 非正数返回 0
	assert json_rate(rates, 'GBP') == 0.0
	assert json_rates_section('{"nope":1}') == ''
}

// 新浪外盘期货响应解析：0=现价 7=昨结 8=开盘 9=持仓
fn test_fetch_sina_futures_fields() {
	def := CommodityDef{
		symbol: 'hf_GC'
		name: '黄金 (COMEX)'
	}
	body := 'var hq_str_hf_GC="4696.221,,4699.400,4699.900,4755.000,4670.500,14:01:25,4697.800,4710.100,12345,,2,2026-08-25,黄金,0";'
	q := parse_sina_futures_body(def, body)
	assert q.symbol == 'GC'
	assert q.price == 4696.221
	assert q.prev_close == 4697.8
	assert q.change < 0
	assert q.volume == 12345
	// 价格非法时返回空 quote（symbol == ''）
	bad := parse_sina_futures_body(def, 'var hq_str_hf_GC="0,,,,,,,0,,,,,,,";')
	assert bad.symbol == ''
}

// http_get 对非法 URL 必须报错而不是 panic（离线环境依赖此快速失败）
fn test_http_get_bad_url_errors() {
	mut got_err := false
	http_get('http://127.0.0.1:1/nope', '') or {
		got_err = true
		return
	}
	assert got_err
}
