# World App 软件文档

> 版本 0.2.0 · V 0.5.x + veb · MySQL 8
>
> World App 是一个单体 Web 应用，把 WorldBank、IMF、world_market 三个独立示例整合为一个系统，用数据和图表展示世界的经济、社会与市场行情。

## 1. 项目简介

- **目标**：全面展示我们这个世界的方方面面数据——国家宏观经济指标（世界银行口径）、GDP 估算与预测（IMF 口径）、全球股票/指数实时行情。
- **形态**：单二进制 veb 服务端渲染应用，页面右侧为分类边栏（目录 + 搜索），顶部显示全局统计，主内容区按分类展示表格与 Chart.js 图表。支持深浅主题切换、响应式布局、Toast 操作反馈。
- **原始需求**：见仓库根目录 `AGENT.md`。

### 核心特性

| 特性 | 说明 |
|------|------|
| 三源合一 | WorldBank 指标、IMF GDP、腾讯/新浪/网易行情统一入库 MySQL |
| SQLite 导入 | 启动时自动把示例项目的 SQLite 库作为初始数据导入（仅库空时一次） |
| 后台自动刷新 | 独立 goroutine 定时抓取并写库；启动即全量，之后每 10 分钟行情/汇率/商品，每 12 小时全量。前端轮询自动感知更新状态 |
| 鲁棒的网络请求 | `fetch/http_util.v` 统一封装：read/write 超时 10s、4 次（含初始）指数退避重试、429 限速等待、5xx 可重试、4xx 直接失败 |
| 分类边栏 | 右侧栏含全部 10 个分类入口和关键词搜索框；CSS `order:2` 实现右对齐 |
| UI/UX 优化 | 深色/浅色双主题、移动端汉堡菜单、Toast 通知、统计卡片渐变、行情 Tabs、国家详情展示 |
| 日志与可观测 | `world_app.log` 文件 + stderr；`fetch_logs` 表记录每个源 success/partial/failed；启动抓取调度不吞错误 |
| REST API | `/api/stats`、`/api/refresh`、`/api/imf_top`、`/search` 供前端轮询与集成 |

## 2. 技术栈

- **语言**：V (vlang.io)，模块 `os`、`time`、`veb`、`net.http`、`db.mysql`、`db.sqlite`
- **数据库**：MySQL 8.0+（库名 `all_in_one`，utf8mb4）
- **前端**：服务端拼装 HTML（`render.v`）+ 原生 JS（`static/js/app.js`）+ CSS；图表用 CDN 引入的 Chart.js 4
- **运行环境**：WSL（Linux），监听 `0.0.0.0:8080`

## 3. 目录结构

```
world_app/
├── main.v              # 入口：veb 应用、路由、App 结构体、后台刷新调度
├── render.v            # HTML 渲染（页面外壳、边栏、各分类内容片段）
├── models/models.v     # 共享数据模型 + 分类目录定义 + 数值格式化
├── database/database.v # MySQL 连接(Database 结构体)、建表、SQLite 导入、查询接口
├── fetch/
│   ├── worldbank.v     # 世界银行指标抓取（api.worldbank.org）
│   ├── imf.v           # IMF GDP 抓取（imf.org datamapper API）
│   └── market.v        # 行情抓取（腾讯→新浪→网易 降级链）
├── static/
│   ├── css/style.css   # 页面样式
│   └── js/app.js       # 搜索、手动刷新、状态轮询、Chart.js 渲染
└── scripts（仓库根）
    ├── build.sh        # 构建 world_app
    ├── run_server.sh   # 启动 + 冒烟测试各路由
    ├── mysql_init.sql  # 创建用户 world/world123 与库 all_in_one
    └── diag.sh         # 连接诊断脚本
```

## 4. 架构与数据流

```
                    ┌─────────────────────────────────────┐
                    │            App (main.v)             │
                    │  db: Database    refresh_running    │
                    └───┬───────────┬────────────────┬────┘
        HTTP 请求(8080) │           │ 查询/写入      │ go 后台刷新
                        ▼           ▼                ▼
                   veb 路由    database.Database   fetch 模块
                   render.v    (MySQL all_in_one)  worldbank/imf/market
                        │                              │
                        ▼                              ▼
                   浏览器(HTML+JS)              外部 API / 写回 MySQL
```

启动流程（`fn main()`）：

