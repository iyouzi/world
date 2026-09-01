# World App 软件文档 / World App Documentation

> 版本 0.3.0 · V 0.5.x + veb · MySQL 8
>
> World App 是一个单体 Web 应用，把 WorldBank、IMF、world_market、Our World in Data 四个独立数据源整合为一个系统，用数据和图表展示世界的经济、社会与市场行情。
>
> **English:** Version 0.3.0 · V 0.5.x + veb · MySQL 8. World App is a monolithic web application that unifies four independent data sources — WorldBank, IMF, world_market, and Our World in Data — into a single system, presenting the world's economy, society, and market quotes through data and charts.

## 1. 项目简介 / Project Introduction

- **目标**：全面展示我们这个世界的方方面面数据——国家宏观经济指标（世界银行口径）、GDP 估算与预测（IMF 口径）、全球股票/指数实时行情、全球发展指标（OWID 口径，含历史数据与未来预测）。
- **形态**：单二进制 veb 服务端渲染应用，页面右侧为分类边栏（目录 + 搜索），顶部显示全局统计，主内容区按分类展示表格与 Chart.js 图表。支持深浅主题切换、响应式布局、Toast 操作反馈。
- **原始需求**：见仓库根目录 `AGENT.md`。

> **English:**
> - **Goal:** Comprehensively present data on every aspect of our world — national macroeconomic indicators (World Bank caliber), GDP estimates and forecasts (IMF caliber), real-time global stock/index quotes, and global development indicators (OWID caliber, including historical data and future projections).
> - **Form:** A single-binary veb server-rendered application. The right side of the page is a categorized sidebar (table of contents + search); the top shows global statistics; the main content area displays tables and Chart.js charts by category. Supports dark/light theme switching, responsive layout, and Toast feedback.
> - **Original requirements:** See `AGENT.md` in the repository root.

### 核心特性 / Core Features

| 特性 | 说明 |
|------|------|
| 四源合一 | WorldBank 指标、IMF GDP、腾讯/新浪/网易行情、OWID 全球发展数据统一入库 MySQL |
| SQLite 导入 | 启动时自动把示例项目的 SQLite 库作为初始数据导入（仅库空时一次） |
| OWID CSV 导入 | 优先从本地 CSV 目录导入（设置 `WA_OWID_CSV_DIR`），无本地文件时自动从 OWID Chart API 下载。16 个指标（人口、健康、能源、经济、教育、食品），含历史与预测数据 |
| 后台自动刷新 | 独立 goroutine 定时抓取并写库；启动即全量（7 个数据源），之后每 10 分钟行情/汇率/商品，每 12 小时全量。前端轮询自动感知更新状态 |
| 鲁棒的网络请求 | `fetch/http_util.v` 统一封装：read/write 超时 10s、4 次（含初始）指数退避重试、429 限速等待、5xx 可重试、4xx 直接失败 |
| 分类边栏 | 右侧栏含全部 18 个分类入口和关键词搜索框；CSS `order:2` 实现右对齐 |
| UI/UX 优化 | 深色/浅色双主题、移动端汉堡菜单、Toast 通知、统计卡片渐变、行情 Tabs、国家详情展示 |
| 日志与可观测 | V `log` 模块写入 `world_data.log`（UTF-8）+ stderr；`fetch_logs` 表记录每个源 success/partial/failed；启动抓取调度不吞错误；所有浮点数精确到 2 位小数 |
| REST API | `/api/stats`、`/api/refresh`、`/api/imf_top`、`/search` 供前端轮询与集成 |

| Feature | Description |
|---------|-------------|
| Four sources unified | WorldBank indicators, IMF GDP, Tencent/Sina/NetEase quotes, and OWID global development data are all stored into MySQL |
| SQLite import | On startup, automatically imports the sample project's SQLite database as initial data (only once when the DB is empty) |
| OWID CSV import | Prioritizes local CSV import (set `WA_OWID_CSV_DIR`); falls back to OWID Chart API download. 16 indicators (population, health, energy, economy, education, food), with historical and projection data |
| Background auto-refresh | A dedicated goroutine periodically fetches and writes to the DB; a full fetch (7 sources) runs at startup, then every 10 minutes for quotes/FX/commodities and every 12 hours for a full refresh. The frontend polls to detect update status |
| Robust network requests | `fetch/http_util.v` uniformly wraps: 10s read/write timeout, 4 attempts (incl. initial) with exponential backoff retry, 429 rate-limit wait, 5xx retriable, 4xx immediate failure |
| Categorized sidebar | The right sidebar contains all 18 category entries and a keyword search box; CSS `order:2` achieves right alignment |
| UI/UX optimizations | Dark/light dual themes, mobile hamburger menu, Toast notifications, gradient stat cards, quote Tabs, country detail view |
| Logging & observability | V `log` module writes to `world_data.log` (UTF-8) + stderr; `fetch_logs` table records success/partial/failed per source; startup fetch scheduler never swallows errors; all floats formatted to 2 decimal places |
| REST API | `/api/stats`, `/api/refresh`, `/api/imf_top`, `/search` for frontend polling and integration |

## 2. 技术栈 / Tech Stack

- **语言**：V (vlang.io)，模块 `os`、`time`、`veb`、`net.http`、`db.mysql`、`db.sqlite`
- **数据库**：MySQL 8.0+（库名 `all_in_one`，utf8mb4）
- **前端**：服务端拼装 HTML（`render.v`）+ 原生 JS（`static/js/app.js`）+ CSS；图表用 CDN 引入的 Chart.js 4
- **运行环境**：WSL（Linux），监听 `0.0.0.0:3003`

> **English:**
> - **Language:** V (vlang.io), modules `os`, `time`, `veb`, `net.http`, `db.mysql`, `db.sqlite`
> - **Database:** MySQL 8.0+ (database `all_in_one`, utf8mb4)
> - **Frontend:** Server-assembled HTML (`render.v`) + vanilla JS (`static/js/app.js`) + CSS; charts via Chart.js 4 loaded from CDN
> - **Runtime:** WSL (Linux), listening on `0.0.0.0:3003`

