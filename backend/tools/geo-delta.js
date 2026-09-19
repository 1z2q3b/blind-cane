#!/usr/bin/env node
/**
 * 计算两个位置点之间的地面距离（米），用于校验模拟器步长是否合理。
 *
 * 用法：node tools/geo-delta.js '{"lng":113.78,"lat":34.74}' '{"lng":113.781,"lat":34.741}'
 *
 * 用等距圆柱投影（equirectangular）而不是 Haversine：模拟器的步长本来就是在
 * 这个投影下生成的，用同一套近似才能得到可比的数值，否则误差会互相抵消或放大。
 * 距离在公里级以下时该投影误差可忽略。
 */
const [a, b] = process.argv.slice(2);
if (!a || !b) {
  process.stdout.write('n/a');
  process.exit(0);
}
let from, to;
try {
  from = JSON.parse(a);
  to = JSON.parse(b);
} catch (e) {
  process.stdout.write('n/a');
  process.exit(0);
}
if (from.lat == null || from.lng == null || to.lat == null || to.lng == null) {
  process.stdout.write('n/a');
  process.exit(0);
}
const METERS_PER_DEGREE_LAT = 111320;
const dy = (to.lat - from.lat) * METERS_PER_DEGREE_LAT;
const dx = (to.lng - from.lng) * METERS_PER_DEGREE_LAT * Math.cos((from.lat * Math.PI) / 180);
process.stdout.write(Math.hypot(dx, dy).toFixed(2));
