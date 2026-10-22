/**
 * 登录 / 注册 UI 端到端测试（无头 Chrome 真实渲染 Flutter Web）。
 *
 * 为什么 API 测过了还要跑这一层：
 *   curl 只能证明后端逻辑对，证明不了「用户点得动」。
 *   登录页有三种输入形态（验证码 / 密码 / 注册三框）、两个分段切换、
 *   一个动态按钮文案，这些全靠 widget 状态驱动，只有真渲染才能验。
 *
 * 定位方式（沿用 ui-smoke.js 的经验）：
 *   Flutter web 画在 canvas 上，DOM 没元素可点，只能开语义树。
 *   TextField 的 labelText 落在内部 <input> 的 aria-label 上，
 *   flt-semantics 节点反而是空的——所以输入框按 <input> 找、按钮按 <flt-semantics> 找。
 *   又因为「登录」既是分段按钮标签又是提交按钮文案，纯文本定位会点错，
 *   这里按 y 坐标区分：分段在上（min y），提交按钮在下（max y）。
 *
 * 用法: node tools/ui-auth.js
 * 环境变量: APP_URL / API_URL / OUT_DIR
 */
const fs = require('fs');
const path = require('path');

const APP_URL = process.env.APP_URL || 'http://127.0.0.1:9100';
const API_URL = process.env.API_URL || 'http://127.0.0.1:8001';
const OUT_DIR = process.env.OUT_DIR || path.join(__dirname, '..', 'target', 'ui-auth');

const DEMO_PHONE = '13800138000';
const DEMO_PWD = '123456';

const CHROME_CANDIDATES = [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
];

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
  throw new Error('未找到 puppeteer-core');
}

function findChrome() {
  const hit = CHROME_CANDIDATES.find((p) => fs.existsSync(p));
  if (!hit) throw new Error('未找到 Chrome/Edge');
  return hit;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const results = [];
function check(name, ok, detail = '') {
  results.push({ name, ok, detail });
  console.log(`  [${ok ? 'PASS' : 'FAIL'}] ${name}${detail ? ' — ' + detail : ''}`);
}

// ---------------------------------------------------------------------------
// 页面内执行的探针
// ---------------------------------------------------------------------------

const ENABLE_SEMANTICS = () => {
  const deep = (sel, root = document) => {
    const hit = root.querySelector(sel);
    if (hit) return hit;
    for (const el of root.querySelectorAll('*')) {
      if (el.shadowRoot) {
        const r = deep(sel, el.shadowRoot);
        if (r) return r;
      }
    }
    return null;
  };
  const ph = deep('flt-semantics-placeholder');
  if (!ph) return false;
  ph.click();
  return true;
};

/** 按 aria-label 精确定位输入框，返回矩形（取面积最大的那个，避免命中隐藏副本）。 */
const INPUT_RECTS = (label) => {
  const out = [];
  const walk = (root) => {
    root.querySelectorAll('input').forEach((el) => {
      if ((el.getAttribute('aria-label') || '').trim() !== label) return;
      const r = el.getBoundingClientRect();
      out.push({ x: r.x, y: r.y, w: r.width, h: r.height, area: r.width * r.height });
    });
    root.querySelectorAll('*').forEach((el) => {
      if (el.shadowRoot) walk(el.shadowRoot);
    });
  };
  walk(document);
  return out;
};

/** 输入框里的当前值，用于确认键盘输入真的进了 Flutter。 */
const INPUT_VALUES = () => {
  const out = [];
  const walk = (root) => {
    root.querySelectorAll('input').forEach((el) => {
      const r = el.getBoundingClientRect();
      if (r.width > 0 && r.height > 0) {
        out.push({
          label: (el.getAttribute('aria-label') || '').trim(),
          value: el.value || '',
        });
      }
    });
    root.querySelectorAll('*').forEach((el) => {
      if (el.shadowRoot) walk(el.shadowRoot);
    });
  };
  walk(document);
  return out;
};

/** 文本精确匹配的语义节点列表（带矩形）。 */
const FIND_EXACT = (text) => {
  const out = [];
  const walk = (root) => {
    root.querySelectorAll('flt-semantics').forEach((el) => {
      const label = (el.getAttribute('aria-label') || '').trim();
      const tc = (el.textContent || '').trim();
      if (label !== text && tc !== text) return;
      const r = el.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0) return;
      out.push({
        y: r.y,
        x: r.x,
        w: r.width,
        h: r.height,
        cx: r.x + r.width / 2,
        cy: r.y + r.height / 2,
        area: r.width * r.height,
      });
    });
    root.querySelectorAll('*').forEach((el) => {
      if (el.shadowRoot) walk(el.shadowRoot);
    });
  };
  walk(document);
  return out;
};

