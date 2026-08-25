# AGENTS.md — world_app

V 语言单体 veb 应用：整合 WorldBank / IMF / 全球市场行情三大数据源，展示世界经济与社会数据。编译为单二进制，运行时依赖 MySQL 8。

## 常用命令

```sh
# 进入项目目录（.v 文件直接在根目录，非子目录）
cd /mnt/h/All_in_One/world_app

# 格式化（.v 文件用 tab 缩进，见 .editorconfig）
v fmt -w .

# 构建
v -o world_app .

# 运行（需 MySQL 已启动，端口 8080）
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

## 环境 / Gotchas

- **MySQL 依赖**：库名 `all_in_one`，用户 `world` / 密码 `world123`。连接参数由环境变量覆盖：`MYSQL_HOST/PORT/USER/PASS/DB`。首次部署需执行 `scripts/mysql_init.sql`（以 root 执行）创建用户与库。
- **veb StaticApp 接口**：`main.v` 中 `App` 的 `static_files`、`static_mime_types`、`enable_markdown_negotiation` 等字段**必须保持 `pub mut:` 且字段名精确匹配**，否则 `/static/*` 全部 404。
- **GBK 编码**：腾讯/新浪行情返回 GBK 字节，`fetch/market.v` 中用 `encoding.iconv.encoding_to_vstring(bytes, 'gbk')` 转 UTF-8。**不要用 `$if encoding.iconv ?` 编译期探测**：`v fmt` 会自动补 import 导致编译失败。
- **change 是 MySQL 保留字**：`market_quotes` 表列名为 `chg` / `chg_pct`（非 `change` / `change_pct`），写 SQL 时注意。
- **SQL 注入防护**：所有查询用 `database.sql_escape()` 转义；搜索 WHERE 中 OR 两侧必须加括号（`database/v` 中已有实现）。
- **ISO3 覆盖有限**：`models.iso2_to_iso3()` 仅 ~80 个国家有映射；未收录的返回空串，调用方自行处理。
- **Flag Emoji 算法**：`models.iso2_to_flag_emoji(iso2)` 使用直接 UTF-8 字节构造（`0xF0 0x9F 0x87 byte(0xA6+offset)`），不要用 `rune().str()` 方式（V 编译器会产生错误码点）。
- **IMF API 经常超时失败**：imf.org 网络不稳定，单次请求约 12s，现在使用 30s 超时 + 重试；日志中常见 `imf: 部分请求失败`，不影响其他数据源。全量抓取（20 国 × 6 数据集）可能耗时 30+ 分钟。
- **后台抓取调度**：启动即全量一次（worldbank + imf + market/fx/commodity），之后每 10 分钟刷行情/汇率/商品，每 12 小时全量。串行请求，worldbank 80 国 × 19 指标耗时可达 10-15 分钟。
- **`.gitignore` 忽略 `*.js` 和 `*.db`**：`static/js/app.js` 及所有 SQLite 数据库不被 git 跟踪，clone 后不存在属正常。
- **静态文件须显式注册**：新增 CSS/JS 文件需同时在 `App.static_files` map 中注册 URL→路径映射。
- **SQLite 初始导入**：通过 `WA_SQLITE_PATHS=/path/to/a.db,/path/to/b.db` 环境变量指定多个路径（逗号分隔），仅在库为空时生效；不设则完全依赖公开 API。
- **日志位置**：程序目录下 `world_app.log`，带时间戳；stderr 同步输出。

## 架构速览

```
main.v          → veb 路由入口（端口 8080），持 App 结构体 + DB 连接
render.v        → HTML 渲染（page_shell / sidebar / overview / wb / imf / market）
models/models.v → 共享数据模型 + all_categories() + iso2_to_iso3 + format_large
database/       → MySQL 连接 / 建表 / SQLite→MySQL 导入 / 查询接口
fetch/          → worldbank.v / imf.v / market.v（含 http_util.v 超时重试）
static/         → css/style.css + js/app.js（编译期嵌入，不依赖磁盘）
```

路由一览：

| 路径 | 说明 |
|------|------|
| `/` | 首页概览（统计卡片 + GDP Top10 图表） |
| `/category/:id` | 分类页（12 个分类，见 `models.all_categories()`） |
| `/country/:iso2` | 国家详情（该国全部指标） |
| `/market/:market` | 行情页（cn/hk/us/index/fx/commodity） |
| `/search?q=` | 搜索 API（国家 + 行情标的 JSON） |
| `/api/stats` | 全局统计 + 最近日志（前端每 5s 轮询） |
| `/api/refresh` | POST 手动触发后台全量抓取 |
| `/api/imf_top` | IMF NGDPD Top10（图表用） |

## 前端 JS 暴露给内联 script 的全局函数

`window.renderBarChart(id, labels, values, label)` — Chart.js 柱状图
`window.renderImfTop(canvasId)` — IMF GDP 异步加载图表
`window.triggerRefresh()` — 手动触发刷新
`window.doSideSearch()` — 侧栏搜索

修改这些函数名时需同步更新 render.v 中的内联 `<script>` 调用。

## 验证流程

改代码后：`v fmt -w .` → `v -o world_app .` → 启动 MySQL → `./_tmp_launch.sh` 检查各路由 HTTP 状态码与 `world_app.log` 尾部日志。

参考文档：`README.md`（详细架构）、`AGENT.md`（原始需求）。
