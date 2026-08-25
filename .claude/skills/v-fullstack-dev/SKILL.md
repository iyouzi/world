---
name: v-fullstack-dev
description: V 语言全栈 Web 应用开发技能，专为 world_app 类项目设计。Use when working on V language web projects with veb framework, MySQL/SQLite databases, HTTP fetch with timeout/retry, GBK encoding, SQL injection prevention, or when the user mentions "V 编译错误"、"veb 路由"、"GBK 乱码"、"行情抓取失败"、"SQL 注入"、"AGENTS.md"、"世界数据平台"、"web app"。
---

# V 全栈 Web 开发 — world_app 项目规范

## 重要：编译期陷阱

### `encoding.iconv` 编译期探测会破坏构建

```v
// ❌ 绝对禁止：v fmt 自动补 import 后 $if 块失效，编译报错
$if encoding.iconv ? {
    return iconv.encoding_to_vstring(bytes, 'gbk') or { bytes.bytestr() }
} else {
    return bytes.bytestr()
}

// ✅ 正确写法：直接 import，错误时回退
import encoding.iconv
fn gbk_to_utf8(bytes []u8) string {
    return iconv.encoding_to_vstring(bytes, 'gbk') or { bytes.bytestr() }
}
```

`v fmt -w .` 会自动补 `import encoding.iconv`，但 `$if` 块中的探测在补 import 前执行，导致编译失败。

### `change` 是 MySQL 保留字

表列名用 `chg` / `chg_pct`（见 `market_quotes` 表），SQL 语句中严禁直接使用 `change` 作为列名。

### `veb.StaticApp` 接口字段必须是 `pub mut:`

```v
pub struct App {
    veb.Context
pub mut:
    static_files                  map[string]string  // 必须 pub mut:，否则 /static/* 全部 404
    static_mime_types             map[string]string
    enable_markdown_negotiation   bool
    // ...其他 veb 接口字段
    db                            database.Database
    refresh_running               bool
}
```

修改字段时绝不能把 `pub mut:` 去掉，也不能改名。

## 项目结构速查

```
world_app/
├── main.v            # 入口 + veb 路由 + 后台刷新调度
├── render.v          # HTML 渲染（page_shell / sidebar / overview / market）
├── models/models.v   # 数据模型 + all_categories() + iso2_to_iso3
├── database/database.v  # MySQL 连接 + 建表 + SQLite→MySQL 导入 + 查询接口
├── fetch/
│   ├── http_util.v   # 统一 HTTP GET（10s 超时 + 指数退避重试）
│   ├── worldbank.v   # api.worldbank.org 抓取
│   ├── imf.v         # imf.org datamapper API 抓取
│   └── market.v      # 腾讯→新浪→网易降级链 + 外汇 + 大宗商品
├── static/
│   ├── css/style.css # CSS 变量双主题（dark/light via data-theme）
│   └── js/app.js     # 搜索/刷新/轮询/Chart.js
├── scripts/
│   ├── build.sh
│   ├── run_server.sh
│   └── mysql_init.sql
└── AGENTS.md         # 运行时提示与 gotchas
```

## veb 路由开发规范

### 静态文件注册

新增 CSS/JS 文件后，必须同时做两件事：

1. 在 `main.v` 的 `release_asset()` + `app.static_files` map 中注册 URL→路径映射
2. 在 `render.v` 的 `page_shell()` `<head>` 中加 `<link>` 或 `<script>` 标签

不注册则 404，无报错。

### 内联 script 暴露全局函数

`render.v` 中通过内联 `<script>` 调用 JS 函数时，这些函数必须在 `app.js` 末尾通过 `window.xxx = fn` 显式暴露：

```js
window.renderBarChart = renderBarChart;
window.triggerRefresh = triggerRefresh;
window.doSideSearch = doSideSearch;
```

改名时必须同步更新两处。

### 安全转义三层函数

| 函数 | 用途 | 调用场景 |
|------|------|---------|
| `h(s)` | HTML 文本/属性值 | `${h(x)}` 嵌入 `<body>` 文本或 `class="..."` |
| `js_str(s)` | JS 字符串内容 | 内联 `<script>` 中的 `'${js_str(x)}'` |
| `a(s)` | URL path 片段 | `href="/country/${a(iso2)}"` |

