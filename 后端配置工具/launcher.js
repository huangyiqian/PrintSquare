// ===========================================================================
// launcher.js — 单文件 exe 的入口（Node SEA Single Executable Application）
//
// 打包后（PrintSquare配置工具.exe）：
//   * 后端代码 server.js 以 SEA asset 的形式嵌在 exe 内部，不落地
//   * data/ 目录定位到 exe 所在目录（通过 PSPHERE_BASE_DIR 传给 server.js）
//   * 自动清理上次的 server-state.json，等服务起来后用默认浏览器打开配置页
//
// 未打包时（node launcher.js）也能直接运行：此时从磁盘读 server.js，
// 目录取本文件所在目录，便于开发调试。
//
// 可用环境变量：
//   PSPHERE_NO_BROWSER=1  不自动打开浏览器（自动化测试用）
//   PORT=xxxx             指定端口（server.js 也支持命令行第 1 个参数）
// ===========================================================================

const fs = require("fs");
const path = require("path");
const Module = require("module");
const { spawn } = require("child_process");

function loadSea() {
  try {
    return require("node:sea");
  } catch {
    return null; // 非 SEA 构建（用普通 node 跑源码）
  }
}

const sea = loadSea();
const isSea = Boolean(sea && sea.isSea && sea.isSea());
const baseDir = isSea ? path.dirname(process.execPath) : __dirname;

// 让 server.js 把 data/ 建在 exe 旁边，而不是二进制内部
process.env.PSPHERE_BASE_DIR = baseDir;

const serverPath = path.join(baseDir, "server.js");
const stateFile = path.join(baseDir, "data", "server-state.json");

// 清掉上次运行留下的状态文件，避免读到旧地址（对齐原 bat 的行为）
try {
  fs.rmSync(stateFile, { force: true });
} catch {
  /* 忽略：下一步写入时会重新创建 */
}

function readConfigUrl() {
  try {
    const raw = JSON.parse(fs.readFileSync(stateFile, "utf8"));
    const urls = Array.isArray(raw.urls) ? raw.urls : [];
    return urls.find((u) => /127\.0\.0\.1|localhost/.test(u)) || urls[0] || "";
  } catch {
    return "";
  }
}

function openBrowser(url) {
  // cmd start 用系统默认浏览器打开，和原来的 bat 行为一致
  const child = spawn("cmd.exe", ["/c", "start", "", url], {
    detached: true,
    stdio: "ignore",
    windowsHide: true
  });
  child.unref();
}

function waitForUrlThenOpen() {
  let tries = 0;
  const timer = setInterval(() => {
    const url = readConfigUrl();
    if (url) {
      clearInterval(timer);
      openBrowser(url);
      console.log(`配置页面已在浏览器打开：${url}`);
      return;
    }
    if (++tries >= 60) {
      clearInterval(timer);
      console.log("未能自动确认服务地址，请手动访问 http://127.0.0.1:8795/");
    }
  }, 500);
}

console.log("============================================================");
console.log(" PrintSquare 配置工具（单文件版）");
console.log(` 工作目录：${baseDir}`);
console.log(" 配置完成后可直接关闭本窗口，后端服务会一并退出。");
console.log("============================================================");
console.log("");

// 把 server.js 作为本模块的子模块执行：
//  - 打包后源码来自 SEA asset，不落地、不需要外部 js 文件
//  - 未打包时走普通 require，行为与 node server.js 完全一致
function bootServer() {
  if (!isSea) {
    require(serverPath);
    return;
  }
  const source = sea.getAsset("server.js", "utf8");
  const mod = new Module(serverPath, null);
  mod.filename = serverPath;
  mod.paths = Module._nodeModulePaths(baseDir);
  mod._compile(source, serverPath);
}

bootServer();

if (String(process.env.PSPHERE_NO_BROWSER || "") !== "1") {
  waitForUrlThenOpen();
}
