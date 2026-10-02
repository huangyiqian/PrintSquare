// ============================================================
// SD2 PrintSquare - ESP8266 Bambu Cloud MQTT display
// ============================================================

#ifndef CONFIG_H
#define CONFIG_H

#define WIFI_SSID     ""
#define WIFI_PASSWORD ""

#define ESP_CONFIG_PORT 8081

#define MQTT_PORT 8883
#define MQTT_BUFFER_SIZE 12288
#define MQTT_RECONNECT_INTERVAL 3000
#define MQTT_REQUEST_INTERVAL 30000
// MQTT 连接正常但连续 90s 收不到打印机遥测数据（打印机关机）→ 判定离线
#define MQTT_OFFLINE_TIMEOUT 90000

#define DISPLAY_REFRESH 350

#endif
