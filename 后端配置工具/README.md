# PrintSquare 后端配置工具

这是 Windows 电脑端配置工具，用于完成 Bambu 云登录、ESP WiFi 写入、打印机列表读取和打印机选择。

客户入口（推荐）：

```text
PrintSquare配置工具.exe
```

单文件 exe，双击即用：它会自动清掉上次的状态、启动后端服务并打开浏览器配置页。窗口关掉服务就退出，不需要再管命令行。

如果 exe 被杀毒软件拦截或无法运行，可以退回原来的 bat 方式（需要保留 `node\node.exe` 与 `server.js`）：

```text
打开配置工具.bat
```

工具默认从 `8795` 端口启动。如果端口被占用，会自动尝试后续端口，并自动打开浏览器。

页面右上角可切换 **中文 / English**，选择会记在浏览器本地；页面配色、玻璃卡片、圆角与控件风格已与 ESP 内置网页后台（8081）统一。

## 重新打包 exe

修改过 `server.js` 之后需要重新生成 exe：

```text
双击运行 build-exe.ps1（或在终端 powershell -File build-exe.ps1）
```

脚本用 `node\node.exe` 作为 SEA 底座，把 `launcher.js` 与 `server.js` 打进一个 exe；首次构建会联网下载 postject 工具链（缓存在 `.exe-build\`）。产物 `PrintSquare配置工具.exe` 约 90MB，随发布包分发，不入 git。

## 配置步骤

1. 用 USB 将当前要配置的 ESP 连接到电脑。
2. 双击 `PrintSquare配置工具.exe`（或退回 `打开配置工具.bat`）。
3. 登录 Bambu 云服务账号。
4. 填写或选择 2.4G WiFi，点击“保存并配置 ESP WiFi”。
5. 设置屏幕亮度、`0° / 90° / 180° / 270°` 旋转角度和屏幕镜像（半透半反镜用：无 / 左右镜像）；点击“应用屏幕设置”写入当前 ESP。
6. 页面显示 WiFi 已配置后，刷新打印机列表。
7. 选择需要显示的打印机，点击“显示这台并同步”。
8. 屏幕开始刷新后，可以断开电脑 USB，改用普通 USB 电源。

屏幕亮度为 0-100% 手动设置，另可在 ESP 8081 后台配置「日间 / 夜间」分时段亮度规则，配置断电保存。早期版本“无任务或任务完成五分钟后自动降到 25%”的逻辑已在 v0.4.65 移除，现在不会自动降亮。

## ESP 局域网页面

ESP 连上 WiFi 后，可以访问：

```text
http://ESP的IP地址:8081/
```

电脑端配置工具会把打印机列表同步到 ESP 本地。同步完成后，电脑关闭时也可以通过 ESP 局域网页面切换已同步的打印机。

如果 ESP 页面显示“暂无已同步打印机”，请在电脑端确认 ESP 地址后点击“同步打印机列表到 ESP 本地网页”。

## 多台 ESP

建议一次只连接一台 ESP 到电脑。配置完当前设备后拔掉，再连接下一台。

工具会按 ESP 的 MAC / device_id 保存独立档案。Bambu 登录信息和默认 WiFi 可以复用，每台 ESP 的打印机选择独立保存。

## 运行时数据

以下文件会在客户电脑上自动生成，不能从测试电脑复制到交付包：

```text
data/config.json
data/devices.json
data/device-history.jsonl
data/server-state.json
```
