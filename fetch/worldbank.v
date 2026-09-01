module fetch

import time
import database
import models

// 世界银行指标定义（整合自 worldbank_info attachment）
struct WBIndicator {
	code  string
	label string
	unit  string
}

fn wb_indicators() []WBIndicator {
	return [
		WBIndicator{
			code: 'SP.POP.TOTL'
			label: 'Population'
			unit: 'people'
		},
		WBIndicator{
			code: 'NY.GDP.MKTP.CD'
			label: 'GDP'
			unit: 'USD'
		},
		WBIndicator{
			code: 'NY.GDP.PCAP.KD'
			label: 'GDP per capita'
			unit: 'USD'
		},
		WBIndicator{
			code: 'NY.GDP.MKTP.KD.ZG'
			label: 'GDP growth %'
			unit: '%'
		},
		WBIndicator{
			code: 'SP.DYN.LE00.IN'
			label: 'Life expectancy'
			unit: 'years'
		},
		WBIndicator{
			code: 'SE.XPD.TOTL.GD.ZS'
			label: 'Education spending %'
			unit: '%GDP'
		},
		WBIndicator{
			code: 'SH.XPD.CHEX.GD.ZS'
			label: 'Health spending %'
			unit: '%GDP'
		},
		WBIndicator{
			code: 'SL.UEM.TOTL.NE.ZS'
			label: 'Unemployment %'
			unit: '%'
		},
		WBIndicator{
			code: 'FP.CPI.TOTL.ZG'
			label: 'Inflation %'
			unit: '%'
		},
		WBIndicator{
			code: 'GC.DOD.TOTL.GD.ZS'
			label: 'Gov debt %'
			unit: '%GDP'
		},
		WBIndicator{
			code: 'GC.XPN.TOTL.GD.ZS'
			label: 'Gov spending %'
			unit: '%GDP'
		},
		WBIndicator{
			code: 'NY.GNS.ICTR.ZS'
			label: 'Gross savings %'
			unit: '%GDP'
		},
		WBIndicator{
			code: 'NE.EXP.GNFS.ZS'
			label: 'Exports %'
			unit: '%GDP'
		},
		WBIndicator{
			code: 'NE.IMP.GNFS.ZS'
			label: 'Imports %'
			unit: '%GDP'
		},
		WBIndicator{
			code: 'SP.POP.GROW'
			label: 'Population growth %'
			unit: '%'
		},
		WBIndicator{
			code: 'IT.NET.USER.ZS'
			label: 'Internet users %'
			unit: '%'
		},
		WBIndicator{
			code: 'EG.USE.PCAP.KG.OE'
			label: 'Energy use'
			unit: 'kg'
		},
		WBIndicator{
			code: 'EG.FEC.RNEW.ZS'
			label: 'Renewable energy %'
			unit: '%'
		},
		WBIndicator{
			code: 'EN.ATM.CO2E.KT'
			label: 'CO2 emissions'
			unit: 'kt'
		},
		WBIndicator{
			code: 'AG.LND.TOTL.K2'
			label: 'Land area'
			unit: 'sq km'
		},
		WBIndicator{
			code: 'NY.GDP.MKTP.PP.CD'
			label: 'GDP PPP'
			unit: 'int-\$'
		},
		WBIndicator{
			code: 'NY.GDP.PCAP.PP.CD'
			label: 'GDP per capita PPP'
			unit: 'int-\$'
		},
	]
}

