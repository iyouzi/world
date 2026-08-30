#!/usr/bin/env bash
# 编译 WorldApp（请在 WSL / Linux 下执行；Windows 原生需要带 encoding 模块的 V）。
set -e
export PATH="$HOME/.local/bin:$PATH"
cd "$(dirname "$0")/.."
v fmt -w .
v -o world_data .
echo "build ok -> ./world_data"