`render_test.v` 有完整的 XSS 测试用例，改转义逻辑后必须跑 `v test render_test.v`。

## 数据库操作规范

### SQL 拼接安全

```v
// ✅ 所有用户输入必须经 sql_escape()
safe := database.sql_escape(search)
q := "WHERE name LIKE '%${safe}%'"

// sql_escape() 转义顺序：\ → \' → \" → \n → \r → \x00
// 反斜杠必须最先转义，否则 ' → \' 中的 \ 会被再次转义
```

### 时间字段格式

日志时间用手工拼接 `YYYY-MM-DD HH:MM:SS`（无 T/Z），兼容 MySQL DATETIME：

```v
fn format_datetime(t time.Time) string {
    return '${t.year:04d}-${int(t.month):02d}-${t.day:02d} ${t.hour:02d}:${t.minute:02d}:${t.second:02d}'
}
```

### MySQL 环境变量覆盖

```sh
MYSQL_HOST=127.0.0.1 MYSQL_PORT=3306 MYSQL_USER=world MYSQL_PASS=world123 MYSQL_DB=all_in_one ./world_app
```

连接超时无法在 `mysql.Config` 中设置（V 0.5.x 不支持），依赖 `fetch/http_util.v` 的 HTTP 层超时。

## HTTP 抓取规范

### 统一使用 `fetch/http_util.v` 的 `http_get(url, referer)`

- 超时：dial 5s / read 10s / write 10s
- 重试：最多 3 次指数退避（200ms → 400ms → 800ms）
- 429：额外 sleep 2s 再重试
- 5xx：按退避重试
- 4xx（非 429）：直接 error，不重试

新增数据源时**不要绕过** `http_get` 直接用 `net.http.fetch`，否则失去超时和重试保护。

### IMF API 已知不稳定

imf.org 在 WSL 网络环境下经常超时，`fetch_imf` 返回全部失败是常见情况，不影响其他数据源。日志标记为 `failed` 即可，前端显示空数据 + 提示文字。

## 后台刷新调度

```
启动 → 全量一次（worldbank + imf + market/fx/commodity）
     → 每 10 分钟：行情 + 汇率 + 商品（3 个高频源）
     → 每 12 小时（72 周期）：全量
```

所有抓取任务由 `run_fetch(label, fn() !int)` 统一包装，错误不 panics 只写日志。新增数据源时在此函数中添加对应调用。

```v
fn run_fetch(label string, f fn () !int) (bool, int) {
    n := f() or {
        database.log_line('background', '${label} 失败: ${err}')
        return false, 0
    }
    return true, n
}
```

## 构建与测试

```sh
cd world_app
v fmt -w .           # 格式化（.v 用 tab 缩进）
v -o world_app .     # 构建
v test .             # 全部测试（database 集成测试需 MySQL，无 DB 时自动跳过）
pkill -x world_app   # 杀进程（精确匹配，不用 -f）
```

`render_test.v` 覆盖 XSS 防护、边栏位置、meta 完整性；`models_test.v` / `database_test.v` / `fetch_test.v` 各有专注点，改相关模块后优先跑对应测试文件。

## 国家 / 指标 / 行情标的扩展

- **新增国家**：在 `fetch/worldbank.v` 的 `country_names()` 和 `iso3_to_iso2()` 中各加一对；在 `models/models.v` 的 `iso2_to_iso3()` 中补充 iso3 映射
- **新增 WorldBank 指标**：在 `wb_indicators()` 中追加
- **新增 IMF 数据集**：在 `imf_datasets()` 中追加（需确认 IMF Data Mapper API 支持）
- **新增行情标的**：在 `fetch/market.v` 的 `default_symbols()` 中追加（market 字段取值 cn/hk/us/index/fx/commodity）
- **新增外汇对**：在 `fx_pairs()` 中追加（symbol 格式：`USDCNY`/`EURUSD`）
- **新增大宗商品**：在 `commodity_defs()` 中追加（symbol 格式：`hf_GC`，新浪期货代码）
- **新增分类**：在 `models.all_categories()` 中追加，并在 `render.v` 的 `main_content_html()` match 分支中处理
