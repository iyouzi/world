module fetch

import database
import models
import os
import time

// OWID 数据抓取模块：优先从本地 CSV 目录导入，无本地文件时从 OWID Chart API 下载。
// CSV 格式：entity,code,year,value_column。导入到 indicators 表（source='owid'）。
//
// 环境变量 WA_OWID_CSV_DIR 指定本地 CSV 目录（如 /mnt/h/All_in_One/owid-data/data）。
// 若设置且存在匹配的 CSV 文件则优先使用；否则自动下载并缓存到 .owid_cache/。
// 后续运行若 MySQL 已有 OWID 数据则直接跳过导入。

// owid_cache_dir OWID CSV 运行时缓存目录（API 下载时使用）
const owid_cache_dir = '.owid_cache'

// get_owid_csv_dir 返回本地 OWID CSV 目录（由环境变量控制）
fn get_owid_csv_dir() string {
	return os.getenv('WA_OWID_CSV_DIR')
}

// fetch_owid 导入全部 OWID 指标到 MySQL。
// 优先从本地 CSV 目录读取；若无本地文件或 MySQL 已有数据则跳过。
// 返回成功导入的记录总数。
pub fn fetch_owid(db database.Database) !int {
	existing := db.count_owid_indicators() or { 0 }
	if existing > 0 {
		database.log_line('owid', 'MySQL 已有 ${existing} 条 OWID 数据，跳过导入')
		return 0
	}
	indicators := models.owid_indicators()
	local_dir := get_owid_csv_dir()
	needs_cleanup := local_dir == ''
	if needs_cleanup {
		os.mkdir_all(owid_cache_dir) or {}
	}
	start := time.now()
	mut total := 0
	mut fail := 0
	for ind in indicators {
		mut csv_path := ''
		if local_dir != '' && os.exists('${local_dir}/${ind.slug}.csv') {
			csv_path = '${local_dir}/${ind.slug}.csv'
			database.log_line('owid', '[${ind.slug}] 从本地导入: ${csv_path}')
		} else {
			database.log_line('owid', '[${ind.slug}] 本地无 CSV，从 OWID API 下载...')
			download_owid_csv(ind.slug) or {
				database.log_line('owid', '[${ind.slug}] 下载失败: ${err}')
				fail++
				continue
			}
			csv_path = '${owid_cache_dir}/${ind.slug}.csv'
		}
		count := db.import_owid_csv(csv_path, ind.slug, ind.name_zh, ind.unit, ind.column_name) or {
			database.log_line('owid', '[${ind.slug}] 导入失败: ${err}')
			fail++
			continue
		}
		database.log_line('owid', '[${ind.slug}] ${ind.name_zh}: ${count} 条')
		total += count
	}
	if needs_cleanup {
		cleanup_cache()
	}
	elapsed := int(time.now().unix_milli() - start.unix_milli())
	src_label := if local_dir != '' { '本地' } else { 'API' }
	database.log_line('owid', 'OWID 导入完成 (${src_label}): ${total} 条记录, ${fail} 个失败, ${elapsed}ms')
	return total
}

// download_owid_csv 从 OWID Chart API 下载单个 CSV 文件到运行时缓存。
fn download_owid_csv(slug string) ! {
	url := 'https://ourworldindata.org/grapher/${slug}.csv?csvType=full&useColumnShortNames=true'
	resp := http_get_timeout(url, '', 30_000_000) or { return error('下载失败: ${err}') }
	if resp.len < 50 {
		return error('响应过短，可能无效')
	}
	os.mkdir_all(owid_cache_dir) or {}
	csv_path := '${owid_cache_dir}/${slug}.csv'
	os.write_file(csv_path, resp) or { return error('写入失败: ${err}') }
	database.log_line('owid', '[${slug}] 下载完成: ${resp.len} 字节')
}

// cleanup_cache 清理运行时缓存目录（仅 API 下载路径调用）
fn cleanup_cache() {
	entries := os.ls(owid_cache_dir) or { return }
	for entry in entries {
		if entry.ends_with('.csv') {
			os.rm('${owid_cache_dir}/${entry}') or {}
		}
	}
	os.rmdir(owid_cache_dir) or {}
}
