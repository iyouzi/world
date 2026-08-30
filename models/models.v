module models

import locale

// 全局共享的数据模型 —— 整合 WorldBank / IMF / Market 三大数据源
// 数据库统一使用 MySQL（按 AGENT.md 要求），启动时可选从 SQLite 导入初始数据。

// ============ 数据源 & 指标分类（用于右侧栏分类检索）============

// DataSource 标识数据来源
pub enum DataSource {
	worldbank
	imf
	market
	owid
}

pub fn (d DataSource) str() string {
	return match d {
		.worldbank { 'worldbank' }
		.imf { 'imf' }
		.market { 'market' }
		.owid { 'owid' }
	}
}

pub fn data_source_from_str(s string) DataSource {
	match s {
		'worldbank' { return .worldbank }
		'imf' { return .imf }
		'market' { return .market }
		'owid' { return .owid }
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
	total_countries  int
	total_population f64
	total_gdp        f64
	avg_life         f64
	last_update      string
	// WLD 世界汇总指标（WorldBank 官方口径）
	gdp_per_capita  f64 // NY.GDP.PCAP.KD，constant 2015 USD
	inflation       f64 // FP.CPI.TOTL.ZG，%
	unemployment    f64 // SL.UEM.TOTL.NE.ZS，%
	internet_users  f64 // IT.NET.USER.ZS，%
	education_spend f64 // SE.XPD.TOTL.GD.ZS，%GDP
	health_spend    f64 // SH.XPD.CHEX.GD.ZS，%GDP
	energy_use      f64 // EG.USE.PCAP.KG.OE，kg oil eq per capita
}

// CountryGdp 国家 GDP 排行条目（各国最新年份，含名称）
pub struct CountryGdp {
pub:
	iso2  string
	name  string
	value f64
	year  int
}

// HomeCountry 首页国家概览表数据
pub struct HomeCountry {
pub:
	iso2           string
	name           string
	population     f64
	land_area      f64
	gdp            f64
	gdp_ppp        f64
	gdp_per_capita f64
	gdp_ppc_ppp    f64
	ppp_per_sqkm   f64
	note           string
	year           int
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
		// OWID Our World in Data 分类
		Category{
			id:          'owid_population'
			title:       '人口与人口统计'
			source:      'owid'
			icon:        '👥'
			description: '全球人口变化、年龄结构、生育率、城镇化趋势'
		},
		Category{
			id:          'owid_health'
			title:       '健康与医疗'
			source:      'owid'
			icon:        '🏥'
			description: '预期寿命、儿童死亡率、孕产妇健康与吸烟率'
		},
		Category{
			id:          'owid_energy'
			title:       '能源与环境'
			source:      'owid'
			icon:        '⚡'
			description: '能源消耗、碳排放、可再生能源与气候变化'
		},
		Category{
			id:          'owid_economy'
			title:       '经济与繁荣'
			source:      'owid'
			icon:        '📈'
			description: '人均 GDP（购买力平价）、经济增长'
		},
		Category{
			id:          'owid_education'
			title:       '教育与知识'
			source:      'owid'
			icon:        '📚'
			description: '平均受教育年限、教育投资与技能发展'
		},
		Category{
			id:          'owid_food'
			title:       '食品与农业'
			source:      'owid'
			icon:        '🌾'
			description: '营养状况、肉类供给、粮食安全与饮食变化'
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

// OwidIndicator OWID CSV 指标定义（slug → 中文名/单位/CSV列名/主题）
pub struct OwidIndicator {
pub:
	slug        string // CSV 文件名（不含 .csv）
	column_name string // CSV 中数值列名（空则用第 4 列）
	topic_slug  string // 主题 slug
	name_zh     string // 中文名
	name_en     string // 英文名
	unit        string // 单位
}

// name 按语言返回指标名称
pub fn (o &OwidIndicator) name(lang locale.Lang) string {
	return if lang == .en { o.name_en } else { o.name_zh }
}

pub fn owid_indicators() []OwidIndicator {
	return [
		OwidIndicator{
			slug:        'population'
			column_name: 'population_historical'
			topic_slug:  'owid_population'
			name_zh:     '人口总数'
			name_en:     'Total Population'
			unit:        '人'
		},
		OwidIndicator{
			slug:        'life-expectancy'
			column_name: 'life_expectancy_0'
			topic_slug:  'owid_population'
			name_zh:     '预期寿命'
			name_en:     'Life Expectancy'
			unit:        '岁'
		},
		OwidIndicator{
			slug:        'children-per-woman-un'
			column_name: 'fertility_rate__sex_all__age_all__variant_estimates'
			topic_slug:  'owid_population'
			name_zh:     '生育率'
			name_en:     'Fertility Rate'
			unit:        '孩/妇'
		},
		OwidIndicator{
			slug:        'median-age'
			column_name: 'median_age__sex_all__age_all__variant_estimates'
			topic_slug:  'owid_population'
			name_zh:     '中位年龄'
			name_en:     'Median Age'
			unit:        '岁'
		},
		OwidIndicator{
			slug:        'share-of-population-urban'
			column_name: 'share__area_type_urban__data_type_estimates'
			topic_slug:  'owid_population'
			name_zh:     '城镇化率'
			name_en:     'Urban Population Share'
			unit:        '%'
		},
		OwidIndicator{
			slug:        'child-mortality'
			column_name: 'child_mortality_rate'
			topic_slug:  'owid_health'
			name_zh:     '5岁以下儿童死亡率'
			name_en:     'Child Mortality Rate'
			unit:        '‰'
		},
		OwidIndicator{
			slug:        'maternal-mortality'
			column_name: 'mmr'
			topic_slug:  'owid_health'
			name_zh:     '孕产妇死亡率'
			name_en:     'Maternal Mortality'
			unit:        '/10万'
		},
		OwidIndicator{
			slug:        'share-of-adults-who-smoke'
			column_name: 'tobacco_use_pct_age_std__sex_both_sexes'
			topic_slug:  'owid_health'
			name_zh:     '吸烟率'
			name_en:     'Smoking Rate'
			unit:        '%'
		},
		OwidIndicator{
			slug:        'annual-co2-emissions-per-country'
			column_name: 'emissions_total'
			topic_slug:  'owid_energy'
			name_zh:     '年度CO₂排放量'
			name_en:     'Annual CO₂ Emissions'
			unit:        '吨'
		},
		OwidIndicator{
			slug:        'co2-emissions-per-capita'
			column_name: 'emissions_total_per_capita'
			topic_slug:  'owid_energy'
			name_zh:     '人均CO₂排放量'
			name_en:     'CO₂ per Capita'
			unit:        '吨'
		},
		OwidIndicator{
			slug:        'share-electricity-renewables'
			column_name: 'renewable_share_of_electricity__pct'
			topic_slug:  'owid_energy'
			name_zh:     '可再生电力占比'
			name_en:     'Renewable Electricity Share'
			unit:        '%'
		},
		OwidIndicator{
			slug:        'gdp-per-capita-worldbank'
			column_name: 'ny_gdp_pcap_pp_kd'
			topic_slug:  'owid_economy'
			name_zh:     '人均GDP(PPP)'
			name_en:     'GDP per Capita (PPP)'
			unit:        '国际元'
		},
		OwidIndicator{
			slug:        'mean-years-of-schooling'
			column_name: 'mf_youth_and_adults__15_64_years__average_years_of_education'
			topic_slug:  'owid_education'
			name_zh:     '平均受教育年限'
			name_en:     'Mean Years of Schooling'
			unit:        '年'
		},
		OwidIndicator{
			slug:        'meat-supply-per-person'
			column_name: 'meat__total__00002943__food_available_for_consumption__0645pc__kilograms_per_year_per_capita'
			topic_slug:  'owid_food'
			name_zh:     '人均肉类供给'
			name_en:     'Meat Supply per Person'
			unit:        '公斤/年'
		},
		OwidIndicator{
			slug:        'food-supply-kcal'
			column_name: 'daily_calories'
			topic_slug:  'owid_food'
			name_zh:     '日均热量供给'
			name_en:     'Daily Calorie Supply'
			unit:        '千卡/人/天'
		},
		OwidIndicator{
			slug:        'prevalence-of-undernourishment'
			column_name: '_2_1_1_prevalence_of_undernourishment__000000000024000__value__006121__percent'
			topic_slug:  'owid_food'
			name_zh:     '营养不足发生率'
			name_en:     'Prevalence of Undernourishment'
			unit:        '%'
		},
	]
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

// iso3_to_iso2 反向映射：ISO3 → ISO2（用于 OWID CSV 的 code 列转换）
pub fn iso3_to_iso2(iso3 string) string {
	m := {
		'USA':       'US'
		'CHN':       'CN'
		'JPN':       'JP'
		'DEU':       'DE'
		'GBR':       'GB'
		'FRA':       'FR'
		'ITA':       'IT'
		'CAN':       'CA'
		'KOR':       'KR'
		'AUS':       'AU'
		'BRA':       'BR'
		'IND':       'IN'
		'RUS':       'RU'
		'ESP':       'ES'
		'NLD':       'NL'
		'SWE':       'SE'
		'NOR':       'NO'
		'DNK':       'DK'
		'FIN':       'FI'
		'CHE':       'CH'
		'BEL':       'BE'
		'AUT':       'AT'
		'POL':       'PL'
		'CZE':       'CZ'
		'GRC':       'GR'
		'PRT':       'PT'
		'IRL':       'IE'
		'SGP':       'SG'
		'NZL':       'NZ'
		'ZAF':       'ZA'
		'MEX':       'MX'
		'IDN':       'ID'
		'TUR':       'TR'
		'SAU':       'SA'
		'ARE':       'AE'
		'HKG':       'HK'
		'TWN':       'TW'
		'THA':       'TH'
		'MYS':       'MY'
		'PHL':       'PH'
		'VNM':       'VN'
		'ARG':       'AR'
		'CHL':       'CL'
		'COL':       'CO'
		'PER':       'PE'
		'EGY':       'EG'
		'NGA':       'NG'
		'ISR':       'IL'
		'PAK':       'PK'
		'BGD':       'BD'
		'KEN':       'KE'
		'MAR':       'MA'
		'GHA':       'GH'
		'TZA':       'TZ'
		'ETH':       'ET'
		'CIV':       'CI'
		'IRN':       'IR'
		'QAT':       'QA'
		'VEN':       'VE'
		'ECU':       'EC'
		'HUN':       'HU'
		'ROU':       'RO'
		'SVK':       'SK'
		'SVN':       'SI'
		'HRV':       'HR'
		'BGR':       'BG'
		'SRB':       'SR'
		'PNG':       'PG'
		'GTM':       'GT'
		'CUB':       'CU'
		'DOM':       'DO'
		'TUN':       'TN'
		'KAZ':       'KZ'
		'LKA':       'LK'
		'AFG':       'AF'
		'ALB':       'AL'
		'DZA':       'DZ'
		'AGO':       'AO'
		'ARM':       'AM'
		'AZE':       'AZ'
		'BHS':       'BS'
		'BHR':       'BH'
		'BRB':       'BB'
		'BLR':       'BY'
		'BLZ':       'BZ'
		'BEN':       'BJ'
		'BMU':       'BM'
		'BTN':       'BT'
		'BOL':       'BO'
		'BIH':       'BA'
		'BWA':       'BW'
		'BRN':       'BN'
		'BFA':       'BF'
		'BDI':       'BI'
		'KHM':       'KH'
		'CMR':       'CM'
		'CPV':       'CV'
		'CAF':       'CF'
		'TCD':       'TD'
		'COM':       'KM'
		'COG':       'CG'
		'COD':       'CD'
		'CRI':       'CR'
		'CYP':       'CY'
		'DJI':       'DJ'
		'SLV':       'SV'
		'GNQ':       'GQ'
		'ERI':       'ER'
		'EST':       'EE'
		'SWZ':       'SZ'
		'FJI':       'FJ'
		'GAB':       'GA'
		'GMB':       'GM'
		'GEO':       'GE'
		'GIN':       'GN'
		'GNB':       'GW'
		'GUY':       'GY'
		'HTI':       'HT'
		'HND':       'HN'
		'ISL':       'IS'
		'IRQ':       'IQ'
		'JAM':       'JM'
		'JOR':       'JO'
		'KIR':       'KI'
		'PRK':       'KP'
		'KWT':       'KW'
		'KGZ':       'KG'
		'LAO':       'LA'
		'LVA':       'LV'
		'LBN':       'LB'
		'LSO':       'LS'
		'LBR':       'LR'
		'LBY':       'LY'
		'LTU':       'LT'
		'LUX':       'LU'
		'MDG':       'MG'
		'MWI':       'MW'
		'MDV':       'MV'
		'MLI':       'ML'
		'MLT':       'MT'
		'MHL':       'MH'
		'MRT':       'MR'
		'MUS':       'MU'
		'FSM':       'FM'
		'MDA':       'MD'
		'MCO':       'MC'
		'MNG':       'MN'
		'MNE':       'ME'
		'MOZ':       'MZ'
		'MMR':       'MM'
		'NAM':       'NA'
		'NRU':       'NR'
		'NPL':       'NP'
		'NIC':       'NI'
		'NER':       'NE'
		'MKD':       'MK'
		'OMN':       'OM'
		'PLW':       'PW'
		'PAN':       'PA'
		'PRY':       'PY'
		'WSM':       'WS'
		'SMR':       'SM'
		'STP':       'ST'
		'SEN':       'SN'
		'SYC':       'SC'
		'SLE':       'SL'
		'SLB':       'SB'
		'SOM':       'SO'
		'SSD':       'SS'
		'SDN':       'SD'
		'SUR':       'SR'
		'SYR':       'SY'
		'TLS':       'TL'
		'TGO':       'TG'
		'TON':       'TO'
		'TTO':       'TT'
		'TKM':       'TM'
		'TUV':       'TV'
		'UGA':       'UG'
		'UKR':       'UA'
		'URY':       'UY'
		'UZB':       'UZ'
		'VUT':       'VU'
		'YEM':       'YE'
		'ZMB':       'ZM'
		'ZWE':       'ZW'
		// OWID 特殊代码（无对应 ISO2，返回空串）
		'WLD':       ''
		'OWID_WRL':  ''
		'OWID_HIC':  ''
		'OWID_LIC':  ''
		'OWID_LMC':  ''
		'OWID_UMC':  ''
		'OWID_CIS':  ''
		'OWID_EU':   ''
		'OWID_EFTA': ''
		'OWID_NAM':  ''
		'OWID_SAM':  ''
		'OWID_CAF':  ''
		'OWID_OCE':  ''
		'OWID_AFR':  ''
		'OWID_ASI':  ''
		'OWID_EUR':  ''
		'OWID_M49':  ''
	}
	return m[iso3] or { '' }
}

// format_large 格式化大数值，保留 2 位小数（Python .2f 风格）
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
		return '${v:.2f}'
	}
	q := v / div
	return '${q:.2f}${suffix}'
}