/** 语义树全部文本（含 input 的 aria-label），拼成一个串用于包含断言。 */
const ALL_TEXT = () => {
  const parts = [];
  const walk = (root) => {
    root.querySelectorAll('flt-semantics').forEach((el) => {
      const v = (el.getAttribute('aria-label') || '').trim() || (el.textContent || '').trim();
      if (v) parts.push(v);
    });
    root.querySelectorAll('input').forEach((el) => {
      const v = (el.getAttribute('aria-label') || '').trim();
      if (v) parts.push(v);
    });
    root.querySelectorAll('*').forEach((el) => {
      if (el.shadowRoot) walk(el.shadowRoot);
    });
  };
  walk(document);
  return parts.join(' | ');
};

// ---------------------------------------------------------------------------
// 组合动作
// ---------------------------------------------------------------------------

async function prepareTree(page, settleMs = 1000) {
  await page.evaluate(ENABLE_SEMANTICS);
  await sleep(settleMs);
}

async function waitForFlutter(page) {
  await page.waitForFunction(
    () => {
      const deep = (sel, root = document) => {
        const hit = root.querySelector(sel);
        if (hit) return hit;
        for (const el of root.querySelectorAll('*')) {
          if (el.shadowRoot) {
            const r = deep(sel, el.shadowRoot);
            if (r) return r;
          }
        }
        return null;
      };
      return !!deep('flt-glass-pane') || !!deep('flutter-view');
    },
    { timeout: 90000, polling: 500 },
  );
}

/** 清空登录态并重新加载，回到未登录的登录页。 */
async function freshApp(page) {
  await page.evaluate(() => localStorage.clear());
  await page.reload({ waitUntil: 'domcontentloaded', timeout: 90000 });
  await waitForFlutter(page);
  await sleep(3500);
  await prepareTree(page);
}

/** 清掉 storage 里的 field，再 reload。 */
async function typeInto(page, label, text) {
  const rects = await page.evaluate(INPUT_RECTS, label);
  const rect = rects.filter((r) => r.area > 0).sort((a, b) => b.area - a.area)[0];
  if (!rect) return false;
  await page.mouse.click(rect.x + rect.w / 2, rect.y + rect.h / 2);
  await sleep(250);
  // 有些实现里点击后焦点会落到新建的编辑元素上，先清空再输入
  await page.keyboard.down('Control');
  await page.keyboard.press('KeyA');
  await page.keyboard.up('Control');
  await page.keyboard.press('Backspace');
  await sleep(120);
  await page.keyboard.type(text, { delay: 45 });
  await sleep(350);
  return true;
}

/** 按文本点击。pick='maxY' 取最下面的（提交按钮），'minY' 取最上面的（分段标签）。 */
async function clickText(page, text, pick = 'maxY') {
  const nodes = await page.evaluate(FIND_EXACT, text);
  if (nodes.length === 0) return false;
  nodes.sort((a, b) => (pick === 'maxY' ? b.y - a.y : a.y - b.y));
  const n = nodes[0];
  await page.mouse.click(n.cx, n.cy);
  await sleep(700);
  return true;
}

async function hasInput(page, label) {
  const rects = await page.evaluate(INPUT_RECTS, label);
  return rects.some((r) => r.area > 0);
}

async function waitForText(page, substr, timeoutMs) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const text = await page.evaluate(ALL_TEXT);
    if (text.includes(substr)) return { text, latencyMs: Date.now() - started };
    await sleep(200);
  }
  return null;
}