// 常用国家（iso3）与中文名，便于展示
fn country_names() map[string]string {
	mut m := map[string]string{}
	// 主要经济体
	m['USA'] = '美国'
	m['CHN'] = '中国'
	m['JPN'] = '日本'
	m['DEU'] = '德国'
	m['GBR'] = '英国'
	m['FRA'] = '法国'
	m['ITA'] = '意大利'
	m['CAN'] = '加拿大'
	m['KOR'] = '韩国'
	m['AUS'] = '澳大利亚'
	m['BRA'] = '巴西'
	m['IND'] = '印度'
	m['RUS'] = '俄罗斯'
	m['ESP'] = '西班牙'
	m['NLD'] = '荷兰'
	m['SWE'] = '瑞典'
	m['NOR'] = '挪威'
	m['DNK'] = '丹麦'
	m['FIN'] = '芬兰'
	m['CHE'] = '瑞士'
	m['BEL'] = '比利时'
	m['AUT'] = '奥地利'
	m['POL'] = '波兰'
	m['CZE'] = '捷克'
	m['GRC'] = '希腊'
	m['PRT'] = '葡萄牙'
	m['IRL'] = '爱尔兰'
	m['SGP'] = '新加坡'
	m['NZL'] = '新西兰'
	m['ZAF'] = '南非'
	m['MEX'] = '墨西哥'
	m['IDN'] = '印度尼西亚'
	m['TUR'] = '土耳其'
	m['SAU'] = '沙特阿拉伯'
	m['ARE'] = '阿联酋'
	// 东南亚
	m['THA'] = '泰国'
	m['MYS'] = '马来西亚'
	m['PHL'] = '菲律宾'
	m['VNM'] = '越南'
	// 中东
	m['ISR'] = '以色列'
	m['IRN'] = '伊朗'
	m['QAT'] = '卡塔尔'
	// 拉美
	m['ARG'] = '阿根廷'
	m['CHL'] = '智利'
	m['COL'] = '哥伦比亚'
	m['PER'] = '秘鲁'
	m['VEN'] = '委内瑞拉'
	m['ECU'] = '厄瓜多尔'
	// 非洲
	m['NGA'] = '尼日利亚'
	m['EGY'] = '埃及'
	m['KEN'] = '肯尼亚'
	m['MAR'] = '摩洛哥'
	m['GHA'] = '加纳'
	m['TZA'] = '坦桑尼亚'
	m['ETH'] = '埃塞俄比亚'
	m['CIV'] = '科特迪瓦'
	// 南亚
	m['PAK'] = '巴基斯坦'
	m['BGD'] = '孟加拉国'
	m['LKA'] = '斯里兰卡'
	// 中亚
	m['KAZ'] = '哈萨克斯坦'
	// 欧洲其他
	m['HUN'] = '匈牙利'
	m['ROU'] = '罗马尼亚'
	m['SVK'] = '斯洛伐克'
	m['SVN'] = '斯洛文尼亚'
	m['HRV'] = '克罗地亚'
	m['BGR'] = '保加利亚'
	m['SRB'] = '塞尔维亚'
	// 大洋洲
	m['PNG'] = '巴布亚新几内亚'
	// 北美其他
	m['GTM'] = '危地马拉'
	m['CUB'] = '古巴'
	m['DOM'] = '多米尼加'
	// 中东非
	m['TUN'] = '突尼斯'
	return m
}

