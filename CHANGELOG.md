# CHANGELOG

## 2026-09-01 — v0.3.1

主要改动

- 修复：移除编译期对被 .gitignore 忽略静态文件的强依赖，改为运行时加载 static/，并提供 scripts/generate_static.sh 供 CI/发布在编译前注入静态产物。
- 安全：在数据库层新增 exec_params(query, params...) 并逐步替换原有字符串拼接写入（示例已替换于 fetch/worldbank, fetch/imf, fetch/market, database/import）。降低 SQL 注入风险；建议后续替换为驱动原生 prepared statements。
- 修复：models.iso3_to_iso2 回退逻辑修正，修复相关测试。
- CI/开发：新增示例 GitHub Actions CI（格式化/测试/生成静态/构建）、README 补充说明。

验证

- 在 WSL 环境下运行：`v fmt && v test` 全部通过（5/5），`v -o world_data` 构建成功（若干未使用变量 warning）。

后续建议

1. 用数据库驱动的 prepared statements 替换 exec_params。
2. 在 CI 中注入真实前端构建产物以恢复编译期嵌入（可选）。
3. 扩展 exec_params 的安全测试覆盖，加入注入用例。

PR: changrui-world-data-review → 已合并到 master
