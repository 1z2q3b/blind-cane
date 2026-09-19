/**
 * 演示前复位后端演示数据。
 *
 * 为什么需要：跑几次验证脚本之后，ward 1 会堆下十几条待处理告警，
 * 首页角标变成「16 告警」、设备电量被压到 1%，演示效果直接崩掉。
 * 每次演示前先跑一遍这个脚本，回到「干净但真实」的初始状态。
 *
 * 做三件事：
 *   1. 清掉演示手机号的短信每日限流（否则当天第 10 次登录会撞 101008）
 *   2. 复位演示设备：电量回 85%、恢复在线
 *   3. 把未处理的告警逐条走官方处置接口置为「已处理」
 *      —— 走接口而不是直接改数据库，顺带把处置链路也验证一遍
 *
 * 用法:
 *   node tools/demo-reset.js
 * 环境变量:
 *   API_URL  默认 http://127.0.0.1:8001（端口 8001 是后端固定端口）
 *   PORT     只想换端口时用，等价于改 API_URL
 */
const PORT = process.env.PORT || '8001';
const API_URL = process.env.API_URL || `http://127.0.0.1:${PORT}`;

const PHONE = '13800138000';
const SMS_CODE = '123456';
const SN = 'BC-2024-DEMO01';
const WARD_ID = 1;

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
    throw new Error(
      `${method} ${pathname} -> code=${json.code} message=${json.message}`,
    );
  }
  return json.data;
}

async function main() {
  console.log(`== 复位演示数据 @ ${API_URL} ==`);

  console.log('1. 清除短信限流');
  const sms = await api(`/api/v1/mock/sms/reset?phone=${PHONE}`);
  console.log(`   ${sms}`);

  console.log('2. 复位演示设备');
  const device = await api(`/api/v1/mock/devices/${SN}/reset`);
  console.log(`   ${device}`);

  console.log('3. 登录演示账号');
  await api('/api/v1/auth/sms/send', { body: { phone: PHONE } });
  const login = await api('/api/v1/auth/login', {
    body: { phone: PHONE, smsCode: SMS_CODE },
  });
  const token = login.accessToken;
  console.log(`   已登录：${login.userInfo.nickname}`);

  console.log('4. 处置遗留的待处理告警');
  let handled = 0;
  // 每轮最多拿 50 条，处置完再取一次，直到没有待处理的
  for (let round = 0; round < 20; round += 1) {
    const page = await api(
      `/api/v1/alerts?wardId=${WARD_ID}&status=0&page=1&size=50`,
      { method: 'GET', token },
    );
    if (!page.records || page.records.length === 0) {
      break;
    }
    for (const alert of page.records) {
      await api(`/api/v1/alerts/${alert.id}/handle`, {
        method: 'PUT',
        token,
        body: { result: 'RESOLVED', note: '演示数据复位' },
      });
      handled += 1;
    }
  }
  console.log(`   共处置 ${handled} 条`);

  const pending = await api('/api/v1/alerts/pending-count', {
    method: 'GET',
    token,
  });
  console.log(`\n== 复位完成，当前待处理告警 ${pending.total} 条 ==`);
}

main().catch((e) => {
  console.error('复位失败:', e.message);
  process.exit(1);
});
