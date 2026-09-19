#!/usr/bin/env node
/**
 * STOMP 订阅观察工具（联调 / 验收用）
 *
 * 用途：验证后端 WebSocket 推送链路是否正常 —— 登录后订阅
 * /topic/ward/{wardId}/location、/alert、/device 三个主题，
 * 把收到的消息实时打印出来，同时把订阅被拒的 ERROR 帧也打印出来。
 *
 * 依赖：ws（本地联调工具依赖，不属于后端运行时依赖）
 *   cd backend && npm init -y && npm install ws
 * 或使用本机已装好的 ws：
 *   NODE_PATH=<node_modules 路径> node tools/stomp-watch.js ...
 *
 * 用法：
 *   node tools/stomp-watch.js --token=<accessToken> --ward=1 --duration=60
 *
 * 参数：
 *   --token    必填，/auth/login 返回的 accessToken（不能用 refreshToken）
 *   --ward     被监护人 id，默认 1
 *   --url      STOMP 端点，默认 ws://127.0.0.1:8001/ws（8001 是后端固定端口）
 *   --duration 监听秒数，默认 30；给 0 表示一直监听
 */

const WebSocket = require('ws');

// ---------- 参数解析 ----------
const args = {};
for (const raw of process.argv.slice(2)) {
  const matched = raw.match(/^--([^=]+)=(.*)$/);
  if (matched) {
    args[matched[1]] = matched[2];
  } else if (raw.startsWith('--')) {
    args[raw.slice(2)] = true;
  }
}

const url = args.url || `ws://127.0.0.1:${process.env.PORT || '8001'}/ws`;
const wardId = args.ward || '1';
const duration = args.duration === undefined ? 30 : Number(args.duration);

if (!args.token) {
  console.error('❌ 缺少 --token=<accessToken>');
  process.exit(2);
}
const token = String(args.token).trim();

const TOPICS = [
  `/topic/ward/${wardId}/location`,
  `/topic/ward/${wardId}/alert`,
  `/topic/ward/${wardId}/device`,
];

// ---------- STOMP 帧编解码 ----------
const NULL = '\u0000';

function encodeFrame(command, headers = {}, body = '') {
  let out = command + '\n';
  for (const [key, value] of Object.entries(headers)) {
    out += `${key}:${value}\n`;
  }
  return out + '\n' + body + NULL;
}

function decodeFrame(raw) {
  // 心跳帧是若干个换行，解析时直接丢弃
  const text = raw.replace(/^\n+/, '');
  if (!text) {
    return null;
  }
  const separator = text.indexOf('\n\n');
  const headerPart = separator >= 0 ? text.slice(0, separator) : text;
  const body = separator >= 0 ? text.slice(separator + 2) : '';

  const lines = headerPart.split('\n');
  const command = lines.shift();
  const headers = {};
  for (const line of lines) {
    const idx = line.indexOf(':');
    if (idx > 0) {
      headers[line.slice(0, idx)] = line.slice(idx + 1);
    }
  }
  return { command, headers, body };
}

function ts() {
  return new Date().toTimeString().slice(0, 8);
}

// ---------- 主流程 ----------
const ws = new WebSocket(url, ['v12.stomp']);
let receiveBuffer = '';
let connected = false;
let subscriptionSeq = 0;
let receivedCount = 0;
let messageSeq = 0;

ws.on('open', () => {
  console.log(`[${ts()}] WebSocket 已连接 ${url}，发送 CONNECT 帧...`);
  ws.send(encodeFrame('CONNECT', {
    'accept-version': '1.2',
    host: 'localhost',
    // STOMP 的 CONNECT 帧无法走 HTTP 头，令牌放在自定义帧头里，
    // 由后端 StompAuthChannelInterceptor 读取
    Authorization: `Bearer ${token}`,
    'heart-beat': '30000,30000',
  }));
});

ws.on('message', (data) => {
  receiveBuffer += data.toString();
  let idx;
  while ((idx = receiveBuffer.indexOf(NULL)) >= 0) {
    const raw = receiveBuffer.slice(0, idx);
    receiveBuffer = receiveBuffer.slice(idx + 1);
    const parsed = decodeFrame(raw);
    if (parsed) {
      handleFrame(parsed);
    }
  }
});

function handleFrame({ command, headers, body }) {
  if (command === 'CONNECTED') {
    connected = true;
    console.log(`[${ts()}] ✅ CONNECTED  server=${headers.server || '-'}  心跳=${headers['heart-beat'] || '-'}`);
    for (const topic of TOPICS) {
      subscriptionSeq += 1;
      ws.send(encodeFrame('SUBSCRIBE', {
        id: `sub-${subscriptionSeq}`,
        destination: topic,
        ack: 'auto',
      }));
      console.log(`[${ts()}] → 订阅 ${topic}`);
    }
    console.log(`[${ts()}] 开始监听 ${duration === 0 ? '（长期）' : duration + ' 秒'}...\n`);
    return;
  }

  if (command === 'MESSAGE') {
    receivedCount += 1;
    console.log(`[${ts()}] 📩 ${headers.destination}  (${++messageSeq})`);
    console.log(`          ${body}`);
    return;
  }

  if (command === 'ERROR') {
    console.error(`[${ts()}] ❌ ERROR 帧：${headers.message || ''}`);
    console.error(`          ${body}`);
    return;
  }

  if (command === 'RECEIPT') {
    console.log(`[${ts()}] receipt-id=${headers['receipt-id']}`);
  }
}

ws.on('error', (err) => {
  console.error(`[${ts()}] WebSocket 错误: ${err.message}`);
});

ws.on('close', (code) => {
  console.log(`\n[${ts()}] 连接关闭 code=${code}，本次共收到 ${receivedCount} 条推送`);
  process.exit(0);
});

if (duration > 0) {
  setTimeout(() => {
    console.log(`\n[${ts()}] 监听结束，共收到 ${receivedCount} 条推送`);
    ws.close();
  }, duration * 1000);
}