## 2.5 环境变量 / Environment Variables

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `MYSQL_HOST` | 127.0.0.1 | MySQL 主机 |
| `MYSQL_PORT` | 3306 | MySQL 端口 |
| `MYSQL_USER` | world | MySQL 用户 |
| `MYSQL_PASS` | world123 | MySQL 密码 |
| `MYSQL_DB` | all_in_one | 数据库名 |
| `WA_OWID_CSV_DIR` | 空 | 本地 OWID CSV 目录（如 `/mnt/h/All_in_One/owid-data/data`）；设置后优先本地导入 |
| `WA_SQLITE_PATHS` | 空 | 逗号分隔的 SQLite 路径，首次运行时导入初始数据 |
| `WA_NO_BROWSER` | 空 | 设置任意值（如 `1`）则禁用启动后自动打开浏览器，适合服务器/无桌面环境 |

> **English:**
> | Variable | Default | Description |
> |----------|---------|-------------|
> | `MYSQL_HOST` | 127.0.0.1 | MySQL host |
> | `MYSQL_PORT` | 3306 | MySQL port |
> | `MYSQL_USER` | world | MySQL user |
> | `MYSQL_PASS` | world123 | MySQL password |
> | `MYSQL_DB` | all_in_one | Database name |
> | `WA_OWID_CSV_DIR` | empty | Local OWID CSV directory (e.g. `/mnt/h/All_in_One/owid-data/data`); prioritizes local import when set |
> | `WA_SQLITE_PATHS` | empty | Comma-separated SQLite paths for initial data import on first run |
> | `WA_NO_BROWSER` | empty | Set any value (e.g. `1`) to disable auto-opening a browser after startup; for server / headless environments |

## 3. 目录结构 / Directory Structure

```
world_data/
├── main.v              # 入口：veb 应用、路由、App 结构体、后台刷新调度
├── render.v            # HTML 渲染（页面外壳、边栏、各分类内容片段）
├── models/models.v     # 共享数据模型 + 分类目录定义 + 数值格式化
├── database/database.v # MySQL 连接(Database 结构体)、建表、SQLite 导入、OWID CSV 导入、查询接口
├── fetch/
│   ├── worldbank.v     # 世界银行指标抓取（api.worldbank.org）
│   ├── imf.v           # IMF GDP 抓取（imf.org datamapper API）
│   ├── market.v        # 行情抓取（腾讯→新浪→网易 降级链）
│   ├── owid.v          # OWID 数据下载与导入（ourworldindata.org）
│   └── http_util.v     # HTTP 超时重试封装
├── static/
│   ├── css/style.css   # 页面样式
│   └── js/app.js       # 搜索、手动刷新、状态轮询、Chart.js 渲染
└── scripts（仓库根）
    ├── build.sh        # 构建 world_data
    ├── run_server.sh   # 启动 + 冒烟测试各路由
    ├── mysql_init.sql  # 创建用户 world/world123 与库 all_in_one
    └── diag.sh         # 连接诊断脚本
```

> **English:**
> ```
> world_data/
> ├── main.v              # Entry point: veb app, routes, App struct, background refresh scheduler
> ├── render.v            # HTML rendering (page shell, sidebar, per-category content fragments)
> ├── models/models.v     # Shared data models + category definitions + number formatting
> ├── database/database.v # MySQL connection (Database struct), table creation, SQLite import, OWID CSV import, query interfaces
> ├── fetch/
> │   ├── worldbank.v     # World Bank indicator fetching (api.worldbank.org)
> │   ├── imf.v           # IMF GDP fetching (imf.org datamapper API)
> │   ├── market.v        # Quote fetching (Tencent → Sina → NetEase fallback chain)
> │   ├── owid.v          # OWID data download & import (ourworldindata.org)
> │   └── http_util.v     # HTTP timeout & retry wrapper
> ├── static/
> │   ├── css/style.css   # Page styles
> │   └── js/app.js       # Search, manual refresh, status polling, Chart.js rendering
> └── scripts (repo root)
>     ├── build.sh        # Build world_data
>     ├── run_server.sh   # Launch + smoke test each route
>     ├── mysql_init.sql  # Create user world/world123 and database all_in_one
>     └── diag.sh         # Connection diagnostics script
> ```

## 4. 架构与数据流 / Architecture & Data Flow

```
                    ┌─────────────────────────────────────┐
                    │            App (main.v)             │
                    │  db: Database    refresh_running    │
                    └───┬───────────┬────────────────┬────┘
        HTTP 请求(3003) │           │ 查询/写入      │ go 后台刷新
                        ▼           ▼                ▼
                   veb 路由    database.Database   fetch 模块
                   render.v    (MySQL all_in_one)  worldbank/imf/market
                        │                              │
                        ▼                              ▼
                   浏览器(HTML+JS)              外部 API / 写回 MySQL
```

> **English:**
> ```
>                    ┌─────────────────────────────────────┐
>                    │            App (main.v)             │
>                    │  db: Database    refresh_running    │
>                    └───┬───────────┬────────────────┬────┘
>        HTTP req (3003) │           │ query/write    │ go background refresh
>                        ▼           ▼                ▼
>                   veb routes  database.Database  fetch modules
>                   render.v    (MySQL all_in_one) worldbank/imf/market
>                        │                              │
>                        ▼                              ▼
>                 Browser (HTML+JS)            External API / write back to MySQL
> ```

启动流程（`fn main()`）：

1. 构造 `App`，调用 `app.db.connect()` —— 连接 MySQL；`ensure_database()` / `init_schema()` 先查 `information_schema` 判断库/表是否已存在，**已存在则跳过并打出明确日志（"数据库已存在，跳过创建" / "表已存在，跳过创建"）**，仅缺失时才 `CREATE`，避免每次启动无谓重建；
2. `app.db.backfill_iso3()` —— 回填历史导入遗留的空 iso3（源 SQLite 的 iso3_code 全为空）；
3. `app.import_existing_sqlite()` —— **仅当库为空时**执行一次 SQLite 导入；库中已有数据则跳过；
4. `go app.background_refresh()` —— 启动即全量抓取一次，之后每 10 分钟刷新行情/汇率/商品，每 12 小时全量一次。所有 HTTP 请求带 10s 超时与低重试（`fetch/http_util.v`），无外网时快速失败并写日志，不会阻塞启动；
5. `veb.run_at[App, Context]` 在 3003 端口启动服务（多线程模式）。

