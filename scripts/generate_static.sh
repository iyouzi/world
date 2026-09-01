#!/usr/bin/env bash
set -euo pipefail
# generate_static.sh
# 用于在 CI 或发布时生成或拷贝 static/js/app.js 到仓库工作树，以保证单二进制编译/发布时前端文件可用。
# 使用：
# 1) CI 提供预构建的 JS： export STATIC_APP_JS=/path/to/app.js && ./scripts/generate_static.sh
# 2) 未提供时，生成一个最小 shim（功能有限，建议在 CI 上传入完整构建产物）

OUT_DIR="$(pwd)/static/js"
mkdir -p "$OUT_DIR"

if [ -n "${STATIC_APP_JS:-}" ] && [ -f "$STATIC_APP_JS" ]; then
  echo "Copying provided STATIC_APP_JS -> $OUT_DIR/app.js"
  cp "$STATIC_APP_JS" "$OUT_DIR/app.js"
else
  echo "No STATIC_APP_JS provided; writing minimal placeholder to $OUT_DIR/app.js"
  cat > "$OUT_DIR/app.js" <<'JS'
// Minimal generated placeholder for app.js
(function(){
  window.t = function(k){ return k };
  window.triggerRefresh = function(){ fetch('/api/refresh',{method:'POST'}).catch(()=>{}); };
  window.doSideSearch = function(){ var e=document.getElementById('side-search-input'); if(e) window.location.href='/search?q='+encodeURIComponent(e.value||''); };
  window.renderBarChart = function(id,l,v,label) { console.warn('Chart rendering not available (placeholder)'); };
  window.renderImfTop = function(id) { console.warn('IMF chart placeholder'); };
  window.showToast = function(m){ console.log('TOAST',m); };
})();
JS
fi

echo "Generated: $OUT_DIR/app.js"
