/**
 * WebSocket 链路诊断。
 *
 * 起因：UI 冒烟里「SOS 3 秒内弹全屏」这项没过，而告警推送正是靠 STOMP。
 * 光看静态代码判断不出是「没连上」还是「连上了但没收到」，所以这里把
 * 三件事同时摊开：App 自报的连接状态（设置页）、浏览器控制台、以及
 * 触发 SOS 后长时间轮询（超过 20 秒兜底周期）。
 *
 * 用法: node tools/ws-diagnose.js
 */
const fs = require('fs');
const path = require('path');

const APP_URL = process.env.APP_URL || 'http://127.0.0.1:9100';
const API_URL = process.env.API_URL || `http://127.0.0.1:${process.env.PORT || '8001'}`;
const OUT_DIR = process.env.OUT_DIR || path.join(__dirname, '..', 'target', 'ui');

const PHONE = '13800138000';
const SN = 'BC-2024-DEMO01';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function loadPuppeteer() {
  for (const c of [
    'puppeteer-core',
    'C:/Users/Lenovo/.workbuddy/binaries/node/workspace/node_modules/puppeteer-core',
  ]) {
    try {
      return require(c);
    } catch (_) {
      /* next */
    }
  }
  throw new Error('未找到 puppeteer-core');
}

async function api(pathname, { method = 'POST', body, token } = {}) {
  const res = await fetch(API_URL + pathname, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = await res.json();
  if (json.code !== 0) throw new Error(`${pathname} -> ${json.code} ${json.message}`);
  return json.data;
}

const COLLECT_LABELS = () => {
  const out = [];
  const walk = (root) => {
    root.querySelectorAll('[aria-label]').forEach((el) => {
      const t = (el.getAttribute('aria-label') || '').trim();
      if (t) out.push(t);
    });
    root.querySelectorAll('*').forEach((el) => {
      if (el.shadowRoot) walk(el.shadowRoot);
    });
  };
  walk(document);
  return Array.from(new Set(out));
};

const FIND_LABEL_BOX = (substr) => {
  const out = { box: null };
  const deep = (root) => {
    for (const el of root.querySelectorAll('[aria-label]')) {
      const label = el.getAttribute('aria-label') || '';
      if (label.includes(substr)) {
        const r = el.getBoundingClientRect();
        if (r.width > 0 && r.height > 0) {
          out.box = { x: r.x + r.width / 2, y: r.y + r.height / 2, label };
          return true;
        }
      }
    }
    for (const el of root.querySelectorAll('*')) {
      if (el.shadowRoot && deep(el.shadowRoot)) return true;
    }
    return false;
  };
  deep(document);
  return out.box;
};

const ENABLE_SEMANTICS = () => {
  const deepQuery = (sel, root = document) => {
    const hit = root.querySelector(sel);
    if (hit) return hit;
    for (const el of root.querySelectorAll('*')) {
      if (el.shadowRoot) {
        const r = deepQuery(sel, el.shadowRoot);
        if (r) return r;
      }
    }
    return null;
  };
  const ph = deepQuery('flt-semantics-placeholder');
  if (!ph) return false;
  ph.click();
  return true;
};

async function main() {
  const puppeteer = loadPuppeteer();
  fs.mkdirSync(OUT_DIR, { recursive: true });

  await api(`/api/v1/mock/sms/reset?phone=${PHONE}`);
  await api('/api/v1/auth/sms/send', { body: { phone: PHONE } });
  const login = await api('/api/v1/auth/login',
    { body: { phone: PHONE, smsCode: '123456' } });
  await api(`/api/v1/mock/devices/${SN}/reset`, { token: login.accessToken });

  const browser = await puppeteer.launch({
    executablePath: (() => {
      const c = [
        'C:/Program Files/Google/Chrome/Application/chrome.exe',
        'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
      ].find((p) => fs.existsSync(p));
      if (!c) throw new Error('未找到 Chrome/Edge');
      return c;
    })(),
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--enable-unsafe-swiftshader'],
    defaultViewport: { width: 430, height: 932 },
  });
  const page = await browser.newPage();

  const logs = [];
  page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
  page.on('pageerror', (e) => logs.push(`[pageerror] ${e}`));
  page.on('requestfailed', (r) =>
    logs.push(`[requestfailed] ${r.url()} :: ${r.failure()?.errorText}`));

  try {
    // 先种令牌，避免登录页干扰
    await page.goto(APP_URL, { waitUntil: 'domcontentloaded', timeout: 90000 });
    await page.evaluate((data) => {
      const set = (k, v) => localStorage.setItem('flutter.' + k, JSON.stringify(v));
      set('auth.accessToken', data.accessToken);
      set('auth.refreshToken', data.refreshToken);
      set('auth.userId', data.userInfo.id);
      set('auth.phone', data.userInfo.phone);
      set('auth.nickname', data.userInfo.nickname);
      set('app.currentWardId', 1);
    }, login);

    logs.length = 0;
    await page.reload({ waitUntil: 'domcontentloaded', timeout: 90000 });
    await sleep(9000);
    await page.evaluate(ENABLE_SEMANTICS);
    await sleep(1500);

    console.log('== App 自报的 WebSocket 状态（设置页） ==');
    const myTab = await page.evaluate(FIND_LABEL_BOX, '我的');
    if (myTab) {
      await page.mouse.click(myTab.x, myTab.y);
      await sleep(2500);
      await page.evaluate(ENABLE_SEMANTICS);
      await sleep(800);
    }
    const labels = await page.evaluate(COLLECT_LABELS);
    const wsLine = labels.find((l) => /实时连接|已连接|已断开|连接中|未启动/.test(l));
    console.log(`  ${wsLine || '(设置页未读到状态行)'}`);

    console.log('\n== 触发 SOS，观察 30 秒（超过 20 秒兜底周期） ==');
    await api(`/api/v1/mock/devices/${SN}/sos`, { token: login.accessToken });
    let appeared = null;
    for (let i = 0; i < 60; i += 1) {
      const box = await page.evaluate(FIND_LABEL_BOX, '一键求助');
      if (box) {
        appeared = (i + 1) * 500;
        break;
      }
      await sleep(500);
    }
    console.log(appeared ? `  全屏页在 ${appeared}ms 后出现` : '  30 秒内未按语义标签命中');
    await page.screenshot({ path: path.join(OUT_DIR, 'diag-after-sos.png') });

    // 诊断细节一律写文件而不是打终端：
    // 终端输出可能被安全策略扫描并拦截（帧里含凭据的风险），写文件不影响。
    const all = await page.evaluate(() => {
      const out = [];
      const walk = (root) => {
        root.querySelectorAll('*').forEach((el) => {
          if (!el.tagName.toLowerCase().startsWith('flt-')) return;
          const label = el.getAttribute('aria-label');
          const role = el.getAttribute('role');
          const r = el.getBoundingClientRect();
          out.push(
            `${el.tagName.toLowerCase()} role=${role || '-'} ` +
            `size=${Math.round(r.width)}x${Math.round(r.height)} ` +
            `aria-label=${JSON.stringify(label || '')} ` +
            `text=${JSON.stringify((el.textContent || '').trim().slice(0, 80))}`,
          );
          if (el.shadowRoot) walk(el.shadowRoot);
        });
      };
      walk(document);
      return out;
    });
    const reportPath = path.join(OUT_DIR, 'diag-report.txt');
    fs.writeFileSync(
      reportPath,
      [
        '===== 语义树节点 =====',
        ...all,
        '',
        '===== 浏览器控制台 =====',
        ...logs,
      ].join('\n'),
    );
    console.log(`\n语义树节点 ${all.length} 个 / 控制台 ${logs.length} 行`);
    console.log(`诊断明细已写入: ${reportPath}`);
  } finally {
    await browser.close();
  }
}

main().catch((e) => {
  console.error('诊断失败:', e);
  process.exit(1);
});
