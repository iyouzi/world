#!/bin/bash
# 临时重启脚本：重新编译 + 重启 + 1 次 curl 冒烟
set +e
cd "$(dirname "$0")"
pkill -x world_app 2>/dev/null
sleep 1
echo "=== build ==="
v -o world_app . 2>&1 | tail -8
sleep 1
MYSQL_HOST=127.0.0.1 nohup ./world_app > /tmp/wa_boot.log 2>&1 &
SRV=$!
echo "SRV=$SRV"
sleep 8
echo "--- curl health ---"
for p in / /market/cn /country/US /category/imf_wEO /static/js/app.js; do
  code=$(curl -s -m 6 -o /dev/null -w "%{http_code}" "http://127.0.0.1:3003$p")
  echo "HTTP $code  $p"
done
echo "--- alive? ---"
kill -0 $SRV 2>/dev/null && echo "ALIVE ($SRV)" || echo "DEAD"
echo "--- last log ---"
tail -15 world_app.log 2>/dev/null || true
