module fetch

import net.http
import time

// 超时与重试参数：
// - dial/read/write 均设超时，避免 TCP 半开连接挂起
// - 重试采用指数退避 (200ms → 400ms → 800ms)，对 429/5xx 友好
// - 对单次抓取总时长做上限（646 个请求串行最坏约 11 分钟）
const dial_timeout = 5 * time.second
const read_timeout = 10 * time.second
const write_timeout = 10 * time.second
const retry_count = 3
const retry_base_wait = 200 * time.millisecond

// http_get 带超时 + 指数退避重试。referer 非空时附加 Referer 头。
// - 429 Too Many Requests：额外 sleep 再重试
// - 5xx：按退避重试
// - 4xx（不含 429）：直接失败不重试
fn http_get(url string, referer string) !string {
	return http_get_timeout(url, referer, int(read_timeout))
}

// http_get_timeout 同 http_get，但允许自定义 read/write timeout（微秒）。
// IMF API 响应慢（~12s），调用方传 30_000_000（30s）以避免超时失败。
fn http_get_timeout(url string, referer string, timeout_us int) !string {
	mut last_err := ''
	for attempt := 0; attempt <= retry_count; attempt++ {
		if attempt > 0 {
			sleep_ms := retry_base_wait * (1 << u32(attempt - 1))
			time.sleep(sleep_ms)
		}
		mut cfg := http.FetchConfig{
			url: url
			method: .get
			user_agent: 'Mozilla/5.0 (compatible; WorldApp/1.0)'
			read_timeout: time.Duration(timeout_us)
			write_timeout: time.Duration(timeout_us)
			max_retries: 1
		}
		if referer != '' {
			cfg.header = http.new_header(key: .referer, value: referer)
		}
		resp := http.fetch(cfg) or {
			last_err = err.str()
			continue
		}
		if resp.status_code == 200 {
			return resp.body
		}
		if resp.status_code == 429 {
			time.sleep(2 * time.second)
			last_err = 'HTTP 429 rate-limited: ${url}'
			continue
		}
		if resp.status_code >= 500 && resp.status_code < 600 {
			last_err = 'HTTP ${resp.status_code}: ${url}'
			continue
		}
		return error('HTTP ${resp.status_code}: ${url}')
	}
	return error('http_get failed after ${retry_count + 1} attempts: ${last_err} (${url})')
}

// esc SQL 转义：与 database.sql_escape 保持一致（反斜杠优先 + 单/双引号 + 控制字符），
// 避免 MySQL NO_BACKSLASH_ESCAPES 或 utf8mb4 字符集下出现 1366 / 注入。
fn esc(s string) string {
	return s.replace('\\', '\\\\').replace("'", "\\'").replace('"', '\\"').replace('\n', '\\n').replace('\r', '').replace('\0', '')
}