fn iso3_to_iso2(iso3 string) string {
	m := {
		'USA': 'US'
		'CHN': 'CN'
		'JPN': 'JP'
		'DEU': 'DE'
		'GBR': 'GB'
		'FRA': 'FR'
		'ITA': 'IT'
		'CAN': 'CA'
		'KOR': 'KR'
		'AUS': 'AU'
		'BRA': 'BR'
		'IND': 'IN'
		'RUS': 'RU'
		'ESP': 'ES'
		'NLD': 'NL'
		'SWE': 'SE'
		'NOR': 'NO'
		'DNK': 'DK'
		'FIN': 'FI'
		'CHE': 'CH'
		'BEL': 'BE'
		'AUT': 'AT'
		'POL': 'PL'
		'CZE': 'CZ'
		'GRC': 'GR'
		'PRT': 'PT'
		'IRL': 'IE'
		'SGP': 'SG'
		'NZL': 'NZ'
		'ZAF': 'ZA'
		'MEX': 'MX'
		'IDN': 'ID'
		'TUR': 'TR'
		'SAU': 'SA'
		'ARE': 'AE'
		// 东南亚
		'THA': 'TH'
		'MYS': 'MY'
		'PHL': 'PH'
		'VNM': 'VN'
		// 中东
		'ISR': 'IL'
		'IRN': 'IR'
		'QAT': 'QA'
		// 拉美
		'ARG': 'AR'
		'CHL': 'CL'
		'COL': 'CO'
		'PER': 'PE'
		'VEN': 'VE'
		'ECU': 'EC'
		// 非洲
		'NGA': 'NG'
		'EGY': 'EG'
		'KEN': 'KE'
		'MAR': 'MA'
		'GHA': 'GH'
		'TZA': 'TZ'
		'ETH': 'ET'
		'CIV': 'CI'
		'TUN': 'TN'
		// 南亚
		'PAK': 'PK'
		'BGD': 'BD'
		'LKA': 'LK'
		// 中亚
		'KAZ': 'KZ'
		// 欧洲其他
		'HUN': 'HU'
		'ROU': 'RO'
		'SVK': 'SK'
		'SVN': 'SI'
		'HRV': 'HR'
		'BGR': 'BG'
		'SRB': 'RS'
		// 大洋洲
		'PNG': 'PG'
		// 北美其他
		'GTM': 'GT'
		'CUB': 'CU'
		'DOM': 'DO'
	}
	return m[iso3] or { models.iso3_to_iso2(iso3) }
}

// fetch_worldbank 抓取世界银行数据并写入 MySQL。
// limit 控制最大国家数（便于演示；0 = 全部常见国家）。
// 全部请求失败时返回 error（网络断开等），由调用方记录失败日志。
pub fn fetch_worldbank(dbconn &database.Database, limit int) !int {
	m := dbconn.handle()
	names := country_names()
	inds := wb_indicators()
	mut count := 0
	mut inserted := 0
	mut req_fail := 0
	start := time.now()
	for iso3, _ in names {
		if limit > 0 && count >= limit {
			break
		}
		cn := names[iso3]
		i2 := iso3_to_iso2(iso3)
		dbconn.exec_params("INSERT IGNORE INTO countries (iso2, iso3, name, region) VALUES (?,?,?,?)", i2, iso3, cn, 'global') or {}

		for ind in inds {
			v := fetch_wb_value(iso3, ind.code)
			if v.ok {
				_, _ = dbconn.exec_params("INSERT INTO indicators (source, country_iso, indicator, label, year, value, unit) VALUES (?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE value=VALUES(value), year=VALUES(year), updated_at=CURRENT_TIMESTAMP", 'worldbank', i2, ind.code, ind.label, '${v.year}', '${v.value}', ind.unit)
				inserted++
			} else {
				req_fail++
			}
		}
		count++
	}
	dur := int(time.now().unix_milli() - start.unix_milli())
	if inserted == 0 && req_fail > 0 {
		dbconn.log_fetch('worldbank', 'failed', '${req_fail} 个请求全部失败（网络不可用？），共尝试 ${count} 国 × ${inds.len} 指标', 0, dur)
		return error('worldbank: 所有 ${req_fail} 个请求均失败')
	}
	msg := '抓取 ${count} 个国家 × ${inds.len} 指标: 成功 ${inserted} 条'
	if inserted == 0 {
		dbconn.log_fetch('worldbank', 'success', msg + '（数据源无更新）', inserted, dur)
	} else if req_fail > 0 {
		dbconn.log_fetch('worldbank', 'partial', '${msg}, 失败 ${req_fail} 个请求', inserted, dur)
	} else {
		dbconn.log_fetch('worldbank', 'success', msg, inserted, dur)
	}
	return count
}

// wb_result 表示单次指标抓取结果（ok=false 表示该值未取到）
struct WBValue {
	ok    bool
	value f64
	year  int
}