1. 构造 `App`，调用 `app.db.connect()` —— 连接 MySQL 并建表（幂等 `CREATE TABLE IF NOT EXISTS`）；
2. `app.db.backfill_iso3()` —— 回填历史导入遗留的空 iso3（源 SQLite 的 iso3_code 全为空）；
3. `app.import_existing_sqlite()` —— **仅当库为空时**执行一次 SQLite 导入；库中已有数据则跳过；
4. `go app.background_refresh()` —— 启动即全量抓取一次，之后每 10 分钟刷新行情/汇率/商品，每 12 小时全量一次。所有 HTTP 请求带 10s 超时与低重试（`fetch/http_util.v`），无外网时快速失败并写日志，不会阻塞启动；
5. `veb.run_at[App, Context]` 在 8080 端口启动服务（多线程模式）。

### 日志

- 运行期日志由 `database.log_line(tag, msg)` 统一写入**程序目录下的 `world_app.log`**（带时间戳），并同步输出 stderr；
- 抓取成败同时写入 MySQL `fetch_logs` 表（经 `/api/stats` 暴露最近 5 条）；
- 全部抓取源在成功/部分/失败时都会记录：`success` / `partial` / `failed` 状态 + 条数 + 耗时。

### SQLite 初始导入

候选路径列表硬编码在 `App.import_existing_sqlite()`（同时包含 `/mnt/h/...` 与 Windows 盘符两种写法）：

- `worldbank/worldbank_info/wb_info/data.db` → 表 `countries` + `data_cache` → 写入 `countries` / `indicators(source='worldbank')`
- `world_market/world_market_shows/world_market.db` → 表 `stocks` → 写入 `market_quotes`
- 不存在的文件自动跳过；插入使用 `INSERT IGNORE` / `ON DUPLICATE KEY UPDATE`，可重复执行
- 仅在 countries 与 market_quotes 均为空时导入；清空这两张表可触发重新导入
- 导入时用 `models.iso2_to_iso3()` 补齐 iso3（源 SQLite 该列全为空）

### 行情抓取降级链（fetch/market.v）

每个标的依次尝试：**腾讯** (`qt.gtimg.cn`) → **新浪** (`hq.sinajs.cn`) → **网易** (`api.money.126.net`)，取首个成功结果写入 `market_quotes`，`source` 记录实际来源。

### 外汇汇率与大宗商品（fetch/market.v）

- **汇率** (`fetch_fx`, market='fx', source='er-api')：open.er-api.com 免 key 接口，以 USD 为基准换算 USDCNY、EURUSD 等 11 个货币对；
- **大宗商品** (`fetch_commodity`, market='commodity', source='sina-futures')：新浪外盘期货接口（hf_GC 黄金、hf_SI 白银、hf_CL WTI、hf_OIL 布油、hf_NG 天然气、hf_CAD 铜），昨收取昨结算价。

## 5. 模块说明

### 5.1 main.v

- `struct App`：内嵌 `veb.Context`；静态文件相关字段（`static_files` 等 10 个字段）**必须保持 `pub mut:` 且名称精确匹配 veb 的 `StaticApp` 接口**，否则 `/static/*` 全部 404；业务字段 `db database.Database`、`refresh_running bool` 也在此结构体内（项目不使用任何全局变量）。
- `Database` 连接句柄由 App 持有，所有 DB 访问经 `app.db.*` 方法完成。

