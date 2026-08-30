# AGENTS.md — world_app

V 语言单体 veb 应用：整合 WorldBank / IMF / 全球市场行情 / OWID 四大数据源，展示世界经济与社会数据。编译为单二进制，运行时依赖 MySQL 8。

## 常用命令

```sh
# 进入项目目录（.v 文件直接在根目录，非子目录）
cd /mnt/h/All_in_One/world_app

# 格式化（.v 文件用 tab 缩进，见 .editorconfig）
v fmt -w .

# 构建
v -o world_app .

# 运行（需 MySQL 已启动，端口 3003）
MYSQL_HOST=127.0.0.1 ./world_app
# 或设 WA_IMPORT_SQLITE=1 首次从 SQLite 导入初始数据

# 测试（database 集成测试需 MySQL，无 DB 时自动跳过）
v test .

# 重启（杀进程用精确匹配，避免误杀 bash 自身）
pkill -x world_app   # 正确
pkill -f world_app   # 错误：会杀掉当前会话

# 临时快速启动 + 冒烟（含 HTTP 测试）
./_tmp_launch.sh
```

## OWID 数据导入（Our World in Data）

OWID 数据来自 [Our World in Data](https://ourworldindata.org)，包含 16 个 CSV 文件（人口、健康、能源、经济、教育、食品）。**优先从本地 CSV 目录导入**（速度快、无网络依赖），本地无文件时自动从 API 下载。

### 本地 CSV 导入（推荐）

设置 `WA_OWID_CSV_DIR` 环境变量指向本地 CSV 目录：

```sh
# 使用 ../owid-data/data 中的 CSV 文件导入
WA_OWID_CSV_DIR=/mnt/h/All_in_One/owid-data/data MYSQL_HOST=127.0.0.1 ./world_app
```

CSV 文件格式：`entity,code,year,value_column`，其中 `code` 为 ISO3 代码，自动转换为 ISO2 存入 MySQL。

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `WA_OWID_CSV_DIR` | 空 | 本地 OWID CSV 目录路径（如 `/mnt/h/All_in_One/owid-data/data`）；设置后优先从本地导入，否则自动从 API 下载 |
| `WA_SQLITE_PATHS` | 空 | 逗号分隔的 SQLite 文件路径，首次运行时导入初始数据 |
| `MYSQL_HOST/PORT/USER/PASS/DB` | 见 §配置 | MySQL 连接参数 |

### API 下载（备用）

不设置 `WA_OWID_CSV_DIR` 时，首次运行自动从 OWID Chart API 下载 CSV 并导入 MySQL，之后缓存清理。下载使用 30s 超时（`fetch/owid.v` 的 `download_owid_csv`），避免大文件超时失败。

### 数据流程

1. **检查 MySQL**：已有 OWID 数据（source='owid'）→ 跳过导入
2. **有本地 CSV** → 直接导入，无需网络
3. **无本地 CSV** → 从 `ourworldindata.org` 下载 16 个 CSV → 导入 → 清理运行时缓存
4. **数据更新**：`DELETE FROM indicators WHERE source='owid'`，重启重新导入

### 数据映射

| CSV 文件 | 指标 slug | 中文名 | 单位 | CSV 数值列名 |
|----------|-----------|--------|------|-------------|
| population.csv | population | 人口总数 | 人 | population_historical |
| life-expectancy.csv | life-expectancy | 预期寿命 | 岁 | life_expectancy_0 |
| children-per-woman-un.csv | children-per-woman-un | 生育率 | 孩/妇 | fertility_rate__sex_all__age_all__variant_estimates |
| median-age.csv | median-age | 中位年龄 | 岁 | median_age__sex_all__age_all__variant_estimates |
| share-of-population-urban.csv | share-of-population-urban | 城镇化率 | % | share__area_type_urban__data_type_estimates |
| child-mortality.csv | child-mortality | 儿童死亡率 | ‰ | child_mortality_rate |
| maternal-mortality.csv | maternal-mortality | 孕产妇死亡率 | /10万 | mmr |
| share-of-adults-who-smoke.csv | share-of-adults-who-smoke | 吸烟率 | % | tobacco_use_pct_age_std__sex_both_sexes |
| annual-co2-emissions-per-country.csv | annual-co2-emissions-per-country | CO₂排放量 | 吨 | emissions_total |
| co2-emissions-per-capita.csv | co2-emissions-per-capita | 人均CO₂ | 吨 | emissions_total_per_capita |
| share-electricity-renewables.csv | share-electricity-renewables | 可再生电力占比 | % | renewable_share_of_electricity__pct |
| gdp-per-capita-worldbank.csv | gdp-per-capita-worldbank | 人均GDP(PPP) | 国际元 | ny_gdp_pcap_pp_kd |
| mean-years-of-schooling.csv | mean-years-of-schooling | 平均受教育年限 | 年 | mf_youth_and_adults__15_64_years__average_years_of_education |
| meat-supply-per-person.csv | meat-supply-per-person | 人均肉类供给 | 公斤/年 | meat__total__00002943__food_available_for_consumption__0645pc__kilograms_per_year_per_capita |
| food-supply-kcal.csv | food-supply-kcal | 日均热量供给 | 千卡/人/天 | daily_calories |
| prevalence-of-undernourishment.csv | prevalence-of-undernourishment | 营养不足发生率 | % | _2_1_1_prevalence_of_undernourishment__000000000024000__value__006121__percent |

## 环境 / Gotchas

- **MySQL 依赖**：库名 `all_in_one`，用户 `world` / 密码 `world123`。连接参数由环境变量覆盖：`MYSQL_HOST/PORT/USER/PASS/DB`。首次部署需执行 `scripts/mysql_init.sql`（以 root 执行）创建用户与库。
- **veb StaticApp 接口**：`main.v` 中 `App` 的 `static_files`、`static_mime_types`、`enable_markdown_negotiation` 等字段**必须保持 `pub mut:` 且字段名精确匹配**，否则 `/static/*` 全部 404。
- **GBK 编码**：腾讯/新浪行情返回 GBK 字节，`fetch/market.v` 中用 `encoding.iconv.encoding_to_vstring(bytes, 'gbk')` 转 UTF-8。**不要用 `$if encoding.iconv ?` 编译期探测**：`v fmt` 会自动补 import 导致编译失败。
- **change 是 MySQL 保留字**：`market_quotes` 表列名为 `chg` / `chg_pct`（非 `change` / `change_pct`），写 SQL 时注意。
- **SQL 注入防护**：所有查询用 `database.sql_escape()` 转义；搜索 WHERE 中 OR 两侧必须加括号（`database/v` 中已有实现）。
- **ISO3 覆盖有限**：`models.iso2_to_iso3()` 仅 ~80 个国家有映射；未收录的返回空串，调用方自行处理。
- **Flag Emoji 算法**：`models.iso2_to_flag_emoji(iso2)` 使用直接 UTF-8 字节构造（`0xF0 0x9F 0x87 byte(0xA6+offset)`），不要用 `rune().str()` 方式（V 编译器会产生错误码点）。
- **IMF API 经常超时失败**：imf.org 网络不稳定，单次请求约 12s，现在使用 30s 超时 + 重试；日志中常见 `imf: 部分请求失败`，不影响其他数据源。全量抓取（20 国 × 6 数据集）可能耗时 30+ 分钟。**注意**：IMF DataMapper API 响应格式已变更（旧格式 `{"Series":{"Obs":[...]}}` → 新格式 `{"values":{"DATASET":{"ISO2":{"YEAR":value}}}}`），`fetch/imf.v` 的 `fetch_imf_dataset` 已更新解析逻辑。
- **后台抓取调度**：启动即全量一次（worldbank + imf + market/fx/commodity + owid），之后每 10 分钟刷行情/汇率/商品，每 12 小时全量。串行请求，worldbank 80 国 × 19 指标耗时可达 10-15 分钟。
- **`.gitignore` 忽略 `*.js` 和 `*.db`**：`static/js/app.js` 及所有 SQLite 数据库不被 git 跟踪，clone 后不存在属正常。
- **静态文件须显式注册**：新增 CSS/JS 文件需同时在 `App.static_files` map 中注册 URL→路径映射。
- **SQLite 初始导入**：通过 `WA_SQLITE_PATHS=/path/to/a.db,/path/to/b.db` 环境变量指定多个路径（逗号分隔），仅在库为空时生效；不设则完全依赖公开 API。
- **日志**：使用 V 内置 `log` 模块（`database/init_log()` 在 main 启动时调用），日志文件 `world_app.log` 为 UTF-8 编码；若终端显示乱码请用 UTF-8 编辑器打开。
- **浮点数格式化**：所有浮点数值统一使用 `fmt2()` 精确到 2 位小数（V `${v:.2f}` 语法，Python `.2f` 风格）；大数值用 `models.format_large()` 保留 2 位小数加 K/M/B/T 后缀。
- **OWID 数据格式**：CSV 文件第一行为表头 `entity,code,year,value_column`，其中 `code` 为 ISO3 代码，需转换为 ISO2 才能存入 `indicators.country_iso`。转换逻辑参考 `models.iso3_to_iso2()`。空 code 或聚合实体（WLD 等）自动跳过。
- **OWID 数据含未来预测**：部分 CSV 包含至 2100 年的预测数据（如人口、生育率），展示时需注意标注"预测"。
- **OWID 指标代码**：使用 CSV 文件名（不含 `.csv`）作为 `indicators.indicator` 字段值，如 `population`、`life-expectancy`。
- **OWID 特殊实体**：CSV 中包含 `WLD`（世界）、`OWID_HIC`（高收入）等聚合实体，无对应 ISO2 代码，导入时自动跳过。
- **主题切换默认深色**：CSS `:root` 定义深色变量，`[data-theme="light"]` 为浅色；JS 读取 `localStorage` 默认深色，右上角 ☀️/🌙 切换并持久化。
- **CSS 自定义属性完整定义**：`--radius`、`--trans`、`--font` 等所有 `var(--*)` 变量在 `:root` 中集中定义，避免未定义导致样式失效。

## 架构速览

```
main.v          → veb 路由入口（端口 3003），持 App 结构体 + DB 连接
render.v        → HTML 渲染（page_shell / sidebar / overview / wb / imf / market / owid）
models/models.v → 共享数据模型 + all_categories() + iso2_to_iso3 + iso3_to_iso2 + owid_indicators
database/       → MySQL 连接 / 建表 / SQLite→MySQL 导入 / OWID CSV 导入 / 查询接口
fetch/          → worldbank.v / imf.v / market.v / owid.v（含 http_util.v 超时重试）
static/         → css/style.css + js/app.js（编译期嵌入，不依赖磁盘）
```

路由一览：

| 路径 | 说明 |
|------|------|
| `/` | 首页概览（统计卡片 + GDP Top20 图表） |
| `/category/:id` | 分类页（18 个分类，见 `models.all_categories()`） |
| `/country/:iso2` | 国家详情（WorldBank + IMF + OWID 全部指标） |
| `/market/:market` | 行情页（cn/hk/us/index/fx/commodity） |
| `/search?q=` | 搜索 API（国家 + 行情标的 JSON） |
| `/api/stats` | 全局统计 + 最近日志（前端每 5s 轮询） |
| `/api/refresh` | POST 手动触发后台全量抓取 |
| `/api/imf_top` | IMF NGDPD Top20（图表用） |

分类目录（18 个）：

| 分组 | 分类 ID | 说明 |
|------|---------|------|
| 🌍 世界银行 | wb_overview / wb_gdp / wb_social / wb_energy | 国家经济概览 / GDP 与增长 / 社会民生 / 能源与环境 |
| 🏛️ 国际货币基金 | imf_gdp / imf_wEO | IMF GDP 估算 / WEO 经济增长预测 |
| 📈 全球市场 | mk_cn / mk_hk / mk_us / mk_index / mk_fx / mk_commodity | A股 / 港股 / 美股 / 全球指数 / 汇率 / 大宗商品 |
| 📊 OWID 全球数据 | owid_population / owid_health / owid_energy / owid_economy / owid_education / owid_food | 人口 / 健康 / 能源 / 经济 / 教育 / 食品 |

## 双语 / 国际化 (i18n)

界面中英文双语，`locale/locale.v` 是文案唯一来源，新增/修改用户可见文案都应在词典里加 key，不要在 `render.v` / `app.js` 里硬编码字符串。

- **词典**：`locale.zh_dict()` / `locale.en_dict()` 返回 `map[string]string`。`locale.t(lang, key)` 取文案，`locale.tf(lang, key, {'n': ...})` 做 `{name}` 占位符替换（V 与 JS 端占位符语法一致，都是 `{name}`）。
- **缺失 key**：`lookup()` 在目标语言缺失时回退另一语言，再回退到 key 本身；但**翻译缺失不会报错**，所以中英文必须各自补齐，不要只加一边。
- **语言判定**（`main.v` 的 `resolve_lang`）：`?lang=zh|en` 查询参数 > `lang` cookie > 默认中文。带 `?lang=` 的请求会回写 cookie（1 年），之后无参访问保持语言。切换仅靠侧栏 `?lang=` 链接触发整页服务端重渲染。
- **前端注入**：`render.v` 的 `page_shell` 会把 `window.LANG`（'zh'/'en'）和 `window.I18N`（完整双语 JSON，由 `locale.json_bundle()` 生成）注入 `<script>`。`app.js` 的 `t(key, params)` 读这两个全局变量，供搜索结果、刷新状态等动态文案使用。
- **主题切换**是独立功能（深色/浅色，右上角 ☀️/🌙 按钮），与语言无关，不要混淆。
- **新增用户可见字符串**：在 `zh_dict()` 和 `en_dict()` 同时加 key（含 JS 客户端用到的 `js_*` key），否则另一种语言会显示中文或裸 key。

## 前端 JS 暴露给内联 script 的全局函数

`window.t(key, params)` — i18n 取文案（读 `window.LANG` / `window.I18N`）
`window.renderBarChart(id, labels, values, label)` — Chart.js 柱状图
`window.renderImfTop(canvasId)` — IMF GDP 异步加载图表
`window.triggerRefresh()` — 手动触发刷新
`window.doSideSearch()` — 侧栏搜索

修改这些函数名时需同步更新 `render.v` / `app.js` 中的调用。

## 验证流程

改代码后：`v fmt -w .` → `v -o world_app .` → 启动 MySQL → `./_tmp_launch.sh` 检查各路由 HTTP 状态码与 `world_app.log` 尾部日志。

参考文档：`README.md`（详细架构）、`AGENT.md`（原始需求）。

## 最近重要修复

### 2026-08-30
- **IMF API 格式变更修复**：`fetch/imf.v` 的 `fetch_imf_dataset` 更新解析逻辑，适配新版 DataMapper API 响应格式 `{"values":{"DATASET":{"ISO2":{"YEAR":value}}}}`。
- **OWID 下载超时修复**：`fetch/owid.v` 的 `download_owid_csv` 改用 `http_get_timeout` 30s 超时，避免大 CSV 文件下载失败。
- **默认深色主题**：CSS `:root` 定义深色变量，JS 默认读取 localStorage 为深色，右上角 ☀️/🌙 切换并持久化。
- **CSS 变量完整定义**：在 `:root` 集中定义 `--radius`、`--trans`、`--font`、`--transition-theme`、`--ease` 等所有自定义属性，修复样式缺失问题。