// fetch_wb_value 抓取某指标最新可用年份的值；网络/HTTP 错误计入 ok=false 而不是静默吞掉
fn fetch_wb_value(iso3 string, indicator string) WBValue {
	url := 'https://api.worldbank.org/v2/country/${iso3}/indicator/${indicator}?format=json&per_page=100&mrnev=1'
	body := http_get(url, '') or { return WBValue{} }
	val, yr := parse_wb(body)
	return WBValue{
		ok: val > 0
		value: val
		year: yr
	}
}

// fetch_wld 抓取 WorldBank WLD（世界汇总）国家的全部可用指标最新值并写入 indicators 表。
// 返回成功抓取的指标数（不含无数据的指标）。
pub fn fetch_wld(dbconn &database.Database) !int {
	m := dbconn.handle()
	mut wld_inds := []WBIndicator{}
	wld_inds << WBIndicator{
		code: 'NY.GDP.MKTP.CD'
		label: 'GDP'
		unit: 'USD'
	}
	wld_inds << WBIndicator{
		code: 'SP.POP.TOTL'
		label: 'Population'
		unit: 'people'
	}
	wld_inds << WBIndicator{
		code: 'SP.DYN.LE00.IN'
		label: 'Life expectancy'
		unit: 'years'
	}
	wld_inds << WBIndicator{
		code: 'NY.GDP.PCAP.KD'
		label: 'GDP per capita'
		unit: 'USD'
	}
	wld_inds << WBIndicator{
		code: 'FP.CPI.TOTL.ZG'
		label: 'Inflation %'
		unit: '%'
	}
	wld_inds << WBIndicator{
		code: 'SL.UEM.TOTL.NE.ZS'
		label: 'Unemployment %'
		unit: '%'
	}
	wld_inds << WBIndicator{
		code: 'IT.NET.USER.ZS'
		label: 'Internet users %'
		unit: '%'
	}
	wld_inds << WBIndicator{
		code: 'SE.XPD.TOTL.GD.ZS'
		label: 'Education spending %'
		unit: '%GDP'
	}
	wld_inds << WBIndicator{
		code: 'SH.XPD.CHEX.GD.ZS'
		label: 'Health spending %'
		unit: '%GDP'
	}
	wld_inds << WBIndicator{
		code: 'EG.USE.PCAP.KG.OE'
		label: 'Energy use'
		unit: 'kg'
	}
	mut inserted := 0
	for ind in wld_inds {
		v := fetch_wb_value('WLD', ind.code)
		if v.ok {
			_, _ = dbconn.exec_params("INSERT INTO indicators (source, country_iso, indicator, label, year, value, unit) VALUES (?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE value=VALUES(value), year=VALUES(year), updated_at=CURRENT_TIMESTAMP", 'worldbank', 'WLD', ind.code, ind.label, '${v.year}', '${v.value}', ind.unit) or {}
			inserted++
		}
	}
	return inserted
}

// 解析世界银行返回 JSON：找第一个非 null 的 value 并取其 year
fn parse_wb(body string) (f64, int) {
	// 寻找所有 "date":"YYYY" 与紧随的 "value":X 配对，取第一个非 null
	mut i := 0
	for i < body.len {
		di := body.index_after('"date":', i) or { -1 }
		if di == -1 {
			break
		}
		// 读取年份（index_after 的起点是包含的，须 +1 跳过起始引号）
		ys := di + 7
		ye := body.index_after('"', ys + 1) or { -1 }
		if ye == -1 {
			break
		}
		year := body[ys + 1..ye].int()
		// 在之后的较短范围里找 value
		vi := body.index_after('"value":', ye) or { -1 }
		if vi == -1 {
			break
		}
		vs := vi + 8
		mut ve := body.index_after(',', vs) or { -1 }
		if ve == -1 {
			ve = body.len
		}
		vstr := body[vs..ve].trim(' \t\n\r').replace('}', '').trim(' \t\n\r')
		if vstr != 'null' && vstr != '' {
			v := vstr.f64()
			if v > 0 {
				return v, year
			}
		}
		i = ye + 1
	}
	return 0.0, 0
}
