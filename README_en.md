[ 简体中文 ](README.md) | [ English ](README_en.md)

# PrintSquare (Enhanced Fork)

![Version](https://img.shields.io/badge/Firmware-v0.5.40-brightgreen)
![Backend Version](https://img.shields.io/badge/WebUI_Backend-v0.5.40-blue)
![License](https://img.shields.io/badge/License-Non--Commercial-orange)

📦 Repository: [https://github.com/huangyiqian/PrintSquare](https://github.com/huangyiqian/PrintSquare)

This project is an enhanced and improved fork of the original [PrintSphere Lite](https://github.com/ccord34/printsphere-lite). Powered by ESP8266EX and a 240x240 ST7789 display, it serves as a mini desktop monitor for real-time printing status and AMS filament tracking for Bambu Lab 3D printers.

---

## 📌 Features

### 🌈 AMS & External Spool Support
* **Multi-color filament rendering**: Displays real-time AMS slot colors, material types, and loading status.
* **Adaptive no-AMS layout**: Automatically detects AMS presence, hides unused slots, and presents the external spool compactly.
* **Official and third-party filament handling**: Shows remaining capacity for official RFID filaments while third-party or non-RFID filaments display only color and material to avoid misleading estimates.
* **ST7789 color calibration**: Uses corrected BGR565 color mapping for accurate filament colors.

### 📊 Screen UI & Layouts
* **Three screen layouts**: Classic, Dashboard and Clock, all fitting the 240x240 ST7789 display, switchable from the built-in 8081 admin page.
* **Complete print overview**: Shows print progress, nozzle temperature, bed temperature, chamber temperature, layer count and estimated remaining time.
* **Detailed printer stage**: Parses the Bambu MQTT `stg_cur` action stage and shows the **actual current action** — auto bed leveling, heatbed preheating, vibration compensation, changing / unloading / loading filament, homing, cleaning the nozzle, heating the hotend, extrusion calibration, motor calibration, filament runout, nozzle wrapping, nozzle clog, and more — in the top-right corner of all three layouts, instead of only the four coarse states.
* **Bilingual status text**: The same status can be rendered either as an English abbreviation (`BEDLVL`, `FLOWCAL`, ...) or as **Chinese bitmap glyphs** (自动调平, 换料中, ...). It follows the Chinese/English switch on the 8081 page and is stored on the device across reboots. Stages specific to other printer families fall back to the generic state automatically, and unmapped error stages are shown as "错误".
* **Backlight & brightness schedule**: 0-100% manual brightness plus optional day / night time slots (configurable on the 8081 page); settings persist across power loss.
* **Half-mirror support (image flip)**: Built for HoloCubic-style 45° half-mirror assemblies, offering Off / Left-right mirror — a mirrored image cannot be corrected by any rotation angle, so it must be flipped electronically. The flip combines freely with 0° / 90° / 180° / 270° rotation, can be switched from both the 8081 page and the desktop tool, and is stored in LittleFS so it survives reboots.
* **Screen rotation**: 0° / 90° / 180° / 270° rotation steps, persisted across power loss; only orientation changes trigger a full redraw, while normal data updates stay partial.
* **Smooth visual effects**: Uses continuous gradient progress indicators and glass-inspired elements, with partial updates to reduce full-screen flicker.

### 🌐 Web Configuration Tool
* **Device setup**: Wi-Fi scanning, printer selection and synchronization, layout / brightness / rotation / mirror settings; writes go over USB serial first with LAN HTTP as fallback.
* **Live monitoring**: Provides print status, progress, temperatures, layer information, remaining time, filament slot data, and the **current action** together with the raw MQTT codes (`gcode_state` / `stg_cur`) and an explanation for troubleshooting.
* **Multi-device management**: Keeps a separate profile per ESP keyed by MAC / device_id (Wi-Fi, serial port, address, selected printer); the cloud account and printer list are shared.
* **Dual-port access**: The same admin page listens on both port 80 and port 8081, so it opens without typing a port; `http://ESP-IP:8081/` is the recommended URL.
* **Chinese/English switch**: The built-in ESP page on port 8081 can switch between Chinese and English; the choice is stored in the browser and **is also pushed to the device, which decides whether the screen itself shows Chinese glyphs or English abbreviations**.

---

## 🖼️ Interface & Hardware Previews

| Classic Layout | Dashboard Layout | Clock Layout |
| :---: | :---: | :---: |
| <img src="docs/images/classic.jpg" width="240" /> | <img src="docs/images/dashboard.jpg" width="240" /> | <img src="docs/images/clock.jpg" width="240" /> |

### Web Backend Configuration Interface
<p align="center">
  <img src="docs/images/网页后台.png" width="560" />
</p>

---

## 🛠️ Hardware Requirements & Pinout

* **MCU**: ESP8266EX / NodeMCU compatible board
* **Display**: 240x240 7-pin ST7789 SPI LCD Screen
* **Enclosure**: 外壳模型可选择https://makerworld.com.cn/zh/models/2587841-cheng-ben-25-printsphere-litetuo-zhu-da-yin-zhuang#profileId-2978954
* **Pin Connections (PlatformIO Default)**:
  * `CS`: GPIO 15
  * `DC`: GPIO 0
  * `RST`: GPIO 2
  * `BL`: GPIO 5 (PWM Backlight Control)

---

## 🚀 Quick Start

1. Download the latest archive `PrintSquare_v<version>_<date>_build.zip` from [GitHub Releases](https://github.com/huangyiqian/PrintSquare/releases) and extract it.
2. Connect the ESP8266 to your Windows PC with a USB cable, then double-click `刷固件工具\一键刷入固件.bat` inside the extracted package and follow the prompts to flash the firmware.
3. Open `后端配置工具\PrintSquare配置工具.exe` (single-file tool, just double-click), which opens the WebUI in your default browser, and log in to your Bambu Lab account.
4. Select or enter your 2.4G Wi-Fi SSID and password, then click **“Save & Configure ESP WiFi”**.
5. Refresh printer list, select your target Bambu printer, and click **“Show This Printer & Sync”**.
6. Once print data appears on the ESP8266 screen, you can unplug the device from your computer and power it via any 5V USB source.
7. Once connected to Wi-Fi, you can also manage the device directly in your browser via `http://[ESP_IP_ADDRESS]:8081/`.

---

## 💻 Build & Compile

This project is built using [PlatformIO](https://platformio.org/):

```bash
# Build ESP8266 firmware
platformio run -e sd2
```

Compiled binary output: `.pio/build/sd2/firmware.bin`

---

## 📄 License & Acknowledgements

* Based on the original project [ccord34/printsphere-lite](https://github.com/ccord34/printsphere-lite).
* Intended for personal learning, hobbyist, and non-commercial use only. Commercial use, mass production, or integration into paid services requires authorization from the original author. See [LICENSE](LICENSE) for details.
