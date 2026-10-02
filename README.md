[ English Version ](README_en.md) | [ 简体中文 ](README.md)

# PrintSphere Lite Plus (Fork 版本)

![Version](https://img.shields.io/badge/Firmware-v0.5.30-brightgreen)
![Backend Version](https://img.shields.io/badge/WebUI_Backend-v0.5.30-blue)
![License](https://img.shields.io/badge/License-Non--Commercial-orange)

本项目为原版 [PrintSphere Lite](https://github.com/ccord34/printsphere-lite) 的增强改进版本（Fork）。基于 ESP8266EX 与 240x240 ST7789 屏幕，专为 Bambu Lab（拓竹）3D 打印机打造的桌面打印状态与 AMS 耗材监控小电视。

---

## 📌 功能介绍

### 🌈 AMS（拓竹多色系统）与外挂料盘（Ext Spool）显示支持
* **多色耗材与外挂料盘渲染**：实时解析 AMS 槽位状态，显示每个槽位的耗材颜色、材质类型与加载状态。
* **无 AMS 场景自适应排版**：自动识别打印机是否接入 AMS，无 AMS 时隐藏冗余空槽位，并以外挂料盘（Ext Spool）紧凑显示。
* **官方与第三方耗材区分**：官方 RFID 耗材显示剩余容量，第三方或无 RFID 耗材只显示色块与材质，避免误导性余量。
* **BGR565 颜色校正**：适配 ST7789 屏幕，准确显示耗材颜色。

### 📊 屏幕 UI 与显示布局
* **三套屏幕布局**：提供经典、信息面板（Dashboard）与时钟布局，均适配 240x240 ST7789 屏幕。
* **完整打印信息**：同时展示打印进度、喷嘴温度、热床温度、仓温与预计剩余时间。
* **显示控制**：支持 0-100% 背光亮度、无任务自动降亮，以及按 90° 步进旋转屏幕并断电保存配置。
* **平滑视觉效果**：使用连续渐变进度条和玻璃拟态元素，数据刷新采用局部更新以减少整屏闪烁。

### 🌐 Web 配置工具
* **设备配置**：支持 WiFi 扫描、打印机选择与同步、屏幕布局切换、亮度和旋转设置。
* **实时监控**：可查看打印状态、进度、温度、层数、剩余时间与耗材槽位。
* **多设备管理**：按硬件标识隔离配置，并优先通过 USB 串口写入，HTTP 局域网配置作为后备。
* **双端口访问**：设备同时支持 80 和 8081 端口的 Web 管理页面。

---

## 🖼️ 界面与实机效果预览

| 经典布局 (Classic) | 信息面板布局 (Dashboard) | 时钟布局 (Clock) |
| :---: | :---: | :---: |
| <img src="docs/images/classic.jpg" width="240" /> | <img src="docs/images/dashboard.jpg" width="240" /> | <img src="docs/images/clock.jpg" width="240" /> |

### Web 后端配置界面
<p align="center">
  <img src="docs/images/网页后台.png" width="560" />
</p>

---

## 🛠️ 硬件需求与引脚连接

* **主控**：ESP8266EX / NodeMCU 兼容开发板
* **屏幕**：240x240 7针 ST7789 SPI 显示屏
* **外壳**：外壳模型可选择https://makerworld.com.cn/zh/models/2587841-cheng-ben-25-printsphere-litetuo-zhu-da-yin-zhuang#profileId-2978954
* **接线参考 (PlatformIO 默认)**：
  * `CS`: GPIO 15
  * `DC`: GPIO 0
  * `RST`: GPIO 2
  * `BL`: GPIO 5 (PWM 背光控制)

---

## 🚀 快速上手使用

1. 使用 USB 线将 ESP8266 连接到 Windows 电脑。
2. 打开 `后端配置工具\PrintSphere配置工具.exe`（单文件工具，双击即用），在自动打开的浏览器页面中登录 Bambu Lab 账号。
3. 选择或填写 2.4G WiFi 名称与密码，点击 **“保存并配置 ESP WiFi”**。
4. 刷新打印机列表，选中你的拓竹打印机并点击 **“显示这台并同步”**。
5. ESP8266 屏幕出现数据后即可拔下电脑 USB，改用任意 5V USB 供电使用。
6. 设备连上 WiFi 后，也可以通过浏览器直接访问 `http://[ESP的局域网IP]:8081/` 进行轻量无线管理。

---

## 💻 编译与构建

项目基于 [PlatformIO](https://platformio.org/) 构建，如需修改源码并自行编译：

```bash
# 编译 ESP8266 固件
platformio run -e sd2
```

编译产物路径：`.pio/build/sd2/firmware.bin`

---

## 📄 License 与致谢

* 本项目基于 [ccord34/printsphere-lite](https://github.com/ccord34/printsphere-lite) 原项目进行修改和增强。
* 本项目仅供个人学习、交流及非商业用途使用。商业使用、批量生产或集成付费服务需获得原作者授权。详细声明见 [LICENSE](LICENSE)。