// ---------------------------------------------------------------------------

async function main() {
  const puppeteer = loadPuppeteer();
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const stamp = String(Math.floor(10000000 + Math.random() * 89999999));
  const NEW_PHONE = '137' + stamp;
  const NEW_PWD = 'reg123456';

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
    if (m.type() === 'error') pageErrors.push('console: ' + m.text());
  });

  try {
    // ======================================================= 1. 登录页结构
    console.log('== 1. 首屏：登录页结构 ==');
    await page.goto(APP_URL, { waitUntil: 'domcontentloaded', timeout: 90000 });
    await waitForFlutter(page);
    await sleep(4000);
    await prepareTree(page);

    const text1 = await page.evaluate(ALL_TEXT);
    await page.screenshot({ path: path.join(OUT_DIR, '01-login-sms.png') });

    check('Flutter 渲染出登录页', text1.includes('导盲杖家属端'),
      text1.slice(0, 60).replace(/\s+/g, ' '));
    check('存在「登录 / 注册」分段切换',
      text1.includes('登录') && text1.includes('注册'));
    check('验证码登录态：手机号 + 验证码输入框都在',
      (await hasInput(page, '手机号')) && (await hasInput(page, '验证码')),
      `inputs=${JSON.stringify((await page.evaluate(INPUT_VALUES)).map((v) => v.label))}`);
    check('提供「用密码登录」切换入口', text1.includes('用密码登录'));
    check('未登录不会误入首页', !text1.includes('实时位置'));

    // ======================================================= 2. 验证码登录
    console.log('== 2. 验证码登录（真实调后端取码） ==');
    const typedPhone = await typeInto(page, '手机号', DEMO_PHONE);
    check('手机号输入框可聚焦并输入', typedPhone);
    const vals = await page.evaluate(INPUT_VALUES);
    const phoneVal = (vals.find((v) => v.label === '手机号') || {}).value || '';
    check('手机号已写入输入框', phoneVal === DEMO_PHONE, `value=${phoneVal}`);

    const clickedSend = await clickText(page, '获取验证码', 'minY');
    check('点击「获取验证码」', clickedSend);
    const hint = await waitForText(page, '演示模式：短信未真实下发', 15000);
    await page.screenshot({ path: path.join(OUT_DIR, '02-code-sent.png') });
    check('收到后端随机验证码提示', !!hint,
      hint ? hint.text.match(/验证码为\s*(\d{6})/)?.[1] : '超时未出现');

    const codeVal = ((await page.evaluate(INPUT_VALUES)).find((v) => v.label === '验证码') || {}).value || '';
    check('验证码已自动填入输入框（6 位）', /^\d{6}$/.test(codeVal), `value=${codeVal}`);

    await clickText(page, '登录', 'maxY');
    const home1 = await waitForText(page, '实时位置', 25000);
    await page.screenshot({ path: path.join(OUT_DIR, '03-home-sms.png') });
    check('验证码登录后跳转首页', !!home1,
      home1 ? `${home1.latencyMs}ms 内进入` : '25s 未进入首页');
    check('首页显示家属昵称', (await page.evaluate(ALL_TEXT)).includes('家属8000'));

    // ======================================================= 3. 密码登录
    console.log('== 3. 密码登录 ==');
    await freshApp(page);
    const sw = await clickText(page, '用密码登录', 'minY');
    await sleep(800);
    await prepareTree(page, 600);
    check('切换到密码登录', sw && (await hasInput(page, '密码')),
      `inputs=${JSON.stringify((await page.evaluate(INPUT_VALUES)).map((v) => v.label))}`);
    const textPwd = await page.evaluate(ALL_TEXT);
    check('密码模式不再显示验证码输入框', !(await hasInput(page, '验证码')) && textPwd.includes('用验证码登录'));
    await page.screenshot({ path: path.join(OUT_DIR, '04-login-password.png') });

    await typeInto(page, '手机号', DEMO_PHONE);
    await typeInto(page, '密码', DEMO_PWD);
    await clickText(page, '登录', 'maxY');
    const home2 = await waitForText(page, '实时位置', 25000);
    await page.screenshot({ path: path.join(OUT_DIR, '05-home-password.png') });
    check('密码登录后跳转首页', !!home2, home2 ? `${home2.latencyMs}ms 内进入` : '25s 未进入首页');

    // ======================================================= 4. 错误提示
    console.log('== 4. 密码错误时给出可读提示 ==');
    await freshApp(page);
    await clickText(page, '用密码登录', 'minY');
    await sleep(800);
    await prepareTree(page, 600);
    await typeInto(page, '手机号', DEMO_PHONE);
    await typeInto(page, '密码', 'wrong9999');
    await clickText(page, '登录', 'maxY');
    const errText = await waitForText(page, '手机号或密码错误', 20000);
    await page.screenshot({ path: path.join(OUT_DIR, '06-wrong-password.png') });
    check('错误密码提示「手机号或密码错误」', !!errText,
      errText ? `${errText.latencyMs}ms 内出现` : '20s 未出现');
    check('失败后仍停在登录页', !(await page.evaluate(ALL_TEXT)).includes('实时位置'));

    // ======================================================= 5. 注册
    console.log('== 5. 注册（手机号 + 密码 + 验证码） ==');
    await freshApp(page);
    const swReg = await clickText(page, '注册', 'minY');
    await sleep(900);
    await prepareTree(page, 600);
    const regLabels = (await page.evaluate(INPUT_VALUES)).map((v) => v.label);
    check('切换到注册模式', swReg, `inputs=${JSON.stringify(regLabels)}`);
    check('注册页出现手机号 / 密码 / 确认密码 / 验证码四个输入框',
      ['手机号', '密码', '确认密码', '验证码'].every((l) => regLabels.includes(l)),
      JSON.stringify(regLabels));
    await page.screenshot({ path: path.join(OUT_DIR, '07-register.png') });

    await typeInto(page, '手机号', NEW_PHONE);
    await typeInto(page, '密码', NEW_PWD);
    await typeInto(page, '确认密码', NEW_PWD);
    await clickText(page, '获取验证码', 'minY');
    const hint2 = await waitForText(page, '演示模式：短信未真实下发', 15000);
    check('注册时也能取到验证码', !!hint2);
    const code2 = ((await page.evaluate(INPUT_VALUES)).find((v) => v.label === '验证码') || {}).value || '';
    check('注册验证码已填入', /^\d{6}$/.test(code2), `value=${code2}`);

    await clickText(page, '注册', 'maxY');
    const home3 = await waitForText(page, '实时位置', 25000);
    await page.screenshot({ path: path.join(OUT_DIR, '08-home-register.png') });
    check('注册成功后自动进入首页', !!home3, home3 ? `${home3.latencyMs}ms 内进入` : '25s 未进入首页');
    const finalText = await page.evaluate(ALL_TEXT);
    check('首页显示新账号昵称（取手机尾号）',
      finalText.includes('家属' + NEW_PHONE.slice(-4)), NEW_PHONE);

    // ======================================================= 6. 无崩溃
    console.log('== 6. 运行期异常检查 ==');
    const realErrors = pageErrors.filter((e) => !/favicon|net::ERR_INTERNET|TypeError: Failed to fetch/i.test(e));
    check('全流程无未捕获异常', realErrors.length === 0,
      realErrors.slice(0, 2).join(' // ') || `${pageErrors.length} 条已知噪声已忽略`);

    console.log('\n== 登记测试账号 ==');
    console.log(`  注册号: ${NEW_PHONE} / ${NEW_PWD}`);
    console.log(`  演示号: ${DEMO_PHONE} / ${DEMO_PWD}`);
  } finally {
    await browser.close();
  }

  const failed = results.filter((r) => !r.ok);
  console.log('\n==============================================');
  console.log(` 结果：${results.length - failed.length} passed, ${failed.length} failed`);
  console.log(` 截图：${OUT_DIR}`);
  console.log('==============================================');
  if (failed.length) {
    failed.forEach((f) => console.log(`  FAIL: ${f.name} ${f.detail}`));
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error('执行出错:', e);
  process.exit(1);
});
