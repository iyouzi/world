module locale

import json2

// Lang 表示界面语言
pub enum Lang {
	zh
	en
}

// str 返回语言代码（'zh' 或 'en'），用于 cookie / query / JS
pub fn (l Lang) str() string {
	return match l {
		.zh { 'zh' }
		.en { 'en' }
	}
}

// parse_lang 将字符串解析为 Lang，未知值回落到中文
pub fn parse_lang(s string) Lang {
	return if s == 'en' { .en } else { .zh }
}

// zh_dict 返回中文文案词典（单一数据源）
pub fn zh_dict() map[string]string {
	return {
		'app_title':            '世界数据全景'
		'app_desc':             '整合世界银行、IMF、全球市场行情与 OWID 数据，一站式展示世界经济与社会发展图景。'
		'meta_desc':            '世界数据全景 (WorldApp) — World Bank / IMF / 全球市场 / OWID 一站式数据可视化'
		'top_world_gdp':        '世界GDP (USD)'
		'top_countries':        '国家数'
		'top_life':             '平均寿命 (年)'
		'top_status':           '更新状态'
		'status_ready':         '就绪'
		'status_querying':      '查询中…'
		'status_connecting':    '连接中…'
		'status_updating':      '更新中…'
		'mobile_bar':           '世界数据全景 · {n} 个国家'
		'menu':                 '菜单'
		'search_placeholder':   '搜索国家 / 市场 / 指标...'
		'refresh_btn':          '立即更新数据'
		'switch_lang':          '语言'
		'lang_zh':              '中文'
		'lang_en':              'EN'
		'theme_toggle':         '切换主题'
		'wait_first_fetch':     '等待首次抓取'
		'year_unit':            '年'
		// 数据源分组（侧栏短标签）
		'src_worldbank':        '🌍 世界银行'
		'src_imf':              '🏛️ 国际货币基金'
		'src_market':           '📈 全球市场'
		'src_owid':             '📊 OWID 全球数据'
		// 数据源分组（详情页完整标签）
		'src_worldbank_full':   '🌍 世界银行 (WorldBank)'
		'src_imf_full':         '🏛️ 国际货币基金 (IMF)'
		'src_owid_full':        '📊 OWID 全球数据'
		// 分类（18 个）
		'cat_wb_overview':      '国家经济概览'
		'cat_wb_gdp':           'GDP 与增长'
		'cat_wb_social':        '社会民生'
		'cat_wb_energy':        '能源与环境'
		'cat_imf_gdp':          'IMF GDP 估算'
		'cat_imf_weo':          'WEO 经济增长预测'
		'cat_mk_cn':            'A股'
		'cat_mk_hk':            '港股'
		'cat_mk_us':            '美股'
		'cat_mk_index':         '全球指数'
		'cat_mk_fx':            '汇率'
		'cat_mk_commodity':     '大宗商品'
		'cat_owid_population':  '人口'
		'cat_owid_health':      '健康'
		'cat_owid_energy':      '能源'
		'cat_owid_economy':     '经济'
		'cat_owid_education':   '教育'
		'cat_owid_food':        '食品'
		// 行情页标签
		'mk_cn_full':           '🇨🇳 A股行情'
		'mk_hk_full':           '🇭🇰 港股行情'
		'mk_us_full':           '🇺🇸 美股行情'
		'mk_index_full':        '📊 全球指数'
		'mk_fx_full':           '💱 全球汇率'
		'mk_commodity_full':    '🛢️ 大宗商品'
		'mk_default':           '📈 全球市场行情'
		// 概览页
		'overview_sub':         'World Bank · IMF · 全球市场 · OWID'
		'world_bank':           'World Bank'
		'imf':                  'IMF'
		'card_world_gdp':       '世界GDP'
		'card_countries':       '国家数'
		'card_population':      '总人口'
		'card_avg_life':        '平均寿命(年)'
		'wld_core':             'World Core Indicators (WLD)'
		'wld_gdp_pc':           '人均GDP (USD, 2015不变价)'
		'wld_cpi':              'CPI 通胀 (%)'
		'wld_unemp':            '失业率 (%)'
		'wld_inet':             '互联网普及率'
		'wld_edu':              '教育支出 (% GDP)'
		'wld_health':           '医疗支出 (% GDP)'
		'wld_energy':           '能源消耗 (kg油当量/人)'
		'wld_items':            '{n} 项'
		'gdp_top20':            'GDP Top 20'
		'imf_top20':            'IMF GDP Top 20'
		'rank':                 '#'
		'country':              '国家'
		'country_code':         '国家代码'
		'gdp_usd':              'GDP (USD)'
		'year':                 '年份'
		'value':                '数值'
		'code':                 '代码'
		'volume':               '成交量'
		'api':                  'API'
		'gdp_chart':            'GDP 图表'
		'chartjs':              'Chart.js'
		'data_source':          '数据源'
		'indicator_code':       '指标代码'
		'unit':                 '单位'
		'home_g20_table':       'G20 及全球主要经济体一览'
		'home_population':      '人口'
		'home_area':            '国土面积 (km²)'
		'home_gdp':             'GDP (USD)'
		'home_gdp_ppp':         'GDP (PPP)'
		'home_gdppc':           '人均GDP'
		'home_gdppc_ppp':       '人均GDP (PPP)'
		'home_ppp_per_sqkm':    'PPP 密度 ($/km²)'
		'home_note':            '备注'
		'empty_data':           '暂无数据：后台抓取尚未成功或源接口不可用'
		'empty_imf':            '暂无 IMF 数据：后台抓取尚未成功或源接口不可用'
		'empty_market':         '暂无行情数据：后台抓取尚未成功或行情源不可用'
		'empty_owid':           '暂无 OWID 数据：本地 CSV 未导入或源不可用'
		'retry_hint':           '可点击侧栏「🔄 立即更新数据」重试，详见 world_data.log'
		'wb_sub_countries':     '共 {n} 个国家（最新年份）'
		'rel_share':            '相对占比'
		'imf_growth_note':      '实际 GDP 同比增长 %'
		'imf_usd_note':         '现价美元 (USD)'
		'imf_updated':          '更新于 {upd} · 共 {n} 个经济体'
		'rel_dist':             '相对分布'
		'ranking':              '排名列表'
		'top_n':                'Top {n}'
		// 国家详情页
		'country_overview':     '国家概览'
		'back_home':            '返回首页'
		'country_detail_title': '国家详情：{iso}'
		'country_sub':          '该国在经济、社会、环境等维度的全部指标'
		'country_nodata':       '该国家暂无已记录的指标数据'
		'country_retry':        '可点击侧栏「🔄 立即更新数据」抓取最新数据'
		'country_fetching':     '正在后台抓取该国家数据，请稍后刷新。'
		'records_count':        '共 {n} 条记录'
		'ind_name':             '指标名'
		'ind_code':             '指标代码'
		'indicators_count':     '共 {n} 条指标 (最新年份 {y})'
		'items_count':          '{n} 项'
		'wb_indicators':        'World Bank 指标'
		'imf_indicators':       'IMF 指标'
		'owid_indicators':      'OWID 指标'
		'no_wb':                '暂无 World Bank 指标'
		'no_imf':               '暂无 IMF 指标'
		'no_owid':              '暂无 OWID 指标'
		'src_owid_cat':         'OWID'
		'owid_sub':             '数据源：OWID (Our World in Data) · 指标：{slug} · 单位：{unit}'
		// 分类页
		'cat_title':            '分类'
		'loading':              '加载中…'
		'no_match':             '没有匹配的指标'
		'error_load':           '加载失败'
		'invalid_page':         '页码无效'
		'not_found':            '未找到该分类'
		// 行情页
		'market_title':         '行情'
		'quote_name':           '名称'
		'quote_price':          '现价'
		'quote_chg':            '涨跌'
		'quote_chg_pct':        '涨跌幅'
		'no_quotes':            '暂无行情数据'
		'mkt_count':            '标的数'
		'mkt_up':               '上涨家数'
		'mkt_down':             '下跌家数'
		'mkt_avg':              '平均涨跌幅 · {up}% 上涨'
		'ds_cn':                '腾讯 / 新浪 / 网易 实时接口'
		'ds_index':             '腾讯 / 新浪 实时接口'
		'ds_fx':                'open.er-api.com（兑美元，免 key）'
		'ds_commodity':         '新浪外盘期货（hf_*，GBK 转码）'
		'ds_multi':             '多市场实时接口'
		// 客户端 JS 文案
		'js_refreshing':        '正在触发全量更新…'
		'js_request_fail':      '请求失败：'
		'js_refresh_ok':        '已触发后台更新'
		'js_refresh_err':       '更新失败'
		'js_search_err':        '搜索出错'
		'js_chart_err':         '渲染图表出错'
		'js_search_hint':       '输入关键词搜索'
		'js_searching':         '正在搜索…'
		'js_no_match':          '没有找到匹配项'
		'js_found':             '找到 {n} 条匹配结果'
		'js_country':           '国家'
		'js_market':            '市场'
		'js_markets_count':     '{n} 个市场'
		'js_results_count':     '{n} 个结果'
		'online_now':           '当前在线'
		'last_update':          '最近更新'
		'fetch_status':         '抓取状态'
		'system_up':            '系统运行'
		'js_load_more':         '点击加载更多'
		'js_loading':           '加载中…'
		'js_load_more2':        '加载更多'
	}
}