路由一览：

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/` | 首页概览：统计卡片 + GDP Top10 图表 |
| GET | `/category/:id` | 分类页，id 见 §7 分类表 |
| GET | `/country/:iso2` | 国家详情：该国全部指标 |
| GET | `/market/:market` | 行情页，market ∈ cn/hk/us/index |
| GET | `/search?q=` | 搜索 API：国家 + 行情标的 JSON |
| GET | `/api/stats` | 全局统计 + 最近日志 + 是否抓取中（前端每 5s 轮询） |
| POST | `/api/refresh` | 手动触发后台全量抓取 |
| GET | `/api/imf_top` | IMF NGDPD 前 10 名（labels/values 数组，供图表） |

### 5.2 database/database.v

- `pub struct Database { db mysql.DB, open bool }`，`connect()` 幂等连接 + 建表；
- `handle()` 暴露底层句柄给 fetch 模块直接执行 SQL；
- `log_fetch()` 记录每次抓取任务到 `fetch_logs`；
- `import_from_sqlite()` 及两个内部函数负责 SQLite→MySQL 迁移；
- 查询接口：`get_countries` / `count_countries` / `get_indicators_for_country` / `get_indicator_top` / `get_world_stats` / `get_world_pop` / `get_market_quotes` / `count_market_quotes` / `recent_logs`。

### 5.3 fetch 模块

| 函数 | 数据源 | 入库位置 |
|------|--------|----------|
| `fetch_worldbank(dbconn, limit)` | api.worldbank.org，36 个常用国家 × 10 个指标 | `countries` + `indicators(source='worldbank')` |
| `fetch_imf(dbconn, limit)` | imf.org datamapper，20 国 × NGDPD/NGDPDPC 多年序列 | `indicators(source='imf')` |
| `fetch_market(dbconn)` | 腾讯/新浪/网易降级链，10 个默认标的 | `market_quotes` |

注意：本机 V 安装无 `encoding` 模块，GBK 接口的中文标题可能乱码，数值字段不受影响（详见 `fetch/market.v` 中 `gbk_to_utf8` 注释）。

### 5.4 render.v 与前端

- `page_shell()` 输出统一外壳：顶栏（世界 GDP/国家数/平均寿命/更新状态）+ 左内容区 + 右侧栏；
- 分类 id 由 `models.all_categories()` 定义：`wb_overview`、`wb_gdp`、`wb_social`、`wb_energy`、`imf_gdp`、`imf_wEO`、`mk_cn`、`mk_hk`、`mk_us`、`mk_index`；
- `static/js/app.js`：搜索（调 `/search`）、手动刷新按钮（POST `/api/refresh`）、每 5 秒轮询 `/api/stats` 更新顶栏状态、Chart.js 渲染柱状图。

## 6. 数据库设计（MySQL：all_in_one）

### countries — 国家/地区

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AI PK | 自增主键 |
| iso2 | VARCHAR(4) UNIQUE | 两位国家码（如 US/CN） |
| iso3 | VARCHAR(4) | 三位国家码 |
| name | VARCHAR(120) | 名称 |
| region | VARCHAR(80) | 区域 |
| income | VARCHAR(40) | 收入水平 |
| created_at | TIMESTAMP | 创建时间 |

### indicators — 宏观指标事实表（WorldBank/IMF 通用）

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

唯一键 `uq_ind(source, country_iso, indicator, year)`；索引按国家、按来源+指标。

### market_quotes — 市场行情

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

### fetch_logs — 抓取任务日志

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INT AI PK | 自增主键 |
| source / status | VARCHAR(20) | 来源；running/success/failed |
| message | TEXT | 描述 |
| records | INT | 本次记录数 |
| started_at | DATETIME | 开始时间 |
| duration_ms | INT | 耗时毫秒 |

## 7. API 示例

```bash
# 全局统计（前端轮询）
$ curl http://127.0.0.1:8080/api/stats
{"stats":{"total_countries":296,"total_population":0,"total_gdp":2.503234e14,
 "avg_life":0,"last_update":"2026-08-24 04:01:45"},"logs":[],"fetching":false}

# 搜索
$ curl "http://127.0.0.1:8080/search?q=US"
{"countries":[...],"quotes":[...]}

# 手动触发抓取
$ curl -X POST http://127.0.0.1:8080/api/refresh
{"status":"started"}

# IMF GDP Top10（labels=iso2 数组, values=对应值）
$ curl http://127.0.0.1:8080/api/imf_top
{"labels":["US","CN",...],"values":[...]}

# 页面路由
$ curl -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/country/US   # 200
$ curl -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/market/cn    # 200
$ curl -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/category/wb_gdp # 200
```

## 8. 配置

连接参数均可被环境变量覆盖（`database/config()`）：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| MYSQL_HOST | 127.0.0.1 | 主机 |
| MYSQL_PORT | 3306 | 端口 |
| MYSQL_USER | world | 用户 |
| MYSQL_PASS | world123 | 密码 |
| MYSQL_DB | all_in_one | 库名 |

首次部署：

```sql
-- 以 root 执行 scripts/mysql_init.sql
SOURCE scripts/mysql_init.sql;   -- 创建 world/world123 用户与 all_in_one 库
```

## 9. 构建与运行

```sh
# 构建（无全局变量，无需 -enable-globals）
cd world_app && v -o world_app .
# 或 ./scripts/build.sh

# 格式化
v fmt -w .

# 运行全部测试（database 集成测试需 MySQL，不可用时自动跳过）
v test .

