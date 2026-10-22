// Verify dual-printer rotation on a PrintSquare device running firmware-v0.5.40-rot.
// Usage: node tools/verify-rotation.js http://<ESP_IP>:8081
const base = process.argv[2];
if (!base) {
  console.error("用法: node tools/verify-rotation.js http://<ESP_IP>:8081");
  process.exit(1);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const getJson = async (p, t = 8000) => {
  const r = await fetch(base + p, { signal: AbortSignal.timeout(t), cache: "no-store" });
  const text = await r.text();
  return { status: r.status, text, json: (() => { try { return JSON.parse(text); } catch { return null; } })() };
};
const postJson = async (p, body, t = 8000) => {
  const r = await fetch(base + p, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(t),
  });
  return { status: r.status, text: await r.text() };
};

(async () => {
  console.log("== 1. 等待设备并检查版本 ==");
  let st = null;
  for (let i = 0; i < 30; i++) {
    try { const r = await getJson("/api/status", 4000); if (r.json) { st = r.json; break; } } catch {}
    await sleep(2000);
  }
  if (!st) { console.error("设备无响应: " + base); process.exit(2); }
  console.log(JSON.stringify({
    firmware: st.firmware_version, ip: st.ip, printer_count: st.printer_count,
    rotate_sec: st.rotate_sec, display_serial: st.display_serial, name: st.name,
    mqtt_connected: st.mqtt_connected, free_heap: st.free_heap,
  }, null, 1));
  if (st.firmware_version !== "firmware-v0.5.40-rot") {
    console.error("固件版本不是 firmware-v0.5.40-rot"); process.exit(3);
  }
  if (!(st.printer_count >= 2)) {
    console.error("已同步打印机数量 < 2，无法轮换"); process.exit(4);
  }

  console.log("\n== 2. 8081 页面控件 ==");
  const page = await fetch(base + "/", { signal: AbortSignal.timeout(8000) }).then((r) => r.text());
  console.log("包含『打印机轮换』:", page.includes("打印机轮换") ? "YES" : "NO");
  console.log("包含 rotate-segmented:", page.includes("rotate-segmented") ? "YES" : "NO");

  console.log("\n== 3. 打开 5 秒轮换 ==");
  console.log(await postJson("/api/config", { rotate_sec: 5 }));

  console.log("\n== 4. 轮询 /api/status 观察 display_serial ==");
  const seq = [];
  let switches = 0;
  for (let i = 0; i < 16; i++) {
    await sleep(2000);
    try {
      const r = await getJson("/api/status", 5000);
      if (!r.json) continue;
      const j = r.json;
      if (seq.length && seq[seq.length - 1].serial !== j.display_serial) switches++;
      seq.push({ serial: j.display_serial, name: j.name });
      console.log(`#${String(i).padStart(2)}  ${(i * 2 + "s").padStart(4)}  ${j.display_serial}  ${j.name}  ${j.status}  online=${j.online}`);
    } catch {}
  }
  console.log("\n切换次数:", switches);
  const serials = [...new Set(seq.map((x) => x.serial))];
  if (serials.length >= 2 && switches >= 1) {
    console.log("\n✅ 轮换生效：屏幕在两台之间交替。");
    process.exit(0);
  }
  console.error("\n⚠️ 没有观察到交替切换，检查串口日志 [ROTATE] / [PUB]。");
  process.exit(5);
})();
