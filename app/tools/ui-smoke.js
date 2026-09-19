/**
 * S5 UI 冒烟：用无头 Chrome 真实渲染家属端，验证「能跑起来 + 关键内容真的画出来了」。
 *
 * 为什么要这一步：`flutter analyze` 只能证明语法没问题，单元测试只覆盖纯函数。
 * Riverpod 的 provider 装配错误、路由重定向死循环、首帧异常这类问题只有在真机上
 * 跑起来才会暴露，静态检查一律看不见。
 *
 * 覆盖：
 *   登录页渲染 → 注入令牌自动进首页 → 首页真实数据 → CORS 跨端口直连
 *   → WebSocket 连接状态 → SOS 全屏强提醒（3 秒内）→ 处置后关闭
 *   → 低电量不打扰 → 位置实时变化 → 运行期无未捕获异常
 *
 * 定位方式说明（踩过的坑）：
 *   Flutter web 把界面画在 canvas 上，DOM 里没有可点的元素，只能靠语义树。
 *   而语义树有两个坑：
 *   1. 文本既可能出现在 `aria-label` 也可能出现在 `textContent`，只查一个会漏；
 *   2. 祖先节点会**合并**子孙的文本，按文档顺序取第一个匹配会命中覆盖整屏的
 *      容器节点，点下去点的是屏幕正中间。所以这里改为「取面积最小的匹配节点」。
 *
 * 用法: node tools/ui-smoke.js
 * 环境变量: APP_URL / API_URL / OUT_DIR
 */
const fs = require('fs');
const path = require('path');

const APP_URL = process.env.APP_URL || 'http://127.0.0.1:9100';
const API_URL = process.env.API_URL || `http://127.0.0.1:${process.env.PORT || '8001'}`;
const OUT_DIR = process.env.OUT_DIR || path.join(__dirname, '..', 'target', 'ui');

const CHROME_CANDIDATES = [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
];

const PHONE = '13800138000';
const SMS_CODE = '123456';
const SN = 'BC-2024-DEMO01';
const WARD_ID = 1;

function loadPuppeteer() {
  for (const c of [
    'puppeteer-core',
    'C:/Users/Lenovo/.workbuddy/binaries/node/workspace/node_modules/puppeteer-core',
  ]) {
    try {
      return require(c);
    } catch (_) {
      /* 试下一个 */
    }
  }
  throw new Error('未找到 puppeteer-core，请先在隔离工作区执行 npm install puppeteer-core');
}