# 运行（需 MySQL 已启动）
MYSQL_HOST=127.0.0.1 ./world_app
# 浏览器访问 http://localhost:8080

# 启动 + 冒烟测试（/, /api/stats, /category, /country, /market, /static）
./scripts/run_server.sh
```

修改代码后的验证顺序：`v fmt -w .` → `v -o world_app .` → 启动 MySQL → `scripts/run_server.sh` 检查各路由 HTTP 状态码与 `world_app/world_app.log` 尾部日志。

## 10. 已知限制与注意事项

1. **行情/汇率/商品依赖外部接口可达性**：任一源不可达时记为 failed/partial 并写日志，不影响其他源与页面。全部外部请求受 `fetch/http_util.v` 超时（read/write 10s）+ 指数退避重试（retry_count=3）保护，无外网时快速失败不挂起。
2. **V 0.5.x `mysql.Config` 不支持超时字段**：`config()` 中无法设置 connection timeout/read_timeout/write_timeout，超时保护依赖 HTTP 层。如需要连接超时，需升级 V 版本或在 MySQL 侧设置 `wait_timeout`。
3. **iso3 覆盖有限**：仅常用 ~47 个国家有 iso2→iso3 映射（`models.iso2_to_iso3`），其余小经济体 iso3 仍为空（源 SQLite 本身缺失）。
4. **大宗商品昨收为近似值**：新浪外盘以"昨结算价"近似昨收，涨跌幅按此计算。
5. **SQL 拼接**：查询使用字符串拼接 + 增强版 `sql_escape()`（转义 `\ ' " \n \r \x00`），搜索 WHERE 条件对 OR 加括号保证优先级；生产化建议改用占位符参数化查询。
6. **静态文件映射是显式的**：新增 CSS/JS 文件需同时在 `App.static_files` map 中注册 URL→路径映射。
7. **`.gitignore` 忽略 `*.js`/`*.db`**：`static/js/app.js` 与所有 SQLite 文件不被 git 跟踪，clone 后缺失属正常现象。`world_app.log` 同样不入库。
8. **测试**：`v test .` 覆盖四个模块（models 格式化与分类目录、database 转义/配置 + MySQL 集成（无 DB 自动跳过）、fetch 各解析器、render 页面片段）。集成测试需要本地 MySQL 已按 §8 初始化。
9. **V 编译器 unused 误报**：对 map key 变量 + `$interp` 字符串插值场景，V 0.5.x 可能误报 "unused variable"，不影响二进制正确性。

## 11. 最近的重要改动（v0.2.0 版本）

- **网络请求**：`fetch/http_util.v` 引入 read/write timeout（10s）、retry_count=3、200ms 起指数退避、429 额外等待 2s、5xx 按退避重试、4xx 直接失败、User-Agent。
- **MySQL 连接**：去掉不可用的 `timeout/read_timeout/write_timeout` 字段（V 0.5.x `mysql.Config` 不支持），补注释说明。
- **SQL 安全**：`sql_escape()` 增加反斜杠、双引号、`\r`、`\x00` 转义；搜索 WHERE 条件用括号明确 OR 优先级；市场分类布尔运算改为显式 if 嵌套。
- **日志函数**：`log_line()` 中 `f.close()` 不带 `or {}`（`close` 返回 void）。
- **后台调度**：`main.background_refresh()` 使用 `run_fetch` 统一捕获错误、计数，不再使用硬编码 total 与 `if n := f() {}` 形式吞错误。
- **渲染**：market_meta 返回 (title, sub, icon) 三元组；render_test 对齐断言。
- **前端 UI/UX**：
  - CSS 深浅主题（`data-theme` 切换 + `prefers-color-scheme` 默认）、统计卡渐变阴影、边栏右侧 order、移动设备断点 `@media (max-width: 820px)` 汉堡 + 遮罩。
  - JS 主题切换 localStorage 持久化、`triggerRefresh()` 带 loading Toast、`/api/stats` 轮询更新刷新按钮状态、搜索结果高亮、市场 Tabs 切换与快速跳转。

## 12. 相关文档

- 原始需求：`AGENT.md`
- Agent 协作指引：`AGENTS.md`
- 参考示例：`world_market/world_market_shows/AGENTS.md`、`worldbank/show_worldbank/README.md`、`worldbank/worldbank_info/wb_info/AGENTS-vlang.md`、`IMF_shows/IMF_API/imf_API.md`
