/**
 * 浏览器内 STOMP 探针。
 *
 * 目的：把「服务端 + 浏览器 WebSocket」与「stomp_dart_client 库」两件事分开。
 * 手写 CONNECT / SUBSCRIBE 帧（帧头与 Dart 客户端完全一致），如果手写能收到
 * MESSAGE 而 App 收不到，问题就锁定在库的用法上；如果手写也收不到，就是
 * 服务端把这一路订阅拒了。
 *
 * 打印时对 Authorization 里的令牌做脱敏，输出里不会出现任何凭据。
 *
 * 用法: node tools/ws-browser-probe.js
 */
const fs = require('fs');
const path = require('path');

const APP_URL = process.env.APP_URL || 'http://127.0.0.1:9100';
const PORT = process.env.PORT || '8001';
const API_URL = process.env.API_URL || `http://127.0.0.1:${PORT}`;
const WS_URL = process.env.WS_URL || `ws://127.0.0.1:${PORT}/ws`;

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

/** 在页面里跑手写 STOMP 客户端。返回收到的事件序列。 */
const RUN_PROBE = async ({ wsUrl, token, wardId, useSubProtocol }) => {
  const events = [];
  const redact = (s) =>
    String(s).replace(/(Authorization\s*:\s*Bearer\s+)\S+/gi, '$1<REDACTED>');

  const result = await new Promise((resolve) => {
    let ws;
    try {
      ws = useSubProtocol
        ? new WebSocket(wsUrl, 'v12.stomp')
        : new WebSocket(wsUrl);
    } catch (e) {
      resolve({ events: [`构造 WebSocket 抛错: ${e}`] });
      return;
    }
    const NUL = '\u0000';
    const frame = (cmd, headers, body = '') =>
      cmd + '\n' +
      Object.entries(headers).map(([k, v]) => `${k}:${v}`).join('\n') +
      '\n\n' + body + NUL;

    const done = () => resolve({ events });
    const timer = setTimeout(() => {
      events.push('超时结束');
      try { ws.close(); } catch (_) {}
      done();
    }, 12000);

    ws.onopen = () => {
      events.push(`WS 已打开，protocol=${JSON.stringify(ws.protocol)}`);
      ws.send(frame('CONNECT', {
        'accept-version': '1.0,1.1,1.2',
        'heart-beat': '30000,30000',
        Authorization: `Bearer ${token}`,
      }));
      events.push('已发送 CONNECT（Authorization 已脱敏）');
    };
    ws.onmessage = (ev) => {
      const raw = String(ev.data);
      if (raw === '\n' || raw.trim() === '') {
        events.push('收到心跳');
        return;
      }
      const cmd = raw.replace(/^\n+/, '').split('\n')[0];
      events.push(`收到 ${cmd} 帧: ${redact(raw).replace(/\u0000/g, '').slice(0, 400)}`);
      if (cmd === 'CONNECTED') {
        ws.send(frame('SUBSCRIBE', {
          id: 'probe-1',
          destination: `/topic/ward/${wardId}/alert`,
        }));
        ws.send(frame('SUBSCRIBE', {
          id: 'probe-2',
          destination: `/topic/ward/${wardId}/location`,
        }));
        events.push('已发送 SUBSCRIBE probe-1(alert) probe-2(location)');
        // 给 Node 侧留出触发 SOS 的时间窗
        setTimeout(() => {
          clearTimeout(timer);
          events.push('观察窗口结束');
          try { ws.close(); } catch (_) {}
          done();
        }, 7000);
      }
      if (cmd === 'ERROR') {
        events.push('服务端回 ERROR，订阅被拒');
        clearTimeout(timer);
        done();
      }
    };
    ws.onerror = () => events.push('WS onerror（未携带详情）');
    ws.onclose = (e) => events.push(`WS 关闭 code=${e.code} reason=${e.reason}`);
  });
  return result;
};

async function main() {
  const puppeteer = loadPuppeteer();
  fs.mkdirSync(path.join(__dirname, '..', 'target', 'ui'), { recursive: true });

  await api(`/api/v1/mock/sms/reset?phone=${PHONE}`);
  const sms = await api('/api/v1/auth/sms/send', { body: { phone: PHONE } });
  const login = await api('/api/v1/auth/login',
    { body: { phone: PHONE, smsCode: sms.mockCode } });
  await api(`/api/v1/mock/devices/${SN}/reset`, { token: login.accessToken });
  console.log(`已取得令牌（长度 ${login.accessToken.length}，不打印内容）`);

  const browser = await puppeteer.launch({
    executablePath: [
      'C:/Program Files/Google/Chrome/Application/chrome.exe',
      'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    ].find((p) => fs.existsSync(p)),
    headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
    defaultViewport: { width: 430, height: 932 },
  });
  const page = await browser.newPage();
  await page.goto(APP_URL, { waitUntil: 'domcontentloaded', timeout: 90000 });

  try {
    for (const useSubProtocol of [false, true]) {
      console.log(`\n===== 手写 STOMP 探针（subprotocol=${useSubProtocol}） =====`);
      const running = page.evaluate(RUN_PROBE, {
        wsUrl: WS_URL,
        token: login.accessToken,
        wardId: 1,
        useSubProtocol,
      });
      // 等订阅建立后再触发 SOS
      await sleep(3500);
      await api(`/api/v1/mock/devices/${SN}/sos`, { token: login.accessToken });
      const { events } = await running;
      events.forEach((e) => console.log(`  ${e}`));
    }
  } finally {
    await browser.close();
  }
}

main().catch((e) => {
  console.error('探针失败:', e);
  process.exit(1);
});
