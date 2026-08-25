module models

// 全局共享的数据模型 —— 整合 WorldBank / IMF / Market 三大数据源
// 数据库统一使用 MySQL（按 AGENT.md 要求），启动时可选从 SQLite 导入初始数据。

// ============ 数据源 & 指标分类（用于右侧栏分类检索）============

// DataSource 标识数据来源
pub enum DataSource {
	worldbank
	imf
	market
}

pub fn (d DataSource) str() string {
	return match d {
		.worldbank { 'worldbank' }
		.imf { 'imf' }
		.market { 'market' }
	}
}

pub fn data_source_from_str(s string) DataSource {
	match s {
		'worldbank' { return .worldbank }
		'imf' { return .imf }
		'market' { return .market }
		else { return .worldbank }
	}
}

// Category 用于右侧栏的分类目录
pub struct Category {
pub:
	id          string
	title       string
	source      string // 'worldbank' | 'imf' | 'market'
	description string
	icon        string
}

// ============ 国家 / 地区 ============

@[table: 'countries']
pub struct Country {
pub mut:
	id         int    @[primary; sql: 'AUTO_INCREMENT']
	iso2       string @[unique]
	iso3       string
	name       string
	region     string
	income     string
	created_at string @[sql: 'DEFAULT CURRENT_TIMESTAMP']
}

// ============ 宏观经济指标（WorldBank / IMF 通用事实表）============

@[table: 'indicators']
pub struct Indicator {
pub mut:
	id          int @[primary; sql: 'AUTO_INCREMENT']
	source      string // 'worldbank' | 'imf'
	country_iso string // iso2 of country
	indicator   string // indicator code, e.g. NY.GDP.MKTP.CD
	label       string // human label
	year        int
	value       f64
	unit        string
	updated_at  string @[sql: 'DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP']
}

// ============ 市场行情（股票 / 指数）============

@[table: 'market_quotes']
pub struct MarketQuote {
pub mut:
	id         int    @[primary; sql: 'AUTO_INCREMENT']
	symbol     string @[unique]
	name       string
	market     string // 'cn' | 'us' | 'hk' | 'index'
	price      f64
	prev_close f64
	change     f64
	change_pct f64
	volume     i64
	source     string
	updated_at string @[sql: 'DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP']
}

// ============ 市场标的定义（用于配置 / 扩展）============

pub struct MarketSymbol {
pub:
	symbol string
	name   string
	market string // 'cn' | 'us' | 'hk' | 'index'
}

// ============ 数据采集任务运行记录（用于自动更新 / 状态展示）============

@[table: 'fetch_logs']
pub struct FetchLog {
pub mut:
	id          int @[primary; sql: 'AUTO_INCREMENT']
	source      string // worldbank / imf / market
	status      string // running / success / failed
	message     string
	records     int
	started_at  string
	duration_ms int
}

// ============ 视图聚合结构（供前端展示）============

pub struct CountryStat {
pub:
	iso2       string
	name       string
	region     string
	population f64
	gdp        f64
	gdp_pc     f64
	life       f64
	unemploy   f64
	inflation  f64
}

pub struct WorldStats {
pub mut:
	total_countries    int
	total_population   f64
	total_gdp          f64
	avg_life           f64
	last_update        string
	// WLD 世界汇总指标（WorldBank 官方口径）
	gdp_per_capita     f64 // NY.GDP.PCAP.KD，constant 2015 USD
	inflation          f64 // FP.CPI.TOTL.ZG，%
	unemployment       f64 // SL.UEM.TOTL.NE.ZS，%
	internet_users     f64 // IT.NET.USER.ZS，%
	education_spend    f64 // SE.XPD.TOTL.GD.ZS，%GDP
	health_spend       f64 // SH.XPD.CHEX.GD.ZS，%GDP
	energy_use         f64 // EG.USE.PCAP.KG.OE，kg oil eq per capita
}

// CountryGdp 国家 GDP 排行条目（各国最新年份，含名称）
pub struct CountryGdp {
pub:
	iso2  string
	name  string
	value f64
	year  int
}

pub struct SidebarItem {
pub:
	id     string
	title  string
	source string
	icon   string
}

