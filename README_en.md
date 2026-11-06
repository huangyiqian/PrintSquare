# PrintSquare Dual-Printer Rotation

**One ESP8266 that alternates between two Bambu Lab printers.**

This is an enhanced branch of [huangyiqian/PrintSquare](https://github.com/huangyiqian/PrintSquare) (V0.5.40).
On top of upstream it adds dual-printer rotation, and replaces the desktop setup tool's
91 MB single-file exe with a readable `bat` + `server.js` (Node.js) launcher.

![Firmware](https://img.shields.io/badge/firmware-v0.5.40--rot-brightgreen)
![Backend](https://img.shields.io/badge/backend-v0.5.40--rot-blue)
![License](https://img.shields.io/badge/license-Non--Commercial-orange)

---

## What this fork adds

Upstream shows one printer per ESP (one cloud MQTT subscription).
With two printers and one small screen, this branch instead:

- subscribes to **both** `device/<serial>/report` topics on a **single MQTT connection**,
  keeping both printers updated in the background;
- swaps the two in-RAM states on a timer — **no reconnect, no data loss, no Flash writes**;
- offers **Off / 5 s / 10 s / 30 s** intervals from both the setup tool and the 8081 page (persisted);
- turns rotation off and the screen stays on the selected printer.

Scope: printers under the **same Bambu account** already synced to the ESP; **2 printers max** for now
(rotation pair = primary ↔ first other synced printer).

## Differences vs upstream V0.5.40

| | Upstream | This branch |
|---|---|---|
| MQTT subscriptions | 1 printer | **2 printers, rotating** |
| Screen | one printer | one printer, auto-switching |
| Setup tool | 91 MB single exe (Node SEA) | **bat + plain `server.js`** (Node.js 18+, or a portable node.exe) |
| Setup page | single-printer selection | new **“4. Dual-printer rotation”** panel: interval, partner, live state, role column |
| 8081 page | layout/brightness/rotation/mirror | adds a **Printer rotation** control |
| Status API | — | `rotate_sec` / `rotate_active` / `rotate_partner` / `display_serial` |
| Git history | includes early commits | **clean re-initialised history** (public code/docs only) |

Everything else (three layouts, AMS display, stage labels, CN/EN bitmap fonts, brightness schedule,
rotation/mirror, multi-ESP profiles, ports 80 + 8081) matches upstream V0.5.40.

## Hardware

- ESP8266EX / NodeMCU compatible board
- 240×240 7-pin ST7789 SPI display
- CH340/CH341 USB serial adapter (flashing / configuration)
- Default wiring: `CS=GPIO15`, `DC=GPIO0`, `RST=GPIO2`, `BL=GPIO5`

## Repository layout

```text
src/                  ESP8266 firmware (rotation lives in main.cpp)
include/              TFT_eSPI display config
platformio.ini        PlatformIO build (env: sd2)
docs/                 design notes, limits, on-device verification (Chinese)
tools/verify-rotation.js   LAN rotation check script
后端配置工具/          bat-based setup tool (server.js + 打开配置工具.bat)
刷固件工具/            one-click flashing scripts (esptool ships in the Release zip)
固件/                  prebuilt firmware
```

## Quick start

1. Install the CH340 driver and connect the ESP over USB.
2. Flash with `刷固件工具\一键刷入固件.bat` from the Release zip
   (default = no erase, keeps WiFi / token / printer selection).
3. Install Node.js 18+ (or drop a portable `node.exe` into `后端配置工具\node\`),
   then run `后端配置工具\打开配置工具.bat` → log in to Bambu → write your 2.4G WiFi.
4. Refresh the printer list, click “Show this one and sync” for the first printer, then again for the second —
   the ESP now has both in `/printers.json`.
5. Open “4. Dual-printer rotation” in the setup tool (or the 8081 page) and pick an interval.

## Rotation details

- Rotation pair = the primary printer ↔ the chosen partner (falls back to the first other synced printer).
- Applying rotation from the setup tool reorders the synced list as primary → partner → others,
  so the pair always matches what you picked.
- Both printers must share one account/region; the ESP subscribes to two report topics on one connection.
- Each switch redraws the screen once (sub-second, no TLS handshake). Turning rotation off unsubscribes the partner.
- Limit is 2 printers; more would need an array of printer states in the firmware (out of scope here).
- API: `GET /api/status` exposes `rotate_sec` / `rotate_active` / `rotate_partner` / `display_serial`;
  `POST /api/config` (or serial JSON) accepts `rotate_sec` (0, or 3–3600 s).
- Verify from a PC: `node tools/verify-rotation.js http://<ESP_IP>:8081`

## Setup tool notes

- Plain source: `打开配置工具.bat` + `server.js` (Node built-ins only, no `npm install`).
- Requires Node.js 18+; the bat looks for `后端配置工具\node\node.exe` first, then system `node`.
- `后端配置工具\data\` is created at runtime and contains your account token, WiFi and printer serials —
  **never commit or share it** (already excluded in `.gitignore`).
- Closing the bat window stops the local setup server; for daily use the ESP's own `http://ESP_IP:8081/` is enough.

## Build from source

```bash
platformio run -e sd2
# output: .pio/build/sd2/firmware.bin
```

## FAQ

- **No serial port / flashing fails**: install the CH340 driver, use a data-capable USB cable, close tools that hold
  the port, or hold BOOT while starting the flash.
- **`Node.js cannot be started`**: install Node.js 18+ or put a portable `node.exe` into `后端配置工具\node\`.
- **Rotation enabled but not switching**: make sure ≥2 printers are synced (`/api/printers` shows two) and check the
  serial log for `Cloud MQTT partner subscribed` and `[ROTATE] showing ...`.
- **Both printer names show `??`**: the setup tool writes serial config as ASCII, dropping Chinese names; toggle rotation
  once on the 8081 page or write names over HTTP to refresh.
- **8081 page unreachable**: confirm the ESP is on a 2.4 GHz network; re-read the IP from the setup tool.

## Credits & licence

- Based on [huangyiqian/PrintSquare](https://github.com/huangyiqian/PrintSquare) (V0.5.40);
- Upstream is based on [ccord34/printsphere-lite](https://github.com/ccord34/printsphere-lite);
- Personal, educational and non-commercial use only. Commercial use or mass production requires authorisation —
  see [LICENSE](LICENSE);
- Flashing and wiring are hardware operations: check your wiring and power, use at your own risk.

This repository uses a freshly initialised history (no upstream git history), containing only public
source, docs and prebuilt firmware.

[![](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)](https://github.com/deepseek-ai/deepseek-harness)
