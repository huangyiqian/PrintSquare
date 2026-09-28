[ 简体中文 ](README.md) | [ English ](README_en.md)

# PrintSphere Lite Plus (Enhanced Fork)

![Version](https://img.shields.io/badge/Firmware-v0.5.25-brightgreen)
![Backend Version](https://img.shields.io/badge/WebUI_Backend-v0.5.25-blue)
![License](https://img.shields.io/badge/License-Non--Commercial-orange)

This project is an enhanced and improved fork of the original [PrintSphere Lite](https://github.com/ccord34/printsphere-lite). Powered by ESP8266EX and a 240x240 ST7789 display, it serves as a mini desktop monitor for real-time printing status and AMS filament tracking for Bambu Lab 3D printers.

---

## 📌 Fork Features & Improvements

### 1. 🌈 AMS (Bambu Multi-Material System) & External Spool (Ext Spool) Support
* **Multi-color filament & external spool rendering**: Fully parses Bambu AMS slot status in real time, accurately recognizing filament color, material type, and loading status for each slot.
* **Adaptive layout without AMS**: Automatically detects whether an AMS unit is connected via `ams_exist_bits`. When no AMS is present, it cleanly hides the 3 redundant empty slots and displays the external spool as `ext` in the first position, keeping the layout compact and elegant.
* **Smart discrimination between Official & 3rd-Party filaments**:
  * Automatically validates RFID tag data (`tag_uid`).
  * **Official filaments** (with RFID): Accurately displays remaining filament percentage (e.g., `85%`).
  * **3rd-party / non-RFID filaments** (Generic/spool holder): Automatically hides percentage numbers, keeping only the color block and material abbreviation (e.g., `PLA`, `PETG`) to prevent misleading estimates.
* **BGR565 color correction**: Recalibrated RGB/BGR565 color mapping specifically for the ST7789 display panel, delivering vibrant and realistic filament colors.
* **Intelligent screen cleanup**: Automatically clears AMS indicators and print speeds when a job finishes, is cancelled, or enters idle state, seamlessly switching back to standby/clock view.

### 2. 📊 Screen UI & Layout Optimization
* **Redesigned Dashboard UI**: Features a 2x2 data card grid showing print progress, nozzle temperature, bed temperature, chamber temperature, and estimated remaining time simultaneously.
* **Dual-nozzle & multi-model compatibility**: Optimized for various models (A1/A1 mini, P1P/P1S, P2S, X1C, X2D, H2 series, etc.), ensuring temperatures and dual-nozzle data are displayed cleanly without text truncation or overlap.
* **PWM backlight control**: Supports 0-100% free slider brightness adjustment, with an automatic low-power dimming standby mode after 5 minutes of inactivity.

### 3. 🌐 WebUI Backend Configuration Tool Upgrades
* **Clean & compact interface**: Streamlined web configuration tool with fast response and reduced whitespace, grouped logically into Wi-Fi scanning, printer switching, and screen layout options.
* **Multi-device profile management**: Supports managing multiple ESP devices under a single Bambu cloud account, isolating settings per hardware by MAC address and Chip ID.
* **USB Serial priority**: All configuration pushes prioritize USB Serial connection with HTTP LAN as a fallback, preventing cross-device misconfigurations on the local network.

### 4. 🧹 Repository Optimization & Privacy Sanitization
* **Sensitive privacy protection**: Configured `.gitignore` rules to exclude Wi-Fi credentials, Bambu Cloud tokens, and printer access codes (`config.json`), safeguarding private data.
* **Local backup isolation**: Keeps local development backups (`*.bak`) on your machine while preventing accidental cloud pushes.
* **Lightweight repository**: Removed bulky redundant binaries and temporary debug scripts for lightning-fast cloning and updates.

### 5. ⚡ ESP Built-in Web (:8081) & Long-term Stability Hardening (v0.5.00)
* **Zero dynamic heap overhead streaming**: Refactored the built-in web management page to stream HTML chunks directly from PROGMEM, dropping the dynamic heap allocation peak to 0 bytes and eliminating memory fragmentation and OOM crashes.
* **Port zombie self-healing**: Addressed the silent lwIP `_listen_pcb` release bug (port unresponsive while flagged as started). Added `isEspServerListening()` active status validation to automatically re-bind and listen if any anomaly occurs.
* **Wi-Fi jitter protection**: Removed destructive socket close calls triggered by transient Wi-Fi beacon losses or packet drops, preventing exhaustion of lwIP TCP PCBs.
* **Speculative connection handling**: Modern browser speculative pre-connections (0 bytes sent) are discarded within 100ms, and request line timeout is tightened from 2000ms to 600ms to avoid blocking the main loop or MQTT packets.
* **Smart idle polling**: WebUI polling interval extended to 8 seconds and coupled with `!document.hidden` visibility checks, completely halting requests when the browser tab is backgrounded or screen locked to prevent `TIME_WAIT` socket buildup.

### 6. 📱 Built-in Web Real-time Printer Dashboard & Seamless Dual-Port Access (v0.5.10)
* **Full-width Real-time Status Card**: Added a dedicated glassmorphism live status dashboard featuring task state badges (Printing, Preparing, Paused, Finished, Standby), dual-color smooth gradient progress bar, and 24px large percentage display.
* **6-Metric Operations Grid**: Real-time readouts for remaining time (auto-formatted in hours/minutes), current layer / total layers, 0.1°C nozzle and bed temperatures, chamber temperature, and Bambu speed modes (Silent 50%, Standard 100%, Sport 124%, Ludicrous 166%).
* **AMS & External Spool Slot Capsules**: Dynamically displays loaded filament color swatches and material types, highlighting the active feed slot with a glowing green border; automatically hides remaining percentages for third-party non-RFID filaments to avoid misleading estimates.
* **Smart Chamber Sensor N/A Handling**: Automatically filters out misleading telemetry placeholders (e.g. 5°C) on models lacking hardware chamber temperature sensors (A1, A1 mini, P1P, P1S), displaying clean `N/A` instead.
* **Dual-Port Listening (Port 80 & 8081)**: Concurrently listens on standard HTTP port 80 and port 8081, allowing mobile browsers to access the dashboard directly via `http://<IP>` without entering `:8081`.
* **Refined Device Status Row**: Streamlined the device card status row to remove redundant nozzle temperature numbers, keeping it clean with job status and progress.

### 7. 🚀 High-Performance Stream Web Server & Cross-Device Hardening (v0.5.13)
* **Root-Cause Fix for Disconnect Infinite Loop & WDT Reboot**: Completely resolved the `while(size > 0)` infinite loop and Watchdog reset in `ChunkedBufferedPrinter` triggered when browsers disconnect or reload mid-stream, introducing instant early-exit on socket closure.
* **1024-Byte Chunk Buffer with Perfect MSS Alignment**: Resized chunk buffer to 1024 bytes (total frame ~1031 bytes), fitting entirely within standard MTU/MSS (1460 bytes) to eradicate 200ms Delayed ACK penalties from packet fragmentation while saving 436 bytes of RAM.
* **Data-Ready Priority & Lenient Mobile Wi-Fi Window**: Overhauled `handleApiClient()` to prioritize `hasClientData()` ready connections (0ms delay), and provides a safe 600ms grace window with `ESP.wdtFeed()` and `optimistic_yield(1000)` for mobile devices under 802.11 power save, completely fixing the 100% mobile access failure bug.
* **Elimination of `client.flush()` Deadlocks**: Removed blocking `client.flush()` calls in ESP8266 core (`wait_until_acked` timeout up to 5000ms), eliminating deadly thread freezes caused by conflicts with browser 200ms TCP delayed ACKs.

### 8. 🛡️ MQTT Invalid Return Value Validation, Auto-Reconnect & Status Hardening (v0.5.14)
* **Comprehensive Low-Level Return Value Validation**: Added strict write byte-count checks on `mqttSendPing()`, `publishMqttRequest()`, and `mqttSendPuback()`, instantly triggering reconnection upon write failure; `mqttReadPacket()` automatically terminates the socket on read errors or negative headers to prevent BearSSL/lwIP half-open deadlocks.
* **Protocol-Level Disconnect & Error Resilience**: Added detection for MQTT DISCONNECT (Type 14) packets; automatically triggers reconnection if 3 consecutive JSON deserialization errors occur.
* **Eliminate False-Positive Reconnection Loops**: Resolved timestamp underflow/miscalculation after handshake, preventing premature timeout disconnect loops and ensuring rock-solid MQTT persistence.
* **Fix Top-Right "OFFLINE" Display When Telemetry Updates**: Overhauled `isPrinterOnline()` status evaluation; accurately displays `PRINT` / `PREP` / `PAUSE` / `DONE` / `ERR` / `IDLE` when valid telemetry arrives, only reverting to `OFFLINE` when disconnected or when the printer is genuinely offline.
* **Preserve Screen Telemetry Across Reconnects**: Reconnecting to the same printer preserves last-known metrics rather than clearing everything to `--`; accurately shows `OFFLINE` status and orange indicators during disconnection.

### 9. ✨ Web Layout Alignment, Asynchronous HTTP Queue & Glassmorphism UI Polish (v0.5.20)
* **WebUI Responsive Grid Alignment**: Overhauled the built-in web management console layout. Screen layout selection is upgraded to an expansive full-width card; Brightness Scheduling and Real-time Debug cards are symmetrically arranged side-by-side (`.paired-grid`) on PC screens, and debug logs feature auto-constrained height to deliver balanced proportions across mobile and desktop browsers.
* **Asynchronous Ready-Queue HTTP Service & Anti-Hang Protection**: Introduced `PendingHttpClient` asynchronous queue buffer with concurrent connection threshold (`MAX_PENDING_HTTP_CLIENTS = 8`), guarded by a 1500ms first-byte timeout window and scheduled per-loop batch processing (`HTTP_CLIENTS_PER_LOOP`). Enabled socket-level `setNoDelay(true)` to eliminate microcontroller loop hangs caused by burst browser pre-connections.
* **Micro-Tactile Glassmorphism Display UI Upgrade**: Introduced `drawGlassCard()` edge rendering with layered specular highlights and drop shadows (`C_GLASS_HI` highlight & `C_GLASS_LO` shadow edges), smooth two-tone progress indicators (`drawGlassProgress()`), and luminous accent accents. Compact speed indicators (`SIL 50%` / `STD 100%` / `SPT 124%` / `LUD 166%`) provide clearer layer and printing status.
* **Flicker-Free Safe Differential Redraw (Safe Redraw)**: Refactored `drawClassicBaseSafe`, `drawDashboardFieldsSafe`, and `drawClockScreenSafe` with comprehensive dirty-state caching, updating only modified bounding boxes to completely eliminate full-screen tearing, flickering, and ghosting.
* **Clock Standby & NTP Sync Refresh Scheduling**: Refined NTP synchronization checks in clock layout (graceful `SYNC...` state preventing redundant re-renders), decoupling idle frame updates to a single precise 1-second cadence to reduce background MCU load.

### 10. 🔄 v0.5.25 Display Rotation Configuration
* **90-degree rotation steps**: TFT content supports `0° / 90° / 180° / 270°`; classic, dashboard, and clock layouts share the same rotation setting.
* **Adjustable from both admin surfaces**: The ESP built-in page on port 8081 and the desktop Web configuration tool can both change the angle, with serial and HTTP configuration paths carrying the field.
* **Power-cycle persistence**: The setting is stored in LittleFS `/cloud.json` and restored automatically after reboot.
* **Redraw only when needed**: The screen clears and rebuilds its render cache only when the angle actually changes; normal data refreshes retain the existing partial-update strategy.
* **Version alignment**: Firmware, backend tooling, and both README documents are unified at `v0.5.25`.

---

## 🖼️ Interface & Hardware Previews

| Dashboard Layout (Dashboard + AMS) | Clock Standby Layout (Clock) |
| :---: | :---: |
| <img src="docs/images/dashboard-layout.jpg" width="340" /> | <img src="docs/images/clock-layout.jpg" width="340" /> |

### Web Backend Configuration Interface
<p align="center">
  <img src="docs/images/web-ui-preview.png" width="680" />
</p>

---

## 🏷️ Version Information

* **Firmware Version**: `v0.5.25`
* **Backend WebUI**: `v0.5.25`

---

## 📁 Directory Structure

```text
src/              ESP8266 firmware core C++ source code (main.cpp, config.h)
include/          TFT_eSPI display driver pin configuration
后端配置工具/     Windows Web configuration tool (server.js, 打开配置工具.bat)
固件/             Precompiled printsphere-lite-esp8266.bin
刷固件工具/       Windows one-click flashing tool and USB serial drivers
docs/             Documentation and assets
platformio.ini    PlatformIO project build configuration
build-release.ps1 Release package packaging script
```

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

1. Connect ESP8266 to your Windows PC using a USB data cable.
2. Open `后端配置工具\打开配置工具.bat`, which opens the WebUI in your default browser, and log in to your Bambu Lab account.
3. Select or enter your 2.4G Wi-Fi SSID and password, then click **“Save & Configure ESP WiFi”**.
4. Refresh printer list, select your target Bambu printer, and click **“Show This Printer & Sync”**.
5. Once print data appears on the ESP8266 screen, you can unplug the device from your computer and power it via any 5V USB source.
6. Once connected to Wi-Fi, you can also manage the device directly in your browser via `http://[ESP_IP_ADDRESS]:8081/`.

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