function findChrome() {
  const hit = CHROME_CANDIDATES.find((p) => fs.existsSync(p));
  if (!hit) throw new Error('未找到 Chrome/Edge 可执行文件');
  return hit;
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
  if (json.code !== 0) {
    throw new Error(`${pathname} 返回 code=${json.code} message=${json.message}`);
  }
  return json.data;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok, detail });
  console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${name}${detail ? ' — ' + detail : ''}`);
}

/** 采集语义树节点。aria-label 与 textContent 都取，两个来源 Flutter 会二选一。 */
const COLLECT_NODES = () => {
  const out = [];
  const walk = (root) => {
    root.querySelectorAll('flt-semantics').forEach((el) => {
      const label = (el.getAttribute('aria-label') || '').trim();
      const text = (el.textContent || '').trim();
      const value = label || text;
      const r = el.getBoundingClientRect();
      if (value) {
        out.push({ text: value, w: Math.round(r.width), h: Math.round(r.height) });
      }
    });
    root.querySelectorAll('*').forEach((el) => {
      if (el.shadowRoot) walk(el.shadowRoot);
    });
  };
  walk(document);
  return out;
};

/** 找匹配文本的节点中心点。取**面积最小**的匹配节点，避免命中合并了子孙文本的整屏容器。 */
const FIND_BOX = (substr) => {
  const matches = [];
  const walk = (root) => {
    root.querySelectorAll('flt-semantics').forEach((el) => {
      const label = (el.getAttribute('aria-label') || '').trim();
      const text = (el.textContent || '').trim();
      const value = label || text;
      if (!value.includes(substr)) return;
      const r = el.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0) return;
      matches.push({
        x: r.x + r.width / 2,
        y: r.y + r.height / 2,
        area: r.width * r.height,
        label: value.slice(0, 60),
      });
    });
    root.querySelectorAll('*').forEach((el) => {
      if (el.shadowRoot) walk(el.shadowRoot);
    });
  };
  walk(document);
  if (matches.length === 0) return null;
  matches.sort((a, b) => a.area - b.area);
  return matches[0];
};

/** 打开 Flutter 的语义树：默认是关的，页面里有个占位按钮。重复调用是幂等的。 */
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

async function prepareTree(page, settleMs = 900) {
  await page.evaluate(ENABLE_SEMANTICS);
  await sleep(settleMs);
}

async function waitForText(page, substr, timeoutMs) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const box = await page.evaluate(FIND_BOX, substr);
    if (box) return { box, latencyMs: Date.now() - started };
    await sleep(120);
  }
  return null;
}

async function waitForFlutter(page) {
  await page.waitForFunction(
    () => {
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
      return !!deepQuery('flt-glass-pane') || !!deepQuery('flutter-view');
    },
    { timeout: 90000, polling: 500 },
  );
}

async function main() {
  const puppeteer = loadPuppeteer();
  fs.mkdirSync(OUT_DIR, { recursive: true });

  console.log('== 1. 取一对真令牌（走真实登录接口） ==');
  await api(`/api/v1/mock/sms/reset?phone=${PHONE}`);
  await api('/api/v1/auth/sms/send', { body: { phone: PHONE } });
  const login = await api('/api/v1/auth/login',
    { body: { phone: PHONE, smsCode: SMS_CODE } });
  check('登录拿到 accessToken', !!login.accessToken, `user=${login.userInfo.nickname}`);

  // 演示数据复位：留一堆历史待处理告警会让首页角标难看，也让断言失去确定性
  await api(`/api/v1/mock/devices/${SN}/reset`, { token: login.accessToken });
  let cleared = 0;
  for (let round = 0; round < 20; round += 1) {
    const pageOfAlerts = await api(
      `/api/v1/alerts?wardId=${WARD_ID}&status=0&page=1&size=50`,
      { method: 'GET', token: login.accessToken },
    );
    if (!pageOfAlerts.records || pageOfAlerts.records.length === 0) break;
    for (const alert of pageOfAlerts.records) {
      await api(`/api/v1/alerts/${alert.id}/handle`, {
        method: 'PUT',
        token: login.accessToken,
        body: { result: 'RESOLVED', note: 'UI 冒烟前置清理' },
      });
      cleared += 1;
    }
  }
  check('前置：设备复位 + 清空历史待处理告警', true,
    `电量回 85%，处置 ${cleared} 条遗留告警`);

  console.log('== 2. 启动无头 Chrome ==');
  const browser = await puppeteer.launch({
    executablePath: findChrome(),
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu-sandbox',
      '--enable-unsafe-swiftshader',
      '--window-size=430,932',
    ],
    defaultViewport: { width: 430, height: 932, deviceScaleFactor: 1 },
  });
  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', (e) => pageErrors.push(String(e)));
  page.on('console', (m) => {
    if (m.type() === 'error') pageErrors.push(`console: ${m.text()}`);
  });

  try {
    console.log('== 3. 未登录状态应停在登录页 ==');
    await page.goto(APP_URL, { waitUntil: 'domcontentloaded', timeout: 90000 });
    await waitForFlutter(page);
    await sleep(4000);
    await prepareTree(page);
    const loginNodes = await page.evaluate(COLLECT_NODES);
    const loginText = loginNodes.map((n) => n.text).join(' | ');
    await page.screenshot({ path: path.join(OUT_DIR, '01-login.png') });

    check('Flutter 首帧渲染成功', loginNodes.length > 0,
      `语义树节点 ${loginNodes.length} 个`);
    check('登录页出现手机号与验证码输入框',
      loginText.includes('手机号') && loginText.includes('验证码'));
    check('登录页未把用户误判为已登录（路由重定向正确）',
      !loginText.includes('实时位置') && !loginText.includes('快捷操作'));

    console.log('== 4. 注入令牌后应自动进入首页并渲染真实数据 ==');
    await page.evaluate((data) => {
      const set = (k, v) => localStorage.setItem('flutter.' + k, JSON.stringify(v));
      set('auth.accessToken', data.accessToken);
      set('auth.refreshToken', data.refreshToken);
      set('auth.userId', data.userInfo.id);
      set('auth.phone', data.userInfo.phone);
      set('auth.nickname', data.userInfo.nickname);
      set('app.currentWardId', 1);
    }, login);
    await page.reload({ waitUntil: 'domcontentloaded', timeout: 90000 });
    await waitForFlutter(page);
    await sleep(8000);
    await prepareTree(page, 1500);
    const homeNodes = await page.evaluate(COLLECT_NODES);
    const homeText = homeNodes.map((n) => n.text).join(' | ');
    await page.screenshot({ path: path.join(OUT_DIR, '02-home.png') });

    check('注入令牌后跳出登录页', !homeText.includes('获取验证码'));
    check('首页渲染出底部导航', homeText.includes('首页') && homeText.includes('告警'));
    check('首页渲染出被监护人姓名与设备 SN',
      homeText.includes('张老先生') && homeText.includes(SN));
    check('首页渲染出实时位置区块', homeText.includes('实时'));

    console.log('== 5. 页面内验证 CORS 预检真的放行 ==');
    const corsProbe = await page.evaluate(async (api) => {
      try {
        const res = await fetch(api + '/api/v1/auth/sms/send', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ phone: '13800138000' }),
        });
        const json = await res.json();
        return { ok: true, status: res.status, code: json.code };
      } catch (e) {
        return { ok: false, error: String(e) };
      }
    }, API_URL);
    // 短信 60 秒限流会让 code 变成 101xxx，那也说明请求已经打到后端了
    check('浏览器可跨端口直连后端（CORS 生效）', corsProbe.ok,
      corsProbe.ok ? `HTTP ${corsProbe.status} code=${corsProbe.code}` : corsProbe.error);

    console.log('== 6. WebSocket 实时通道应处于已连接 ==');
    const myTab = await page.evaluate(FIND_BOX, '我的');
    if (myTab) {
      await page.mouse.click(myTab.x, myTab.y);
      await sleep(2000);
      await prepareTree(page);
    }
    const settingsNodes = await page.evaluate(COLLECT_NODES);
    const settingsText = settingsNodes.map((n) => n.text).join(' | ');
    check('WebSocket 显示为已连接（位置与告警实时推送）',
      settingsText.includes('已连接'),
      settingsText.includes('已断开') ? '当前显示已断开' : '');

    console.log('== 7. SOS 应在 3 秒内弹出全屏强提醒（验收硬指标） ==');
    // '我已确认' 只存在于全屏页，用它判断不会被列表里的「一键求助」文案干扰
    const beforeSos = await page.evaluate(FIND_BOX, '我已确认');
    check('触发前确认当前没有全屏告警页', !beforeSos);

    const t0 = Date.now();
    await api(`/api/v1/mock/devices/${SN}/sos`, { token: login.accessToken });
    // 不重新 enable 语义树：轮询本身会驱动 Flutter 更新 a11y 树
    let fullscreen = null;
    while (Date.now() - t0 < 8000) {
      fullscreen = await page.evaluate(FIND_BOX, '我已确认');
      if (fullscreen) break;
      await sleep(100);
    }
    const latency = Date.now() - t0;
    check('SOS 触发了全屏强提醒页', !!fullscreen,
      fullscreen ? `耗时 ${latency}ms` : '等待 8 秒未出现');
    check('全屏提醒在 3 秒内弹出（提示词验收标准）',
      !!fullscreen && latency < 3000, `${latency}ms`);
    await sleep(500);
    await page.screenshot({ path: path.join(OUT_DIR, '03-sos-fullscreen.png') });

    const nodesOnAlert = await page.evaluate(COLLECT_NODES);
    const alertText = nodesOnAlert.map((n) => n.text).join(' | ');
    check('全屏页渲染出告警类型与老人姓名',
      alertText.includes('一键求助') && alertText.includes('张老先生'));
    check('全屏页提供一键拨号入口', alertText.includes('立即拨打 120'));
    check('全屏页提供处置入口（已处理 / 误报）',
      alertText.includes('我已确认') && alertText.includes('这是误报'));

    console.log('== 8. 标记误报后全屏页应关闭 ==');
    const dismissBox = await page.evaluate(FIND_BOX, '这是误报');
    if (dismissBox) {
      await page.mouse.click(dismissBox.x, dismissBox.y);
    }
    await sleep(1500);
    const gone = await waitForText(page, '我已确认', 3000);
    check('点击「这是误报」后全屏页关闭', !gone,
      dismissBox
        ? `已点击 (${Math.round(dismissBox.x)},${Math.round(dismissBox.y)})`
        : '未找到按钮');
    await page.screenshot({ path: path.join(OUT_DIR, '04-after-dismiss.png') });

    console.log('== 9. 低电量告警不应打扰（不弹全屏） ==');
    await api(`/api/v1/mock/devices/${SN}/battery?level=15`,
      { token: login.accessToken });
    await sleep(2500);
    const lowBattery = await page.evaluate(FIND_BOX, '我已确认');
    check('低电量不触发全屏强提醒（避免告警骚扰）', !lowBattery);

    console.log('== 10. 模拟器推进的位置应能被界面感知 ==');
    // 第 6 步切到了「我的」，坐标只在首页，先切回去
    const homeTab = await page.evaluate(FIND_BOX, '首页');
    if (homeTab) {
      await page.mouse.click(homeTab.x, homeTab.y);
      await sleep(2000);
      await prepareTree(page);
    }
    // 语义节点会把「坐标 + 刚刚 · 精度 ±14m」合并成一段文本，所以用子串提取而不是整串匹配
    const coordOf = (nodes) => {
      for (const n of nodes) {
        const m = n.text.match(/(\d{2,3}\.\d{4,},\s*\d{2,3}\.\d{4,})/);
        if (m) return m[1];
      }
      return null;
    };
    const beforeNodes = await page.evaluate(COLLECT_NODES);
    const beforeLoc = coordOf(beforeNodes);
    await sleep(12000);
    const afterNodes = await page.evaluate(COLLECT_NODES);
    const afterLoc = coordOf(afterNodes);
    check('位置在 12 秒内发生变化（实时链路在工作）',
      !!beforeLoc && !!afterLoc && beforeLoc !== afterLoc,
      beforeLoc
        ? `${beforeLoc} -> ${afterLoc || '未读到'}`
        : `未读到坐标，节点样例: ${beforeNodes.map((n) => n.text.replace(/\s+/g, ' ')).slice(0, 6).join(' / ')}`);
    await page.screenshot({ path: path.join(OUT_DIR, '05-final.png') });

    const realErrors = pageErrors.filter((e) => !/favicon|net::ERR_/.test(e));
    check('运行期无未捕获异常', realErrors.length === 0,
      realErrors.slice(0, 3).join(' | '));
  } finally {
    await browser.close();
  }

  const failed = results.filter((r) => !r.ok);
  console.log(`\n== 结果: ${results.length - failed.length}/${results.length} 通过 ==`);
  console.log(`截图: ${OUT_DIR}`);
  if (failed.length > 0) {
    console.log('失败项:');
    failed.forEach((f) =>
      console.log(`  - ${f.name}${f.detail ? ' (' + f.detail + ')' : ''}`));
  }
  process.exit(failed.length === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error('UI 冒烟执行失败:', e);
  process.exit(1);
});
