module models

fn test_format_large_units() {
	assert format_large(0.0) == '-'
	assert format_large(123.45) == '123.45'
	assert format_large(4000.0) == '4.00K'
	assert format_large(3000000.0) == '3.00M'
	assert format_large(2500000000.0) == '2.50B'
	assert format_large(1500000000000.0) == '1.50T'
}

// 整值边界：旧实现会因 split('.')[1] 越界 panic
fn test_format_large_exact_boundaries() {
	assert format_large(1e12) == '1.00T'
	assert format_large(1e9) == '1.00B'
	assert format_large(1e6) == '1.00M'
	assert format_large(1e3) == '1.00K'
}

fn test_data_source_roundtrip() {
	for d in [DataSource.worldbank, .imf, .market, .owid] {
		assert data_source_from_str(d.str()) == d
	}
	// 未知来源回退 worldbank
	assert data_source_from_str('nope') == .worldbank
}

fn test_all_categories_complete_and_unique() {
	cats := all_categories()
	// 12 个原始分类 + 6 个 OWID 分类 = 18
	assert cats.len == 18
	mut seen := map[string]bool{}
	for c in cats {
		assert c.id != ''
		assert c.title != ''
		assert c.description != ''
		assert c.icon != ''
		assert c.source in ['worldbank', 'imf', 'market', 'owid']
		assert !seen[c.id]
		seen[c.id] = true
	}
	// 新增的汇率 / 大宗商品分类必须存在
	assert seen['mk_fx']
	assert seen['mk_commodity']
	// OWID 分类必须存在
	assert seen['owid_population']
	assert seen['owid_health']
	assert seen['owid_energy']
	assert seen['owid_economy']
	assert seen['owid_education']
	assert seen['owid_food']
}

// 源 SQLite 的 iso3_code 全为空，导入时靠该映射补齐
fn test_iso2_to_iso3() {
	assert iso2_to_iso3('US') == 'USA'
	assert iso2_to_iso3('CN') == 'CHN'
	// 未收录代码返回空串，由调用方回退
	assert iso2_to_iso3('ZZ') == ''
}