// 全部可用分类（右侧栏目录）
pub fn all_categories() []Category {
	return [
		Category{
			id:          'wb_overview'
			title:       '国家经济概览'
			source:      'worldbank'
			icon:        '🌍'
			description: '世界银行各国经济与社会指标'
		},
		Category{
			id:          'wb_gdp'
			title:       'GDP 与增长'
			source:      'worldbank'
			icon:        '💰'
			description: 'GDP、人均 GDP、增长率'
		},
		Category{
			id:          'wb_social'
			title:       '社会民生'
			source:      'worldbank'
			icon:        '👥'
			description: '人口、预期寿命、教育、失业'
		},
		Category{
			id:          'wb_energy'
			title:       '能源与环境'
			source:      'worldbank'
			icon:        '🌱'
			description: '能源使用、CO2 排放'
		},
		Category{
			id:          'imf_gdp'
			title:       'IMF GDP 估算'
			source:      'imf'
			icon:        '🏛️'
			description: 'IMF 口径 GDP / 人均 GDP'
		},
		Category{
			id:          'imf_wEO'
			title:       'IMF WEO 预测'
			source:      'imf'
			icon:        '📈'
			description: 'WEO 经济增长预测'
		},
		Category{
			id:          'mk_cn'
			title:       'A股行情'
			source:      'market'
			icon:        '🇨🇳'
			description: '沪深交易所实时行情'
		},
		Category{
			id:          'mk_hk'
			title:       '港股行情'
			source:      'market'
			icon:        '🇭🇰'
			description: '香港交易所实时行情'
		},
		Category{
			id:          'mk_us'
			title:       '美股行情'
			source:      'market'
			icon:        '🇺🇸'
			description: '美股实时行情'
		},
		Category{
			id:          'mk_index'
			title:       '全球指数'
			source:      'market'
			icon:        '📊'
			description: '主要股指行情'
		},
		Category{
			id:          'mk_fx'
			title:       '全球汇率'
			source:      'market'
			icon:        '💱'
			description: '主要货币对实时汇率'
		},
		Category{
			id:          'mk_commodity'
			title:       '大宗商品'
			source:      'market'
			icon:        '🛢️'
			description: '黄金、原油等大宗商品行情'
		},
	]
}

// iso2_to_flag_emoji 将 ISO 3166-1 alpha-2 代码转为区域字符 Emoji。
// 直接构造 UTF-8 字节，避免 rune 转换与 int 运算的兼容性陷阱。
pub fn iso2_to_flag_emoji(iso2 string) string {
	if iso2.len != 2 { return '' }
	mut buf := []u8{}
	for ch in iso2.bytes() {
		offset := int(ch) - int('A'[0])
		buf << 0xF0
		buf << 0x9F
		buf << 0x87
		buf << byte(0xA6 + offset)
	}
	return buf.bytestr()
}

// iso2_to_iso3 常用国家 iso2 -> iso3 映射。
// 源 SQLite 的 countries 表 iso3_code 全为空，导入/展示时用它补齐；
// 未收录的代码返回空串，由调用方决定回退行为。
pub fn iso2_to_iso3(iso2 string) string {
	m := {
		'US': 'USA'
		'CN': 'CHN'
		'JP': 'JPN'
		'DE': 'DEU'
		'GB': 'GBR'
		'FR': 'FRA'
		'IT': 'ITA'
		'CA': 'CAN'
		'KR': 'KOR'
		'AU': 'AUS'
		'BR': 'BRA'
		'IN': 'IND'
		'RU': 'RUS'
		'ES': 'ESP'
		'NL': 'NLD'
		'SE': 'SWE'
		'NO': 'NOR'
		'DK': 'DNK'
		'FI': 'FIN'
		'CH': 'CHE'
		'BE': 'BEL'
		'AT': 'AUT'
		'PL': 'POL'
		'CZ': 'CZE'
		'GR': 'GRC'
		'PT': 'PRT'
		'IE': 'IRL'
		'SG': 'SGP'
		'NZ': 'NZL'
		'ZA': 'ZAF'
		'MX': 'MEX'
		'ID': 'IDN'
		'TR': 'TUR'
		'SA': 'SAU'
		'AE': 'ARE'
		'HK': 'HKG'
		'TW': 'TWN'
		'TH': 'THA'
		'MY': 'MYS'
		'PH': 'PHL'
		'VN': 'VNM'
		'AR': 'ARG'
		'CL': 'CHL'
		'CO': 'COL'
		'PE': 'PER'
		'EG': 'EGY'
		'NG': 'NGA'
		'IL': 'ISR'
		'PK': 'PAK'
		'BD': 'BGD'
		'KE': 'KEN'
		'MA': 'MAR'
		'GH': 'GHA'
		'TZ': 'TZA'
		'ET': 'ETH'
		'CI': 'CIV'
		'IR': 'IRN'
		'QA': 'QAT'
		'VE': 'VEN'
		'EC': 'ECU'
		'HU': 'HUN'
		'RO': 'ROU'
		'SK': 'SVK'
		'SI': 'SVN'
		'HR': 'HRV'
		'BG': 'BGR'
		'SR': 'SRB'
		'PG': 'PNG'
		'GT': 'GTM'
		'CU': 'CUB'
		'DO': 'DOM'
		'TN': 'TUN'
		'KZ': 'KAZ'
		'LK': 'LKA'
	}
	return m[iso2] or { '' }
}

// 格式化大数值（从原 worldbank 代码沿用）
pub fn format_large(v f64) string {
	if v == 0.0 {
		return '-'
	}
	mut div := 0.0
	mut suffix := ''
	if v >= 1e12 {
		div = 1e12
		suffix = 'T'
	} else if v >= 1e9 {
		div = 1e9
		suffix = 'B'
	} else if v >= 1e6 {
		div = 1e6
		suffix = 'M'
	} else if v >= 1e3 {
		div = 1e3
		suffix = 'K'
	} else {
		return v.str().split('.')[0]
	}
	q := v / div
	parts := q.str().split('.')
	// 整值（如恰好 1e12）无小数部分，直接返回避免越界
	if parts.len < 2 {
		return parts[0] + suffix
	}
	return parts[0] + '.' + parts[1][0..1] + suffix
}
