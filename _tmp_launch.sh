#!/bin/bash
# 临时启动脚本：在 WSL 中执行，避免 Windows PowerShell 变量解析
set +e
cd "$(dirname "$0")"
LOG=world_data.log

# 杀掉旧进程
pkill -x world_data 2>/dev/null
sleep 1

# 重新编译确保二进制最新
echo "=== build ==="
v -o world_data . 2>&1 | tail -5

# 启动
MYSQL_HOST=127.0.0.1 nohup ./world_data > /tmp/wa_boot.log 2>&1 &
SRV=$!
echo "SRV_PID=$SRV"
sleep 12

echo "=== /tmp/wa_boot.log tail ==="
tail -30 /tmp/wa_boot.log 2>/dev/null
echo ""
echo "=== world_data.log tail ==="
tail -30 "$LOG" 2>/dev/null
echo ""
echo "=== HTTP smoke (curl) ==="
for p in / /api/stats /category/wb_overview /country/US /market/cn /market/fx /market/commodity /category/imf_wEO /static/css/style.css; do
  code=$(curl -s -m 8 -o /dev/null -w "%{http_code}" "http://127.0.0.1:3003$p" 2>/dev/null)
  size=$(curl -s -m 8 -o /tmp/wa_body.html -w "%{size_download}" "http://127.0.0.1:3003$p" 2>/dev/null)
  echo "HTTP $code  size=$size  $p"
done

echo ""
echo "=== server alive? ==="
kill -0 $SRV 2>/dev/null && echo "ALIVE (pid=$SRV)" || echo "DEAD"