// en_dict 返回英文文案词典（单一数据源）
pub fn en_dict() map[string]string {
	return {
		'app_title':            'World Data Panorama'
		'app_desc':             'Integrating World Bank, IMF, global market quotes and OWID data into a one-stop view of the world economy and society.'
		'meta_desc':            'World Data Panorama (WorldApp) — World Bank / IMF / Global Markets / OWID one-stop data visualization'
		'top_world_gdp':        'World GDP (USD)'
		'top_countries':        'Countries'
		'top_life':             'Life Exp. (yrs)'
		'top_status':           'Update Status'
		'status_ready':         'Ready'
		'status_querying':      'Querying...'
		'status_connecting':    'Connecting...'
		'status_updating':      'Updating...'
		'mobile_bar':           'World Data Panorama · {n} countries'
		'menu':                 'Menu'
		'search_placeholder':   'Search countries / markets / indicators...'
		'refresh_btn':          'Refresh Data Now'
		'switch_lang':          'Language'
		'lang_zh':              '中文'
		'lang_en':              'EN'
		'theme_toggle':         'Toggle theme'
		'wait_first_fetch':     'Waiting for first fetch'
		'year_unit':            ''
		'src_worldbank':        '🌍 World Bank'
		'src_imf':              '🏛️ IMF'
		'src_market':           '📈 Global Markets'
		'src_owid':             '📊 OWID Global Data'
		'src_worldbank_full':   '🌍 World Bank (WorldBank)'
		'src_imf_full':         '🏛️ IMF (International Monetary Fund)'
		'src_owid_full':        '📊 OWID Global Data'
		'cat_wb_overview':      'Country Economic Overview'
		'cat_wb_gdp':           'GDP & Growth'
		'cat_wb_social':        'Society & Living'
		'cat_wb_energy':        'Energy & Environment'
		'cat_imf_gdp':          'IMF GDP Estimates'
		'cat_imf_weo':          'WEO Growth Forecast'
		'cat_mk_cn':            'A-Shares'
		'cat_mk_hk':            'HK Stocks'
		'cat_mk_us':            'US Stocks'
		'cat_mk_index':         'Global Indices'
		'cat_mk_fx':            'FX'
		'cat_mk_commodity':     'Commodities'
		'cat_owid_population':  'Population'
		'cat_owid_health':      'Health'
		'cat_owid_energy':      'Energy'
		'cat_owid_economy':     'Economy'
		'cat_owid_education':   'Education'
		'cat_owid_food':        'Food'
		'mk_cn_full':           '🇨🇳 A-Shares'
		'mk_hk_full':           '🇭🇰 HK Stocks'
		'mk_us_full':           '🇺🇸 US Stocks'
		'mk_index_full':        '📊 Global Indices'
		'mk_fx_full':           '💱 Global FX'
		'mk_commodity_full':    '🛢️ Commodities'
		'mk_default':           '📈 Global Market Quotes'
		'overview_sub':         'World Bank · IMF · Global Markets · OWID'
		'world_bank':           'World Bank'
		'imf':                  'IMF'
		'card_world_gdp':       'World GDP'
		'card_countries':       'Countries'
		'card_population':      'Population'
		'card_avg_life':        'Avg Life (yrs)'
		'wld_core':             'World Core Indicators (WLD)'
		'wld_gdp_pc':           'GDP per capita (USD, const 2015)'
		'wld_cpi':              'CPI Inflation (%)'
		'wld_unemp':            'Unemployment (%)'
		'wld_inet':             'Internet Penetration'
		'wld_edu':              'Education Spend (% GDP)'
		'wld_health':           'Health Spend (% GDP)'
		'wld_energy':           'Energy Use (kg oil eq/cap)'
		'wld_items':            '{n} items'
		'gdp_top20':            'GDP Top 20'
		'imf_top20':            'IMF GDP Top 20'
		'rank':                 '#'
		'country':              'Country'
		'country_code':         'Country Code'
		'gdp_usd':              'GDP (USD)'
		'year':                 'Year'
		'value':                'Value'
		'code':                 'Code'
		'volume':               'Volume'
		'api':                  'API'
		'gdp_chart':            'GDP Chart'
		'chartjs':              'Chart.js'
		'data_source':          'Source'
		'indicator_code':       'Indicator'
		'unit':                 'Unit'
		'home_g20_table':       'G20 & Major Global Economies'
		'home_population':      'Population'
		'home_area':            'Land Area (km²)'
		'home_gdp':             'GDP (USD)'
		'home_gdp_ppp':         'GDP (PPP)'
		'home_gdppc':           'GDP/cap'
		'home_gdppc_ppp':       'GDP/cap (PPP)'
		'home_ppp_per_sqkm':    'PPP Density ($/km²)'
		'home_note':            'Note'
		'empty_data':           'No data: background fetch not yet successful or source unavailable'
		'empty_imf':            'No IMF data: background fetch not yet successful or source unavailable'
		'empty_market':         'No quote data: background fetch not yet successful or quote source unavailable'
		'empty_owid':           'No OWID data: local CSV not imported or source unavailable'
		'retry_hint':           'Click "Refresh Data" in the sidebar to retry. See world_data.log'
		'wb_sub_countries':     'Countries (latest year)'
		'rel_share':            'Share'
		'imf_growth_note':      'Real GDP YoY %'
		'imf_usd_note':         'Current USD'
		'imf_updated':          'Updated {upd} · {n} economies'
		'rel_dist':             'Distribution'
		'ranking':              'Ranking'
		'top_n':                'Top {n}'
		'country_overview':     'Country Overview'
		'back_home':            'Back to Home'
		'country_detail_title': 'Country Detail: {iso}'
		'country_sub':          'All indicators for this country across economy, society and environment'
		'country_nodata':       'No recorded indicator data for this country'
		'country_retry':        'Click "Refresh Data" to fetch the latest data'
		'country_fetching':     'Background fetching in progress; please refresh later.'
		'records_count':        '{n} records'
		'ind_name':             'Indicator'
		'ind_code':             'Code'
		'indicators_count':     '{n} indicators (latest year {y})'
		'items_count':          '{n} items'
		'wb_indicators':        'World Bank Indicators'
		'imf_indicators':       'IMF Indicators'
		'owid_indicators':      'OWID Indicators'
		'no_wb':                'No World Bank indicators'
		'no_imf':               'No IMF indicators'
		'no_owid':              'No OWID indicators'
		'src_owid_cat':         'OWID'
		'owid_sub':             'Source: OWID (Our World in Data) · Indicator: {slug} · Unit: {unit}'
		'cat_title':            'Category'
		'loading':              'Loading...'
		'no_match':             'No matching indicators'
		'error_load':           'Failed to load'
		'invalid_page':         'Invalid page'
		'not_found':            'Category not found'
		'market_title':         'Quotes'
		'quote_name':           'Name'
		'quote_price':          'Last'
		'quote_chg':            'Chg'
		'quote_chg_pct':        'Chg%'
		'no_quotes':            'No quote data'
		'mkt_count':            'Symbols'
		'mkt_up':               'Advancers'
		'mkt_down':             'Decliners'
		'mkt_avg':              'Avg Chg · {up}% up'
		'ds_cn':                'Tencent / Sina / NetEase realtime API'
		'ds_index':             'Tencent / Sina realtime API'
		'ds_fx':                'open.er-api.com (USD, no key)'
		'ds_commodity':         'Sina futures (hf_*, GBK decoded)'
		'ds_multi':             'Multi-market realtime API'
		'js_refreshing':        'Triggering full refresh...'
		'js_request_fail':      'Request failed: '
		'js_refresh_ok':        'Background refresh triggered'
		'js_refresh_err':       'Refresh failed'
		'js_search_err':        'Search error'
		'js_chart_err':         'Chart rendering error'
		'js_search_hint':       'Type to search'
		'js_searching':         'Searching...'
		'js_no_match':          'No matches found'
		'js_found':             'Found {n} results'
		'js_country':           'Country'
		'js_market':            'Market'
		'js_markets_count':     '{n} markets'
		'js_results_count':     '{n} results'
		'online_now':           'Online'
		'last_update':          'Last Update'
		'fetch_status':         'Fetch Status'
		'system_up':            'System'
		'js_load_more':         'Click to load more'
		'js_loading':           'Loading...'
		'js_load_more2':        'Load more'
	}
}