> **English — Startup flow (`fn main()`):**
> 1. Construct `App` and call `app.db.connect()` — connect to MySQL; `ensure_database()` / `init_schema()` first query `information_schema` to check whether the database/tables already exist, and **skip with an explicit log line ("数据库已存在，跳过创建" / "表已存在，跳过创建") when present**, issuing `CREATE` only for what is missing, avoiding needless rebuilds on every startup;
> 2. `app.db.backfill_iso3()` — backfill empty iso3 left by historical imports (the source SQLite's iso3_code is all empty);
> 3. `app.import_existing_sqlite()` — runs the SQLite import **only once when the DB is empty**; skips if data already exists;
> 4. `go app.background_refresh()` — a full fetch runs once at startup, then every 10 minutes for quotes/FX/commodities and every 12 hours for a full refresh. All HTTP requests carry a 10s timeout with low retry (`fetch/http_util.v`); without internet it fails fast and logs, never blocking startup;
> 5. `veb.run_at[App, Context]` starts the service on port 3003 (multi-threaded mode).

### 日志 / Logging

- 运行期日志由 `database.log_line(tag, msg)` 统一写入**程序目录下的 `world_data.log`**（UTF-8 编码，V `log` 模块输出），并同步输出 stderr；
- 抓取成败同时写入 MySQL `fetch_logs` 表（经 `/api/stats` 暴露最近 5 条）；
- 全部抓取源在成功/部分/失败时都会记录：`success` / `partial` / `failed` 状态 + 条数 + 耗时；
- 所有浮点数统一使用 `fmt2()` 精确到 2 位小数（`${v:.2f}` 格式），大数值用 `format_large()` 保留 2 位小数加 K/M/B/T 后缀。

> **English:**
> - Runtime logs are uniformly written by `database.log_line(tag, msg)` to **`world_data.log` in the program directory** (UTF-8, via V `log` module) and simultaneously output to stderr;
> - Fetch success/failure is also written to the MySQL `fetch_logs` table (exposed via `/api/stats`, latest 5 entries);
> - Every fetch source records on success/partial/failure: `success` / `partial` / `failed` status + record count + duration;
> - All floats use `fmt2()` for exactly 2 decimal places (`${v:.2f}` format); large numbers use `format_large()` with 2 decimals plus K/M/B/T suffix.

### SQLite 初始导入 / SQLite Initial Import

候选路径列表硬编码在 `App.import_existing_sqlite()`（同时包含 `/mnt/h/...` 与 Windows 盘符两种写法）：

- `worldbank/worldbank_info/wb_info/data.db` → 表 `countries` + `data_cache` → 写入 `countries` / `indicators(source='worldbank')`
- `world_market/world_market_shows/world_market.db` → 表 `stocks` → 写入 `market_quotes`
- 不存在的文件自动跳过；插入使用 `INSERT IGNORE` / `ON DUPLICATE KEY UPDATE`，可重复执行
- 仅在 countries 与 market_quotes 均为空时导入；清空这两张表可触发重新导入
- 导入时用 `models.iso2_to_iso3()` 补齐 iso3（源 SQLite 该列全为空）

> **English:** The candidate path list is hard-coded in `App.import_existing_sqlite()` (with both `/mnt/h/...` and Windows drive-letter forms):
> - `worldbank/worldbank_info/wb_info/data.db` → tables `countries` + `data_cache` → written to `countries` / `indicators(source='worldbank')`
> - `world_market/world_market_shows/world_market.db` → table `stocks` → written to `market_quotes`
> - Missing files are skipped automatically; inserts use `INSERT IGNORE` / `ON DUPLICATE KEY UPDATE` and are repeatable
> - Imported only when both `countries` and `market_quotes` are empty; clearing these two tables triggers re-import
> - During import, `models.iso2_to_iso3()` fills in iso3 (that column is empty in the source SQLite)

### 行情抓取降级链（fetch/market.v）/ Quote Fetch Fallback Chain (fetch/market.v)

每个标的依次尝试：**腾讯** (`qt.gtimg.cn`) → **新浪** (`hq.sinajs.cn`) → **网易** (`api.money.126.net`)，取首个成功结果写入 `market_quotes`，`source` 记录实际来源。

> **English:** Each symbol is tried in order: **Tencent** (`qt.gtimg.cn`) → **Sina** (`hq.sinajs.cn`) → **NetEase** (`api.money.126.net`); the first successful result is written to `market_quotes`, and `source` records the actual provider used.

### 外汇汇率与大宗商品（fetch/market.v）/ FX Rates & Commodities (fetch/market.v)

- **汇率** (`fetch_fx`, market='fx', source='er-api')：open.er-api.com 免 key 接口，以 USD 为基准换算 USDCNY、EURUSD 等 11 个货币对；
- **大宗商品** (`fetch_commodity`, market='commodity', source='sina-futures')：新浪外盘期货接口（hf_GC 黄金、hf_SI 白银、hf_CL WTI、hf_OIL 布油、hf_NG 天然气、hf_CAD 铜），昨收取昨结算价。

> **English:**
> - **FX rates** (`fetch_fx`, market='fx', source='er-api'): key-free open.er-api.com API, converting 11 pairs such as USDCNY and EURUSD against USD;
> - **Commodities** (`fetch_commodity`, market='commodity', source='sina-futures'): Sina overseas futures API (hf_GC gold, hf_SI silver, hf_CL WTI, hf_OIL Brent, hf_NG natural gas, hf_CAD copper); previous close uses the prior settlement price.

## 5. 模块说明 / Module Reference

### 5.1 main.v

- `struct App`：内嵌 `veb.Context`；静态文件相关字段（`static_files` 等 10 个字段）**必须保持 `pub mut:` 且名称精确匹配 veb 的 `StaticApp` 接口**，否则 `/static/*` 全部 404；业务字段 `db database.Database`、`refresh_running bool` 也在此结构体内（项目不使用任何全局变量）。
- `Database` 连接句柄由 App 持有，所有 DB 访问经 `app.db.*` 方法完成。

> **English:**
> - `struct App`: embeds `veb.Context`; the static-file related fields (`static_files` and 9 others) **must remain `pub mut:` with names exactly matching veb's `StaticApp` interface**, otherwise `/static/*` all return 404; business fields `db database.Database` and `refresh_running bool` also live in this struct (the project uses no global variables).
> - The `Database` connection handle is held by App; all DB access goes through `app.db.*` methods.

路由一览 / Routes overview:

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/` | 首页概览：统计卡片 + GDP Top20 图表 |
| GET | `/category/:id` | 分类页，id 见 §7 分类表 |
| GET | `/country/:iso2` | 国家详情：该国全部指标 |
| GET | `/market/:market` | 行情页，market ∈ cn/hk/us/index |
| GET | `/search?q=` | 搜索 API：国家 + 行情标的 JSON |
| GET | `/api/stats` | 全局统计 + 最近日志 + 是否抓取中（前端每 5s 轮询） |
| POST | `/api/refresh` | 手动触发后台全量抓取 |
| GET | `/api/imf_top` | IMF NGDPD 前 20 名（labels/values 数组，供图表） |

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Home overview: stat cards + GDP Top20 chart |
| GET | `/category/:id` | Category page; id see §7 category table |
| GET | `/country/:iso2` | Country detail: all indicators of that country |
| GET | `/market/:market` | Market page; market ∈ cn/hk/us/index |
| GET | `/search?q=` | Search API: countries + quote symbols as JSON |
| GET | `/api/stats` | Global stats + recent logs + fetching flag (polled by frontend every 5s) |
| POST | `/api/refresh` | Manually trigger a background full fetch |
| GET | `/api/imf_top` | IMF NGDPD top 20 (labels/values arrays for charts) |

### 5.2 database/database.v

- `pub struct Database { db mysql.DB, open bool }`，`connect()` 幂等连接 + 建表；
- `handle()` 暴露底层句柄给 fetch 模块直接执行 SQL；
- `log_fetch()` 记录每次抓取任务到 `fetch_logs`；
- `import_from_sqlite()` 及两个内部函数负责 SQLite→MySQL 迁移；
- 查询接口：`get_countries` / `count_countries` / `get_indicators_for_country` / `get_indicator_top` / `get_world_stats` / `get_world_pop` / `get_market_quotes` / `count_market_quotes` / `recent_logs`。

> **English:**
> - `pub struct Database { db mysql.DB, open bool }`, `connect()` idempotent connect + table creation;
> - `handle()` exposes the raw handle so the fetch module can run SQL directly;
> - `log_fetch()` records each fetch task to `fetch_logs`;
> - `import_from_sqlite()` and two internal functions handle SQLite→MySQL migration;
> - Query interfaces: `get_countries` / `count_countries` / `get_indicators_for_country` / `get_indicator_top` / `get_world_stats` / `get_world_pop` / `get_market_quotes` / `count_market_quotes` / `recent_logs`.

### 5.3 fetch 模块 / fetch Module

| 函数 | 数据源 | 入库位置 |
|------|--------|----------|
| `fetch_worldbank(dbconn, limit)` | api.worldbank.org，36 个常用国家 × 10 个指标 | `countries` + `indicators(source='worldbank')` |
| `fetch_imf(dbconn, limit)` | imf.org datamapper，20 国 × NGDPD/NGDPDPC 多年序列 | `indicators(source='imf')` |
| `fetch_market(dbconn)` | 腾讯/新浪/网易降级链，10 个默认标的 | `market_quotes` |

| Function | Data source | Stored in |
|----------|-------------|-----------|
| `fetch_worldbank(dbconn, limit)` | api.worldbank.org, 36 common countries × 10 indicators | `countries` + `indicators(source='worldbank')` |
| `fetch_imf(dbconn, limit)` | imf.org datamapper, 20 countries × NGDPD/NGDPDPC multi-year series | `indicators(source='imf')` |
| `fetch_market(dbconn)` | Tencent/Sina/NetEase fallback chain, 10 default symbols | `market_quotes` |

注意：本机 V 安装无 `encoding` 模块，GBK 接口的中文标题可能乱码，数值字段不受影响（详见 `fetch/market.v` 中 `gbk_to_utf8` 注释）。

> **English:** Note: the local V installation lacks the `encoding` module, so Chinese titles from GBK interfaces may be garbled while numeric fields are unaffected (see the `gbk_to_utf8` comment in `fetch/market.v`).

### 5.4 render.v 与前端 / render.v & Frontend

- `page_shell()` 输出统一外壳：顶栏（世界 GDP/国家数/平均寿命/更新状态）+ 左内容区 + 右侧栏；
- 分类 id 由 `models.all_categories()` 定义：`wb_overview`、`wb_gdp`、`wb_social`、`wb_energy`、`imf_gdp`、`imf_wEO`、`mk_cn`、`mk_hk`、`mk_us`、`mk_index`；
- `static/js/app.js`：搜索（调 `/search`）、手动刷新按钮（POST `/api/refresh`）、每 5 秒轮询 `/api/stats` 更新顶栏状态、Chart.js 渲染柱状图。

> **English:**
> - `page_shell()` outputs the unified shell: top bar (world GDP / country count / avg life expectancy / update status) + left content area + right sidebar;
> - Category ids are defined by `models.all_categories()`: `wb_overview`, `wb_gdp`, `wb_social`, `wb_energy`, `imf_gdp`, `imf_wEO`, `mk_cn`, `mk_hk`, `mk_us`, `mk_index`;
> - `static/js/app.js`: search (calls `/search`), manual refresh button (POST `/api/refresh`), polls `/api/stats` every 5 seconds to update the top bar status, and renders Chart.js bar charts.

## 6. 数据库设计（MySQL：all_in_one）/ Database Design (MySQL: all_in_one)

### countries — 国家/地区 / countries — Countries/Regions

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AI PK | 自增主键 |
| iso2 | VARCHAR(4) UNIQUE | 两位国家码（如 US/CN） |
| iso3 | VARCHAR(4) | 三位国家码 |
| name | VARCHAR(120) | 名称 |
| region | VARCHAR(80) | 区域 |
| income | VARCHAR(40) | 收入水平 |
| created_at | TIMESTAMP | 创建时间 |

| Column | Type | Description |
|--------|------|-------------|
| id | INT AI PK | Auto-increment primary key |
| iso2 | VARCHAR(4) UNIQUE | Two-letter country code (e.g. US/CN) |
| iso3 | VARCHAR(4) | Three-letter country code |
| name | VARCHAR(120) | Name |
| region | VARCHAR(80) | Region |
| income | VARCHAR(40) | Income level |
| created_at | TIMESTAMP | Creation time |

### indicators — 宏观指标事实表（WorldBank/IMF 通用）/ indicators — Macro Indicator Fact Table (WorldBank/IMF)

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AI PK | 自增主键 |
| source | VARCHAR(20) | `worldbank` / `imf` |
| country_iso | VARCHAR(4) | 关联 iso2 |
| indicator | VARCHAR(40) | 指标代码（如 NY.GDP.MKTP.CD / NGDPD） |
| label | VARCHAR(120) | 展示名 |
| year | INT | 年份 |
| value | DOUBLE | 数值 |
| unit | VARCHAR(20) | 单位 |
| updated_at | TIMESTAMP | 自动更新 |

| Column | Type | Description |
|--------|------|-------------|
| id | INT AI PK | Auto-increment primary key |
| source | VARCHAR(20) | `worldbank` / `imf` |
| country_iso | VARCHAR(4) | References iso2 |
| indicator | VARCHAR(40) | Indicator code (e.g. NY.GDP.MKTP.CD / NGDPD) |
| label | VARCHAR(120) | Display name |
| year | INT | Year |
| value | DOUBLE | Value |
| unit | VARCHAR(20) | Unit |
| updated_at | TIMESTAMP | Auto-updated |

唯一键 `uq_ind(source, country_iso, indicator, year)`；索引按国家、按来源+指标。

> **English:** Unique key `uq_ind(source, country_iso, indicator, year)`; indexes by country and by source+indicator.

### market_quotes — 市场行情 / market_quotes — Market Quotes

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AI PK | 自增主键 |
| symbol | VARCHAR(20) UNIQUE | 标的代码（sh600519/usAAPL…） |
| name | VARCHAR(120) | 名称 |
| market | VARCHAR(10) | cn/hk/us/index/fx/commodity |
| price / prev_close / chg / chg_pct | DOUBLE | 价格、昨收、涨跌、涨跌幅% |
| volume | BIGINT | 成交量 |
| source | VARCHAR(20) | tencent/sina/netease/er-api/sina-futures/sqlite导入等 |
| updated_at | TIMESTAMP | 更新时间 |

| Column | Type | Description |
|--------|------|-------------|
| id | INT AI PK | Auto-increment primary key |
| symbol | VARCHAR(20) UNIQUE | Symbol code (sh600519/usAAPL…) |
| name | VARCHAR(120) | Name |
| market | VARCHAR(10) | cn/hk/us/index/fx/commodity |
| price / prev_close / chg / chg_pct | DOUBLE | price, previous close, change, change % |
| volume | BIGINT | Volume |
| source | VARCHAR(20) | tencent/sina/netease/er-api/sina-futures/sqlite import etc. |
| updated_at | TIMESTAMP | Update time |

### fetch_logs — 抓取任务日志 / fetch_logs — Fetch Task Logs

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AI PK | 自增主键 |
| source / status | VARCHAR(20) | 来源；running/success/failed |
| message | TEXT | 描述 |
| records | INT | 本次记录数 |
| started_at | DATETIME | 开始时间 |
| duration_ms | INT | 耗时毫秒 |

| Column | Type | Description |
|--------|------|-------------|
| id | INT AI PK | Auto-increment primary key |
| source / status | VARCHAR(20) | source; running/success/failed |
| message | TEXT | Description |
| records | INT | Records this run |
| started_at | DATETIME | Start time |
| duration_ms | INT | Duration in ms |

## 7. API 示例 / API Examples

```bash
# 全局统计（前端轮询）
$ curl http://127.0.0.1:3003/api/stats
{"stats":{"total_countries":296,"total_population":0,"total_gdp":2.503234e14,
 "avg_life":0,"last_update":"2026-08-24 04:01:45"},"logs":[],"fetching":false}

# 搜索
$ curl "http://127.0.0.1:3003/search?q=US"
{"countries":[...],"quotes":[...]}

# 手动触发抓取
$ curl -X POST http://127.0.0.1:3003/api/refresh
{"status":"started"}

# IMF GDP Top20（labels=iso2 数组, values=对应值）
$ curl http://127.0.0.1:3003/api/imf_top
{"labels":["US","CN",...],"values":[...]}

# 页面路由
$ curl -o /dev/null -w "%{http_code}" http://127.0.0.1:3003/country/US   # 200
$ curl -o /dev/null -w "%{http_code}" http://127.0.0.1:3003/market/cn    # 200
$ curl -o /dev/null -w "%{http_code}" http://127.0.0.1:3003/category/wb_gdp # 200
```

> **English:**
> ```bash
> # Global stats (polled by frontend)
> $ curl http://127.0.0.1:3003/api/stats
> {"stats":{"total_countries":296,"total_population":0,"total_gdp":2.503234e14,
>  "avg_life":0,"last_update":"2026-08-24 04:01:45"},"logs":[],"fetching":false}
>
> # Search
> $ curl "http://127.0.0.1:3003/search?q=US"
> {"countries":[...],"quotes":[...]}
>
> # Manually trigger a fetch
> $ curl -X POST http://127.0.0.1:3003/api/refresh
> {"status":"started"}
>
> # IMF GDP Top20 (labels=iso2 array, values=corresponding values)
> $ curl http://127.0.0.1:3003/api/imf_top
> {"labels":["US","CN",...],"values":[...]}
>
> # Page routes
> $ curl -o /dev/null -w "%{http_code}" http://127.0.0.1:3003/country/US   # 200
> $ curl -o /dev/null -w "%{http_code}" http://127.0.0.1:3003/market/cn    # 200
> $ curl -o /dev/null -w "%{http_code}" http://127.0.0.1:3003/category/wb_gdp # 200
> ```

## 8. 配置 / Configuration

连接参数均可被环境变量覆盖（`database/config()`）：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| MYSQL_HOST | 127.0.0.1 | 主机 |
| MYSQL_PORT | 3306 | 端口 |
| MYSQL_USER | world | 用户 |
| MYSQL_PASS | world123 | 密码 |
| MYSQL_DB | all_in_one | 库名 |

| Variable | Default | Description |
|----------|---------|-------------|
| MYSQL_HOST | 127.0.0.1 | Host |
| MYSQL_PORT | 3306 | Port |
| MYSQL_USER | world | User |
| MYSQL_PASS | world123 | Password |
| MYSQL_DB | all_in_one | Database name |

首次部署 / First deployment:

```sql
-- 以 root 执行 scripts/mysql_init.sql
SOURCE scripts/mysql_init.sql;   -- 创建 world/world123 用户与 all_in_one 库
```

> **English:**
> ```sql
> -- Run scripts/mysql_init.sql as root
> SOURCE scripts/mysql_init.sql;   -- Create user world/world123 and database all_in_one
> ```

## 9. 构建与运行 / Build & Run

在发布/CI 中会先生成或拷贝前端静态文件（static/js/app.js）再编译，以保证单二进制发布时前端功能可用。本仓库提供 scripts/generate_static.sh：

- 本地快速开发（WSL 推荐）：
```sh
# 在 WSL（Ubuntu）内安装依赖（仅需一次）
sudo apt update && sudo apt install -y build-essential libssl-dev pkg-config
# 生成占位或拷贝前端文件（CI 会在发布时提供完整构建产物）
./scripts/generate_static.sh
# 构建
v -o world_data .
# 格式化
v fmt -w .
# 测试
v test .
# 运行（需 MySQL 已启动）
MYSQL_HOST=127.0.0.1 ./world_data
```

- 在 CI/发布（已添加示例 GitHub Actions 工作流 .github/workflows/ci.yml）中，流程为：checkout → install deps → ./scripts/generate_static.sh（使用 CI 提供的构建产物或生成占位）→ v fmt → v test → v -o world_data → 上传构建产物。

> English (short): Use scripts/generate_static.sh in CI to ensure static/js/app.js exists before building. Prefer building inside WSL or CI where libssl-dev is available. Steps: generate static → v fmt → v test → v -o world_data.

# 本地 Windows 注意
- 在 Windows 原生环境编译需要 OpenSSL 开发头（<openssl/ecdsa.h>）。推荐在 WSL 中构建（apt install libssl-dev）或用 MSYS2 安装 mingw-w64-openssl。

修改代码后的验证顺序：`v fmt -w .` → `v -o world_data .` → 启动 MySQL → `scripts/run_server.sh` 检查各路由 HTTP 状态码与 `world_data/world_data.log` 尾部日志。

> **English:** Verification order after code changes: `v fmt -w .` → `v -o world_data .` → start MySQL → `scripts/run_server.sh` to check each route's HTTP status code and the tail of `world_data/world_data.log`.

## 10. 已知限制与注意事项 / Known Limitations & Notes

1. **行情/汇率/商品依赖外部接口可达性**：任一源不可达时记为 failed/partial 并写日志，不影响其他源与页面。全部外部请求受 `fetch/http_util.v` 超时（read/write 10s）+ 指数退避重试（retry_count=3）保护，无外网时快速失败不挂起。
2. **V 0.5.x `mysql.Config` 不支持超时字段**：`config()` 中无法设置 connection timeout/read_timeout/write_timeout，超时保护依赖 HTTP 层。如需要连接超时，需升级 V 版本或在 MySQL 侧设置 `wait_timeout`。
3. **iso3 覆盖有限**：仅常用 ~47 个国家有 iso2→iso3 映射（`models.iso2_to_iso3`），其余小经济体 iso3 仍为空（源 SQLite 本身缺失）。
4. **大宗商品昨收为近似值**：新浪外盘以"昨结算价"近似昨收，涨跌幅按此计算。
5. **SQL 拼接**：查询使用字符串拼接 + 增强版 `sql_escape()`（转义 `\ ' " \n \r \x00`），搜索 WHERE 条件对 OR 加括号保证优先级；生产化建议改用占位符参数化查询。
6. **静态文件映射是显式的**：新增 CSS/JS 文件需同时在 `App.static_files` map 中注册 URL→路径映射。
7. **`.gitignore` 忽略 `*.js`/`*.db`**：`static/js/app.js` 与所有 SQLite 文件不被 git 跟踪，`world_data.log` 同样不入库。注意：本分支改为在运行时加载静态文件（若存在则释放到 .assets/ 并由服务端提供），因此构建失败的常见原因 `$embed_file` 不再强制要求 `static/js/app.js` 在编译时存在；但为保证前端功能正常，建议在发布前通过构建脚本生成或把 `static/js/app.js` 放回构建环境。
8. **测试**：`v test .` 覆盖四个模块（models 格式化与分类目录、database 转义/配置 + MySQL 集成（无 DB 自动跳过）、fetch 各解析器、render 页面片段）。集成测试需要本地 MySQL 已按 §8 初始化。
9. **V 编译器 unused 误报**：对 map key 变量 + `$interp` 字符串插值场景，V 0.5.x 可能误报 "unused variable"，不影响二进制正确性。

> **English:**
> 1. **Quotes/FX/commodities depend on external reachability**: when any source is unreachable it is logged as failed/partial without affecting other sources or pages. All external requests are protected by `fetch/http_util.v` timeout (read/write 10s) + exponential backoff retry (retry_count=3); without internet it fails fast and does not hang.
> 2. **V 0.5.x `mysql.Config` lacks timeout fields**: `config()` cannot set connection/read/write timeout; timeout protection relies on the HTTP layer. For connection timeouts, upgrade V or set `wait_timeout` on the MySQL side.
> 3. **Limited iso3 coverage**: only ~47 common countries have an iso2→iso3 mapping (`models.iso2_to_iso3`); other small economies still have empty iso3 (missing in the source SQLite itself).
> 4. **Commodity previous close is approximate**: Sina overseas futures approximate previous close with "prior settlement price"; change % is computed against it.
> 5. **SQL concatenation**: queries use string concatenation + an enhanced `sql_escape()` (escaping `\ ' " \n \r \x00`); the search WHERE wraps OR in parentheses to preserve precedence; for production, prefer parameterized placeholder queries.
> 6. **Static file mapping is explicit**: new CSS/JS files must also be registered in the `App.static_files` map (URL → path).
> 7. **`.gitignore` ignores `*.js`/`*.db`**: `static/js/app.js` and all SQLite files are untracked by git, and `world_data.log` is also not committed. Note that `main.v` embeds the frontend JS into the single binary at compile time via `$embed_file('static/js/app.js')`; **that file must exist at build time** — if missing after clone (due to gitignore), regenerate/place `app.js` via the build script or `scripts/`, otherwise `v -o world_data .` fails.
> 8. **Tests**: `v test .` covers four modules (models formatting & category directory, database escaping/config + MySQL integration (auto-skipped without DB), fetch parsers, render page fragments). Integration tests need local MySQL initialized per §8.
> 9. **V compiler unused false positive**: for map key variables + `$interp` string interpolation, V 0.5.x may falsely report "unused variable"; this does not affect binary correctness.

## 11. 最近的重要改动 / Recent Major Changes

### v0.3.0 (2026-08)

- **端口 8080 → 3003**：`veb.run_at(..., port: 3003)`、启动横幅、自动开浏览器 URL，以及 README / AGENTS.md / `_tmp_launch.sh` / `_tmp_restart.sh` 全部同步。
- **Top10 → Top20**：首页 GDP 榜单与 IMF Top 榜单由前 10 名升级为前 20 名（`get_country_gdp_top(20)` / `get_indicator_top('imf','NGDPD',20)`），i18n key 重命名为 `gdp_top20` / `imf_top20`。
- **数据库/表存在时不再新建**：`ensure_database()` / `init_schema()` 改为先查 `information_schema`，库/表已存在则跳过并打出明确日志，不再每次启动都执行 `CREATE`。
- **后台刷新并发互斥**：`main.background_refresh()` 用 `refresh_running` 原子标志 + 互斥锁，`/api/refresh` 与定时任务不会重叠触发，避免重复抓取与写库竞争。
- **新增 `WA_NO_BROWSER`**：服务器/无桌面环境下禁用启动自动打开浏览器。
- **重建 `static/js/app.js`**：搜索、`triggerRefresh()` 加载 Toast、`/api/stats` 状态轮询、主题切换、Chart.js 渲染；编译期由 `$embed_file` 嵌入单二进制。
- **新增 `scripts/`**：`build.sh`、`run_server.sh`、`mysql_init.sql`、`diag.sh`，并配 `_tmp_launch.sh` / `_tmp_restart.sh` 冒烟脚本。
- **WorldBank 抓取去重**：按 iso3 去重（36 国 × 10 指标一次批量 upsert），修正意大利 `iso3=ITA` 映射，消除 `indicators` 表重复写入。
- **行情抓取健壮性**：`fetch_market` 无数据（无外网）时跳过 `replace`，不再把上次价格清零为 0。
- **渲染健壮性**：GDP 图表直接使用数值数组（修复 `map[string]f64` 顺序不确定导致的空图），Top 列表/值缺失时安全降级。
- **SQL 安全**：搜索/插入统一走 `sql_escape()`，market 写入改用参数化 `sql` 块。
- 依赖本地 MySQL 的集成测试与建库脚本补齐，`v fmt` + `v build` 在 WSL 验证通过。

### v0.3.1 (2026-08-30)

- **IMF API 格式变更修复**：`fetch/imf.v` 的 `fetch_imf_dataset` 更新解析逻辑，适配新版 DataMapper API 响应格式 `{"values":{"DATASET":{"ISO2":{"YEAR":value}}}}`。
- **OWID 下载超时修复**：`fetch/owid.v` 的 `download_owid_csv` 改用 `http_get_timeout` 30s 超时，避免大 CSV 文件下载失败。
- **默认深色主题**：CSS `:root` 定义深色变量，JS 默认读取 localStorage 为深色，右上角 ☀️/🌙 切换并持久化。
- **CSS 变量完整定义**：在 `:root` 集中定义 `--radius`、`--trans`、`--font`、`--transition-theme`、`--ease` 等所有自定义属性，修复样式缺失问题。
- **首页 G20+ 主要国家表格**：`render.v` 的 `overview_html` 新增 G20 及全球 48 个主要经济体表格，展示人口、国土面积、GDP、PPP、人均GDP、PPP密度等指标。WorldBank 指标新增 `AG.LND.TOTL.K2`（国土面积）、`NY.GDP.MKTP.PP.CD`（PPP GDP）、`NY.GDP.PCAP.PP.CD`（人均PPP）。

> **English:**
> ### v0.3.1 (2026-08-30)
> - **IMF API format change fix**: Updated `fetch_imf_dataset` in `fetch/imf.v` to parse the new DataMapper API response format `{"values":{"DATASET":{"ISO2":{"YEAR":value}}}}`.
> - **OWID download timeout fix**: Changed `download_owid_csv` in `fetch/owid.v` to use `http_get_timeout` with 30s timeout to avoid large CSV download failures.
> - **Default dark theme**: CSS `:root` defines dark mode variables, JS defaults to dark mode from localStorage, top-right ☀️/🌙 toggle with persistence.
> - **Complete CSS custom properties**: All `var(--*)` variables (`--radius`, `--trans`, `--font`, `--transition-theme`, `--ease`, etc.) now defined in `:root` to prevent missing variable style issues.
> - **Homepage G20+ Major Economies Table**: Added G20 and 48 major global economies table to `overview_html` in `render.v`, showing population, land area, GDP, PPP, GDP per capita, PPP density. WorldBank indicators added: `AG.LND.TOTL.K2` (land area), `NY.GDP.MKTP.PP.CD` (GDP PPP), `NY.GDP.PCAP.PP.CD` (GDP per capita PPP).

> **English:**
> ### v0.3.0 (2026-08)
> - **Port 8080 → 3003**: `veb.run_at(..., port: 3003)`, startup banner, auto-open URL, and README / AGENTS.md / `_tmp_launch.sh` / `_tmp_restart.sh` all updated.
> - **Top10 → Top20**: the home GDP ranking and the IMF top ranking upgraded from top 10 to top 20 (`get_country_gdp_top(20)` / `get_indicator_top('imf','NGDPD',20)`); i18n keys renamed to `gdp_top20` / `imf_top20`.
> - **Skip DB/table creation when they exist**: `ensure_database()` / `init_schema()` now query `information_schema` first and skip with an explicit log line when the database/tables already exist, instead of running `CREATE` on every startup.
> - **Background-refresh concurrency mutex**: `main.background_refresh()` uses a `refresh_running` atomic flag + mutex so `/api/refresh` and the scheduler never overlap, avoiding duplicate fetches and write races.
> - **New `WA_NO_BROWSER`**: disables auto-opening a browser after startup in server / headless environments.
> - **Rebuilt `static/js/app.js`**: search, `triggerRefresh()` loading Toast, `/api/stats` status polling, theme toggle, Chart.js rendering; embedded into the single binary at compile time via `$embed_file`.
> - **New `scripts/`**: `build.sh`, `run_server.sh`, `mysql_init.sql`, `diag.sh`, plus `_tmp_launch.sh` / `_tmp_restart.sh` smoke scripts.
> - **WorldBank de-duplication**: de-duplicated by iso3 (36 countries × 10 indicators in one batched upsert), fixed Italy `iso3=ITA` mapping, eliminating duplicate writes into `indicators`.
> - **Quote fetch robustness**: `fetch_market` skips `replace` when there is no data (no internet) instead of zeroing the previous price.
> - **Render robustness**: the GDP chart now uses the value array directly (fixing the empty chart caused by non-deterministic `map[string]f64` ordering), and Top lists / missing values degrade safely.
> - **SQL safety**: search/insert uniformly go through `sql_escape()`, and market writes now use parameterized `sql` blocks.
> - Integration tests depending on local MySQL and the DB-init script were completed; `v fmt` + `v build` verified under WSL.

### v0.2.0

- **网络请求**：`fetch/http_util.v` 引入 read/write timeout（10s）、retry_count=3、200ms 起指数退避、429 额外等待 2s、5xx 按退避重试、4xx 直接失败、User-Agent。
- **MySQL 连接**：去掉不可用的 `timeout/read_timeout/write_timeout` 字段（V 0.5.x `mysql.Config` 不支持），补注释说明。
- **SQL 安全**：`sql_escape()` 增加反斜杠、双引号、`\r`、`\x00` 转义；搜索 WHERE 条件用括号明确 OR 优先级；市场分类布尔运算改为显式 if 嵌套。
- **日志函数**：`log_line()` 中 `f.close()` 不带 `or {}`（`close` 返回 void）。
- **后台调度**：`main.background_refresh()` 使用 `run_fetch` 统一捕获错误、计数，不再使用硬编码 total 与 `if n := f() {}` 形式吞错误。
- **渲染**：market_meta 返回 (title, sub, icon) 三元组；render_test 对齐断言。
- **前端 UI/UX**：
  - CSS 深浅主题（`data-theme` 切换 + `prefers-color-scheme` 默认）、统计卡渐变阴影、边栏右侧 order、移动设备断点 `@media (max-width: 820px)` 汉堡 + 遮罩。
  - JS 主题切换 localStorage 持久化、`triggerRefresh()` 带 loading Toast、`/api/stats` 轮询更新刷新按钮状态、搜索结果高亮、市场 Tabs 切换与快速跳转。

> **English:**
> - **Network requests**: `fetch/http_util.v` introduces read/write timeout (10s), retry_count=3, exponential backoff starting at 200ms, extra 2s wait on 429, 5xx retried with backoff, 4xx fails immediately, and a User-Agent.
> - **MySQL connection**: removed the unusable `timeout/read_timeout/write_timeout` fields (unsupported by V 0.5.x `mysql.Config`) and added explanatory comments.
> - **SQL safety**: `sql_escape()` now escapes backslash, double quote, `\r`, `\x00`; search WHERE wraps OR in parentheses for clear precedence; market category boolean logic changed to explicit if nesting.
> - **Log function**: `log_line()` calls `f.close()` without `or {}` (`close` returns void).
> - **Background scheduler**: `main.background_refresh()` uses `run_fetch` to uniformly capture errors and count, no longer using a hardcoded total or `if n := f() {}` swallowing errors.
> - **Rendering**: market_meta returns a (title, sub, icon) triple; render_test assertions aligned.
> - **Frontend UI/UX**:
>   - CSS dark/light themes (`data-theme` switch + `prefers-color-scheme` default), gradient/shadow stat cards, sidebar right order, mobile breakpoint `@media (max-width: 820px)` hamburger + overlay.
>   - JS theme switch persisted in localStorage, `triggerRefresh()` with loading Toast, `/api/stats` polling updates the refresh button state, search result highlighting, market Tabs switching and quick jump.

## 12. 相关文档 / Related Docs

- 原始需求：`AGENT.md`
- Agent 协作指引：`AGENTS.md`
- 参考示例：`world_market/world_market_shows/AGENTS.md`、`worldbank/show_worldbank/README.md`、`worldbank/worldbank_info/wb_info/AGENTS-vlang.md`、`IMF_shows/IMF_API/imf_API.md`

> **English:**
> - Original requirements: `AGENT.md`
> - Agent collaboration guide: `AGENTS.md`
> - Reference examples: `world_market/world_market_shows/AGENTS.md`, `worldbank/show_worldbank/README.md`, `worldbank/worldbank_info/wb_info/AGENTS-vlang.md`, `IMF_shows/IMF_API/imf_API.md`
