#!/usr/bin/env node
/**
 * 从 stdin 读取 JSON，按点号路径取值并打印（联调/验证脚本用）。
 *
 * 为什么不直接在 bash 里用 `node -e` 拼字符串：JSON 里的双引号会破坏
 * shell 字符串转义，而空值又会拼出非法 JS。独立脚本 + argv 传参最稳。
 *
 * 用法：echo '{"data":{"id":9}}' | node tools/json-get.js data.id
 * 取值失败/路径不存在时输出空串，退出码 0（便于 bash 直接比较）
 */
let raw = '';
process.stdin.on('data', (chunk) => (raw += chunk));
process.stdin.on('end', () => {
  const path = process.argv[2] || '';
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    process.stdout.write('');
    return;
  }
  const value = path.split('.').reduce((acc, key) => (acc == null ? undefined : acc[key]), parsed);
  process.stdout.write(value == null ? '' : String(value));
});
