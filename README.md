# PrintSquare 双机轮换版

**一块 ESP8266，轮流显示两台拓竹（Bambu Lab）打印机的打印状态。**

本仓库是 [huangyiqian/PrintSquare](https://github.com/huangyiqian/PrintSquare)（V0.5.40）的增强分支，
在上游基础上增加了「双打印机轮换显示」能力，并把电脑端配置工具改成了可审计的 bat + 源码形式。

![Firmware](https://img.shields.io/badge/firmware-v0.5.40--rot-brightgreen)
![Backend](https://img.shields.io/badge/backend-v0.5.40--rot-blue)
![License](https://img.shields.io/badge/license-Non--Commercial-orange)

---

## 这个项目解决了什么

上游固件一块 ESP 只显示一台打印机（同一时刻只订阅一台的云端 MQTT）。
如果你有两台打印机、只想放一块小屏，常见做法是再买一块 ESP —— 本项目改成：

- **同一条 MQTT 连接同时订阅两台打印机**，两台数据都在后台实时更新；
- 屏幕按设定间隔在两台之间切换，**纯内存切换：不重连、不丢数据、不写 Flash**（5 秒一换也不磨损闪存）；
- 配置工具和 8081 页面都能设置「关闭 / 5 秒 / 10 秒 / 30 秒」，断电保存；
- 关闭轮换后固定显示当前选中的那台打印机。

> 适用范围：**同一个 Bambu 账号**下、已同步到 ESP 的打印机；当前实现最多轮换 **2 台**
> （轮换对 = 主显示 ↔ 已同步列表里的第一台其它打印机）。

## 与上游 V0.5.40 的差异

| | 上游 | 本分支 |
|---|---|---|
| 打印机订阅 | 单台 | **双台（可轮换）** |
| 屏幕显示 | 一台 | 一台，按间隔自动切换 |
| 配置工具 | 91MB 单文件 exe（Node SEA） | **bat + `server.js` 明文源码**（需 Node.js 18+，或放便携 node.exe） |
| 配置工具页面 | 单打印机选择 | 新增「4. 双机轮换」面板：间隔、搭档、实时状态、打印机角色列 |
| 8081 页面 | 布局/亮度/旋转/镜像 | 新增「打印机轮换」控件 |
| 状态接口 | — | `/api/status` 增加 `rotate_sec` / `rotate_active` / `rotate_partner` / `display_serial` |
| 仓库历史 | 含早期提交 | **干净重建**，只保留可公开的代码与文档 |

其余功能（三套布局、AMS 耗材显示、细分状态、中英文点阵、亮度定时、旋转/镜像、多设备档案、
80/8081 双端口后台）与上游 V0.5.40 一致。

## 硬件需求

- ESP8266EX / NodeMCU 兼容板
- 240×240 7 针 ST7789 SPI 屏
- CH340/CH341 USB 串口（刷机与配置用）
- 接线（PlatformIO 默认）：`CS=GPIO15`、`DC=GPIO0`、`RST=GPIO2`、`BL=GPIO5`

## 仓库结构

```text
src/                 ESP8266 固件源码（轮换功能在 main.cpp）
include/             TFT_eSPI 屏幕配置
platformio.ini       PlatformIO 构建配置（env: sd2）
docs/
  └─ 双打印机轮换.md   实现细节、限制、实机验证记录、改动点清单
tools/
  └─ verify-rotation.js  局域网轮换验收脚本
后端配置工具/         bat 版配置工具（server.js + 打开配置工具.bat）
刷固件工具/           一键刷入脚本（esptool 随 Release 压缩包分发）
固件/                预编译固件
```

## 快速上手

1. **装驱动**：安装 CH340/CH341 驱动，插上 ESP。
2. **刷固件**：用 Release 压缩包里的 `刷固件工具\一键刷入固件.bat` 刷入 `固件\printsquare-esp8266.bin`
   （默认不擦除，保留 WiFi / Token / 打印机选择）。
3. **配置**：装 Node.js 18+（或把便携 `node.exe` 放到 `后端配置工具\node\`），双击
   `后端配置工具\打开配置工具.bat` → 登录 Bambu 账号 → 写 2.4G WiFi。
4. **同步两台**：刷新打印机列表，对第一台点「显示这台并同步」，再对第二台点一次 ——
   ESP 的 `/printers.json` 里就会有两台。
5. **开轮换**：配置工具「4. 双机轮换」选间隔（或 8081 页面「打印机轮换」），点应用。屏幕开始交替。

## 双机轮换细则

- **轮换对** = 主显示的打印机 ↔ 你选的轮换搭档（未选时用已同步列表里的第一台其它打印机）。
- 配置工具在应用轮换时，会把打印机列表按「主显示 → 搭档 → 其它」顺序同步给 ESP，
  保证轮换对就是页面上选的两台。
- 两台必须是同一账号、同一云端区域；ESP 用一条 MQTT 连接订阅两个 `device/<serial>/report`。
- 切换时整屏重绘一次（百毫秒级），不重新握手；关闭轮换会退订搭档并回到主显示。
- 当前上限 2 台；三台以上需要在固件里扩展状态数组（不在本分支范围内）。
- 相关接口：
  - `GET /api/status` → `rotate_sec`、`rotate_active`、`rotate_partner`、`display_serial`
  - `POST /api/config`（或串口 JSON）→ `rotate_sec`（0 或 3~3600 秒）
- 验收脚本：

```bash
node tools/verify-rotation.js http://<ESP_IP>:8081
```

## 配置工具说明

- 纯源码：`打开配置工具.bat` + `server.js`（只用 Node 内置模块，无需 `npm install`）。
- 需要 Node.js 18+；bat 会先找 `后端配置工具\node\node.exe`，再找系统 `node`。
- 运行时会生成 `后端配置工具\data\`（config.json / devices.json / 设备历史），
  里面有你的账号 token、WiFi 和打印机序列号 —— **不要提交、不要外发**（已在 `.gitignore` 中排除）。
- 关闭 bat 窗口后本地配置服务即停止；日常改布局/亮度/轮换用 `http://ESP_IP:8081/` 即可。

## 从源码编译

```bash
platformio run -e sd2
# 产物：.pio/build/sd2/firmware.bin
```

## 常见问题

- **找不到串口 / 刷机失败**：先装 CH340 驱动；换支持数据传输的 USB 线；关掉占用串口的软件；必要时按住 BOOT 再刷。
- **配置工具提示 `Node.js cannot be started`**：装 Node.js 18+，或把便携 `node.exe` 放进 `后端配置工具\node\`。
- **开了轮换不切换**：确认已同步 ≥2 台（`http://ESP_IP:8081/api/printers` 有两条）；看串口日志中的
  `Cloud MQTT partner subscribed` 与 `[ROTATE] showing ...`。
- **两台名字都是 `??`**：配置工具走串口写配置时是 ASCII 编码，中文名会丢；用 8081 页面重设一次轮换开关刷新，
  或通过 HTTP 重新写入名称。
- **8081 页面打不开**：确认 ESP 连的是 2.4G WiFi；IP 变了用配置工具的「检测当前 ESP」重读。

## 致谢与许可

- 基于 [huangyiqian/PrintSquare](https://github.com/huangyiqian/PrintSquare)（V0.5.40）修改；
- 上游基于 [ccord34/printsphere-lite](https://github.com/ccord34/printsphere-lite)；
- 仅供个人学习与交流，**非商业用途**；商业使用、批量生产需原作者授权，详见 [LICENSE](LICENSE)；
- 刷机与接线属硬件操作，请自行确认接线与供电，风险自负。

本仓库为重新初始化的干净历史（不包含上游 git 历史），只保留可公开的源码、文档与预编译固件。

[![](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)](https://github.com/deepseek-ai/deepseek-harness)
