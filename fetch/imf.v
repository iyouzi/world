module fetch

import time
import database

// IMF 数据源：将 IMF 的 GDP / GDP per capita 估算写入 indicators 表（source='imf'）。
// 接口参考 IMF_shows attachment：
//   https://www.imf.org/external/datamapper/api/v1/NGDPD/CHN
// 其中 NGDPD = GDP 现价美元, NGDPDPC = 人均 GDP。
struct ImfDataset {
	label string
	unit  string
}

// imf_datasets 数据集代码 -> (标签, 单位)
// 均为 IMF Data Mapper (WEO) 公开数据集代码
fn imf_datasets() map[string]ImfDataset {
	mut m := map[string]ImfDataset{}
	m['NGDPD'] = ImfDataset{
		label: 'GDP (current US\$)'
		unit: 'USD'
	}
	m['NGDPDPC'] = ImfDataset{
		label: 'GDP per capita (current US\$)'
		unit: 'USD'
	}
	m['NGDP_RPCH'] = ImfDataset{
		label: 'Real GDP growth %'
		unit: '%'
	}
	m['GGXWDG_NGDP'] = ImfDataset{
		label: 'Gross debt % of GDP'
		unit: '%GDP'
	}
	m['PCPIPCH'] = ImfDataset{
		label: 'Inflation %'
		unit: '%'
	}
	m['LUR'] = ImfDataset{
		label: 'Unemployment %'
		unit: '%'
	}
	return m
}

// 常用国家 iso2（与 worldbank 对齐）
fn imf_countries() []string {
	return ['US', 'CN', 'JP', 'DE', 'GB', 'FR', 'IT', 'CA', 'KR', 'AU', 'BR', 'IN', 'RU', 'ES',
		'NL', 'CH', 'MX', 'ID', 'TR', 'SA']
}

// fetch_imf 从 IMF Data Mapper API 抓取 WEO 数据写入 MySQL。
// 全部请求失败时返回 error（网络断开等），由调用方记录失败日志。
pub fn fetch_imf(dbconn &database.Database, limit int) !int {
	m := dbconn.handle()
	datasets := imf_datasets()
	countries := imf_countries()
	mut total := 0
	mut req_fail := 0
	start := time.now()
	for ds_code, meta in datasets {
		label := meta.label
		unit := meta.unit
		for i, iso2 in countries {
			if limit > 0 && i >= limit {
				break
			}
			vals := fetch_imf_dataset(ds_code, iso2)
			if vals.len == 0 {
				req_fail++
				continue
			}
			for year_key, v in vals {
				if v > 0 {
					y_str := year_key.str()
					dbconn.exec_params('INSERT INTO indicators (source, country_iso, indicator, label, year, value, unit) VALUES (?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE value=VALUES(value), year=VALUES(year), updated_at=CURRENT_TIMESTAMP', 'imf', iso2, ds_code, label, '${y_str}', '${v}', unit) or {}
					total++
				}
			}
		}
	}
	dur := int(time.now().unix_milli() - start.unix_milli())
	if total == 0 && req_fail > 0 {
		dbconn.log_fetch('imf', 'failed', '${req_fail} 个请求全部失败（网络不可用？）', 0, dur)
		return error('imf: 所有 ${req_fail} 个请求均失败')
	}
	if req_fail > 0 {
		dbconn.log_fetch('imf', 'partial', '抓取 IMF ${total} 条记录（${req_fail} 个请求无数据）', total, dur)
	} else {
		dbconn.log_fetch('imf', 'success', '抓取 IMF ${total} 条记录', total, dur)
	}
	return total
}

// fetch_imf_dataset 拉取某个数据集下某个国家多年的数值（取最近若干年）；
// 网络错误 / 无数据返回空 map，由调用方计入失败。
// 新 IMF DataMapper API 格式: {"values":{"DATASET":{"ISO2":{"YEAR":value}}}}
fn fetch_imf_dataset(dataset string, iso2 string) map[int]f64 {
	mut result := map[int]f64{}
	url := 'https://www.imf.org/external/datamapper/api/v1/${dataset}/${iso2}'
	// IMF API 响应慢（~12s），需 30s 超时避免所有请求超时失败
	body := http_get_timeout(url, '', 30_000_000) or { return result }
	// 解析新格式: {"values":{"DATASET":{"COUNTRY":{"YEAR":value,...}}}}
	values_pos := body.index('"values"') or { return result }
	// 在 values 对象内找到数据集名称
	ds_key := '"' + dataset + '"'
	ds_start := body.index_after(ds_key, values_pos) or { return result }
	// 跳过数据集名称后的引号，找到对象起始大括号
	ds_brace := body.index_after('"', ds_start) or { return result }
	// 在数据集内找到国家 ISO2 代码
	iso2_key := '"' + iso2 + '"'
	iso2_pos := body.index_after(iso2_key, ds_brace) or { return result }
	// 跳过国家名称后的引号，找到数据对象起始大括号
	iso2_brace := body.index_after('"', iso2_pos) or { return result }
	// 从 iso2_brace + 1 开始解析 "YEAR":value 对
	mut i := iso2_brace + 1
	for i < body.len {
		// 跳过空白和分隔符
		for i < body.len && (body[i] == ` ` || body[i] == `,` || body[i] == `}` || body[i] == `\t` || body[i] == `\n` || body[i] == `\r`) {
			i++
		}
		if i >= body.len || body[i] == `}` {
			break
		}
		if body[i] != `"` {
			i++
			continue
		}
		// 读取年份（引号内）
		tq := body.index_after('"', i) or { break }
		year := body[i + 1..tq].int()
		i = tq + 1
		// 跳过空白和冒号
		for i < body.len && body[i] != `:` {
			i++
		}
		i++ // 跳过冒号
		// 读取数值
		mut vp := i
		for vp < body.len && body[vp] != `,` && body[vp] != `}` && body[vp] != `"` && body[vp] != ` ` {
			vp++
		}
		vstr := body[i..vp].trim(' \t\n\r')
		if vstr != '' && vstr != 'null' {
			v := vstr.f64()
			if v > 0 {
				result[year] = v
			}
		}
		i = vp
	}
	return result
}
