#!/usr/bin/env bash
# 启动 WorldApp（headless 调试模式：跳过自动打开浏览器）。
# 用法：MYSQL_HOST=127.0.0.1 ./scripts/run_server.sh
set -e
export PATH="$HOME/.local/bin:$PATH"
cd "$(dirname "$0")/.."

export WA_NO_BROWSER="${WA_NO_BROWSER:-1}"
export MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
export MYSQL_PORT="${MYSQL_PORT:-3306}"
export MYSQL_USER="${MYSQL_USER:-world}"
export MYSQL_PASS="${MYSQL_PASS:-world123}"
export MYSQL_DB="${MYSQL_DB:-all_in_one}"

./world_app