// t 取文案（无插值）
pub fn t(lang Lang, key string) string {
	return lookup(lang, key)
}

// tf 取文案并做 {name} 占位符替换
pub fn tf(lang Lang, key string, params map[string]string) string {
	mut out := lookup(lang, key)
	for k, v in params {
		out = out.replace('{${k}}', v)
	}
	return out
}

fn lookup(lang Lang, key string) string {
	return match lang {
		.en { en_dict()[key] or { zh_dict()[key] or { key } } }
		else { zh_dict()[key] or { en_dict()[key] or { key } } }
	}
}

// status_label 把抓取状态代码映射为可读文案
pub fn status_label(lang Lang, code string) string {
	return match code {
		'querying' { t(lang, 'status_querying') }
		'connecting' { t(lang, 'status_connecting') }
		'updating' { t(lang, 'status_updating') }
		else { t(lang, 'status_ready') }
	}
}

// I18nBundle 用于向浏览器注入双语词典
pub struct I18nBundle {
	zh map[string]string
	en map[string]string
}

// bundle 返回完整双语词典，供前端 JSON 注入
pub fn bundle() I18nBundle {
	return I18nBundle{
		zh: zh_dict()
		en: en_dict()
	}
}

// json_bundle 返回注入到页面 <script> 的双语词典 JSON
pub fn json_bundle() string {
	return json2.encode(bundle())
}
