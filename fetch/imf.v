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
		label: 'GDP (current US$)'
		unit:  'USD'
	}
	m['NGDPDPC'] = ImfDataset{
		label: 'GDP per capita (current US$)'
		unit:  'USD'
	}
	m['NGDP_RPCH'] = ImfDataset{
		label: 'Real GDP growth %'
		unit:  '%'
	}
	m['GGXWDG_NGDP'] = ImfDataset{
		label: 'Gross debt % of GDP'
		unit:  '%GDP'
	}
	m['PCPIPCH'] = ImfDataset{
		label: 'Inflation %'
		unit:  '%'
	}
	m['LUR'] = ImfDataset{
		label: 'Unemployment %'
		unit:  '%'
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
					m.exec("INSERT INTO indicators (source, country_iso, indicator, label, year, value, unit) VALUES ('imf', '${esc(iso2)}', '${esc(ds_code)}', '${esc(label)}', ${y_str}, ${v}, '${esc(unit)}') ON DUPLICATE KEY UPDATE value=VALUES(value), year=VALUES(year), updated_at=CURRENT_TIMESTAMP") or {}
					total++
				}
			}
		}
	}
	dur := int(time.now().unix_milli() - start.unix_milli())
	if total == 0 && req_fail > 0 {
		dbconn.log_fetch('imf', 'failed',
			'${req_fail} 个请求全部失败（网络不可用？）', 0, dur)
		return error('imf: 所有 ${req_fail} 个请求均失败')
	}
	if req_fail > 0 {
		dbconn.log_fetch('imf', 'partial',
			'抓取 IMF ${total} 条记录（${req_fail} 个请求无数据）', total, dur)
	} else {
		dbconn.log_fetch('imf', 'success', '抓取 IMF ${total} 条记录', total, dur)
	}
	return total
}

// fetch_imf_dataset 拉取某个数据集下某个国家多年的数值（取最近若干年）；
// 网络错误 / 无数据返回空 map，由调用方计入失败
fn fetch_imf_dataset(dataset string, iso2 string) map[int]f64 {
	mut result := map[int]f64{}
	url := 'https://www.imf.org/external/datamapper/api/v1/${dataset}/${iso2}'
	// IMF API 响应慢（~12s），需 30s 超时避免所有请求超时失败
	body := http_get_timeout(url, '', 30_000_000) or { return result }
	series_start := body.index('"Series"') or { return result }
	obs_start := body.index_after('"Obs"', series_start) or { return result }
	mut i := obs_start
	for i < body.len {
		ts := body.index_after('"@TIME"', i) or { -1 }
		if ts == -1 {
			break
		}
		// 读取年份
		tq := body.index_after(':', ts) or { -1 }
		if tq == -1 {
			break
		}
		tq2 := body.index_after('"', tq + 1) or { -1 }
		if tq2 == -1 {
			break
		}
		te := body.index_after('"', tq2 + 1) or { -1 }
		if te == -1 {
			break
		}
		year := body[tq2 + 1..te].int()
		// 找 @OBS_VALUE
		vs := body.index_after('"@OBS_VALUE"', te) or { -1 }
		if vs == -1 {
			break
		}
		vq := body.index_after(':', vs) or { -1 }
		if vq == -1 {
			break
		}
		// 跳到数值开始
		mut vp := vq + 1
		for vp < body.len && (body[vp] == ` ` || body[vp] == `,` || body[vp] == `"`) {
			vp++
		}
		mut ve := vp
		for ve < body.len && body[ve] != `,` && body[ve] != `}` && body[ve] != `"` {
			ve++
		}
		vstr := body[vp..ve].trim(' \t\n\r')
		if vstr != '' && vstr != 'null' {
			v := vstr.f64()
			if v > 0 {
				result[year] = v
			}
		}
		i = te + 1
	}
	return result
}
