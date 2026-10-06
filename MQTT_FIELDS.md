# Bambu MQTT 可获取字段参考

本文档整理当前项目已经接入、解析或在界面中使用过的 Bambu 打印机状态字段，供其他项目参考。

注意：Bambu 不同机型、不同固件版本、是否连接 AMS、是否双喷嘴，返回字段会有差异。另一个项目接入时不要只依赖单一字段名，建议按本文的兼容规则解析。

## 1. 订阅与刷新方式

当前项目的思路：

- 每台打印机订阅对应设备的 MQTT 状态上报主题。
- 周期性发送 `pushall` 请求，让设备完整推送一次状态。
- 上屏、下屏各自关联一台设备，也可以进入待机页。
- 后台可以固定选择设备，也可以按打印状态和剩余时间做自动调度。

常见主题方向：

```text
device/{serial}/report
```

其中 `{serial}` 是设备序列号 / deviceId。

## 2. 设备基础信息

| 字段 | 类型 | 说明 |
|---|---:|---|
| `name` | string | 打印机名称，通常来自云端设备列表 |
| `deviceId` / `serial` | string | 设备 ID / 序列号 |
| `model` | string | 打印机型号，可能是底层型号值 |
| `taskImage` | string | 当前任务封面图地址，可能为空 |

### 型号映射

部分接口返回的是底层型号值，需要映射成用户可读型号。

| 显示型号 | 底层设备型号值 |
|---|---|
| X1C | `BL-P001` |
| P1P | `C11` |
| P1S | `C12` |
| X1E | `C13` |
| A1 mini | `N1` |
| A1 | `N2S` |
| X2D | `N6-V2` |
| P2S | `N7-V2` |
| H2C | `O1C2-V2` |
| H2D | `O1D` |
| H2S | `O1S` |

## 3. 打印状态

### 建议兼容读取字段

| 数据 | 兼容字段名 |
|---|---|
| 打印状态 | `printStatus`, `gcode_state`, `print_status`, `status`, `state` |

### 状态值映射

| 原始值 | 建议中文显示 |
|---|---|
| `RUNNING` | 打印中 |
| `FINISH` / `FINISHED` / `COMPLETE` | 完成 |
| `PAUSE` / `PAUSED` | 暂停 |
| `IDLE` | 空闲 |
| `FAILED` / `FAILURE` / `ERROR` | 失败 |
| `OFFLINE` | 离线 |
| `PREPARE` | 准备中 |
| `SLICING` | 切片中 |
| `INIT` | 初始化 |
| 其他未知值 | 未知，或直接显示原始值 |

注意事项：

- 未识别状态不要显示空白，至少显示“未知”或原始值。
- 状态字段在不同来源里字段名不完全一致，必须做多字段兼容。
- 如果日志里状态正常但屏幕不显示，优先检查 UI label 是否被隐藏、裁切、覆盖或画到屏幕外，不要只改解析层。

### 3.1 细分阶段（`stg_cur`）

`gcode_state` 只能区分"打印中 / 暂停 / 完成"，无法区分"正在自动调平""正在换料""正在回零"。
打印机在**同一个 `print` 对象**里额外上报当前动作阶段：

| 字段 | 类型 | 说明 |
|---|---:|---|
| `stg_cur` | number（个别固件回传字符串） | 当前动作阶段，取值 0–77 |
| `stg` | array | 本次打印将依次执行的阶段列表，可用于预判 |
| `mc_print_stage` / `mc_print_sub_stage` | number | 固件内部打印阶段，语义与 `stg_cur` **不同**，不建议当作细分状态使用 |

空闲值因机型而异：**X1 系列返回 `-1`，P1 系列返回 `255`**，两者都必须按"无细分阶段"处理。

> **本项目注意**：`parseMqttPayload()` 使用 `DeserializationOption::Filter(mqttFilter)` 做字段白名单，
> 未加入 `initMqttFilter()` 的字段会在解析前被直接丢弃。新增字段时**必须同时**加白名单
> （本项目已加入 `print.stg_cur`）。

#### `stg_cur` 完整枚举（0–77）

这是字段本身的取值范围，与本项目是否给某个值加标签无关。

| 值 | 枚举 | 值 | 枚举 | 值 | 枚举 |
|---:|---|---:|---|---:|---|
| 0 | `printing` | 26 | `paused_ams_lost` | 52 | `check_material` |
| 1 | `auto_bed_leveling` | 27 | `paused_low_fan_speed_heat_break` | 53 | `calibrating_live_view_camera` |
| 2 | `heatbed_preheating` | 28 | `paused_chamber_temperature_control_error` | 54 | `waiting_for_heatbed_temperature` |
| 3 | `sweeping_xy_mech_mode` | 29 | `cooling_chamber` | 55 | `check_material_position` |
| 4 | `changing_filament` | 30 | `paused_user_gcode` | 56 | `calibrating_cutter_model_offset` |
| 5 | `m400_pause` | 31 | `motor_noise_showoff` | 57 | `measuring_surface` |
| 6 | `paused_filament_runout` | 32 | `paused_nozzle_filament_covered_detected` | 58 | `thermal_preconditioning` |
| 7 | `heating_hotend` | 33 | `paused_cutter_error` | 59 | `homing_blade_holder` |
| 8 | `calibrating_extrusion` | 34 | `paused_first_layer_error` | 60 | `calibrating_camera_offset` |
| 9 | `scanning_bed_surface` | 35 | `paused_nozzle_clog` | 61 | `calibrating_blade_holder_position` |
| 10 | `inspecting_first_layer` | 36 | `check_absolute_accuracy_before_calibration` | 62 | `hotend_pick_place_test` |
| 11 | `identifying_build_plate_type` | 37 | `absolute_accuracy_calibration` | 63 | `waiting_chamber_temperature_equalize` |
| 12 | `calibrating_micro_lidar` | 38 | `check_absolute_accuracy_after_calibration` | 64 | `preparing_hotend` |
| 13 | `homing_toolhead` | 39 | `calibrate_nozzle_offset` | 65 | `calibrating_detection_nozzle_clumping` |
| 14 | `cleaning_nozzle_tip` | 40 | `bed_level_high_temperature` | 66 | `purifying_chamber_air` |
| 15 | `checking_extruder_temperature` | 41 | `check_quick_release` | 67 | `measuring_rotary_attachment` |
| 16 | `paused_user` | 42 | `check_door_and_cover` | 68 | `moving_toolhead_above_purge_chute` |
| 17 | `paused_front_cover_falling` | 43 | `laser_calibration` | 69 | `cooling_nozzle` |
| 18 | `calibrating_micro_lidar` | 44 | `check_plaform` | 70 | `moving_toolhead_to_center_of_heatbed` |
| 19 | `calibrating_extrusion_flow` | 45 | `check_birdeye_camera_position` | 71 | `active_arc_fitting` |
| 20 | `paused_nozzle_temperature_malfunction` | 46 | `calibrate_birdeye_camera` | 72 | `hotend_type_detection` |
| 21 | `paused_heat_bed_temperature_malfunction` | 47 | `bed_level_phase_1` | 73 | `build_plate_alignment_detection` |
| 22 | `filament_unloading` | 48 | `bed_level_phase_2` | 74 | `heatbed_surface_foreign_object_detection` |
| 23 | `paused_skipped_step` | 49 | `heating_chamber` | 75 | `heatbed_underside_foreign_object_detection` |
| 24 | `filament_loading` | 50 | `heated_bedcooling` | 76 | `pre_extrusion_before_printing` |
| 25 | `calibrating_motor_noise` | 51 | `print_calibration_lines` | 77 | `preparing_ams` |

#### 本项目实际加标签的阶段

只给 **A1 / P1 这类机型会用到的阶段**加标签，其余值命中时回退到"通用状态"（`PRINT`/`PREP`…）。
完整对照（含中文点阵字模像素图）见 [`docs/状态字模对照表.md`](docs/状态字模对照表.md)。

| `stg_cur` | 枚举 | 英文缩写 | 中文标签 |
|---:|---|---|---|
| 1 | `auto_bed_leveling` | `BEDLVL` | **自动调平** |
| 2 | `heatbed_preheating` | `BEDHEAT` | **热床预热** |
| 3 | `sweeping_xy_mech_mode` | `VIBRA` | **振动补偿** |
| 4 | `changing_filament` | `FILCHG` | **换料中** |
| 5 | `m400_pause` | `M400` | **暂停中** |
| 6 | `paused_filament_runout` | `RUNOUT` | **断料暂停** |
| 7 | `heating_hotend` | `NOZHEAT` | **喷嘴加热** |
| 8 | `calibrating_extrusion` | `EXTCAL` | **挤出校准** |
| 13 | `homing_toolhead` | `HOME` | **回零中** |
| 14 | `cleaning_nozzle_tip` | `NOZCLN` | **清洁喷嘴** |
| 16 | `paused_user` | `PAUSE` | **已暂停** |
| 22 | `filament_unloading` | `UNLOAD` | **退料中** |
| 24 | `filament_loading` | `LOAD` | **进料中** |
| 25 | `calibrating_motor_noise` | `MOTCAL` | **电机校准** |
| 30 | `paused_user_gcode` | `GCODE` | **指令暂停** |
| 32 | `paused_nozzle_filament_covered_detected` | `BLOB` | **喷嘴裹料** |
| 35 | `paused_nozzle_clog` | `CLOG` | **喷嘴堵塞** |
| 17、20、21、23、26、27、28、33、34 | *（未列出的 paused_\* 报错类，共 9 个值）* | `ERR` | **错误** |

#### 显示注意事项

- **只有"打印中 / 准备中 / 暂停中"才用细分阶段**；完成、失败、空闲、离线必须沿用
  `DONE` / `ERR` / `IDLE` / `OFFLINE`，否则阶段值滞后会把终态盖掉。
- 未收录的值（含 `-1`、`255`）回退到通用状态词，不要显示空白或原始数字。
- 中文标签用 **16x16 1bpp 点阵字模**（`src/cn_stage_glyphs.h`，Windows 黑体 `simhei.ttf`、
  16px、SingleBitPerPixelGridFit、取笔画外接框居中、阈值 127、MSB 先行，格式与
  `drawProgmemHexBitmap()` 一致）。16px 与字体 2 同高，所以三种布局都不用移动原有元素；
  标签最长 4 字共 70px（4*16+3*2），因此模型名限宽到 92px（经典 90、时钟 100）以免重叠。
- 显示中文还是英文由设备配置项 `lang`（`zh` / `en`）决定，由 8081 网页的中英文切换写入并断电保存。
- 阶段切换频繁（调平→预热→回零…），刷新策略仍是脏字段局部刷新，不要整屏重绘。

## 4. 打印进度

| 数据 | 类型 | 兼容字段名 |
|---|---:|---|
| 打印进度 | number | `printProgress`, `mc_percent`, `percent`, `progress` |
| 剩余时间，单位分钟 | number | `remainingTime`, `mc_remaining_time`, `remaining_minutes`, `remainingMinutes` |
| 当前层数 | number | `layerNum`, `layer_num`, `current_layer`, `currentLayer` |
| 总层数 | number | `totalLayerNum`, `total_layer_num`, `total_layers`, `totalLayers` |

注意事项：

- `remainingTime` 通常是分钟，需要前端转换成 `0min`、`1h 5min`、`122h 30min` 等显示格式。
- 层数为 `0/0`、缺字段或总层数为 0 时，界面应避免除零或显示异常。
- 长时间文本要考虑圆屏空间，必要时使用滚动或缩短格式。

## 5. 喷嘴温度

### 单喷嘴设备

单喷嘴设备通常返回：

| 字段 | 类型 | 说明 |
|---|---:|---|
| `activeNozzle` | string | 通常为 `single` |
| `nozzleTemp` | number | 主喷嘴当前温度 |
| `targetNozzleTemp` | number | 主喷嘴目标温度 |

兼容字段：

| 数据 | 兼容字段名 |
|---|---|
| 主喷嘴当前温度 | `nozzleTemp`, `nozzle_temper`, `nozzle_temp`, `nozzleTemperature` |
| 主喷嘴目标温度 | `targetNozzleTemp`, `nozzle_target_temper`, `target_nozzle_temp` |

显示建议：

- 单喷嘴设备只显示“主喷嘴”。
- 不要强行显示左喷嘴、右喷嘴，避免出现不存在的喷嘴温度。

### 双喷嘴设备

双喷嘴设备通常返回：

| 字段 | 类型 | 说明 |
|---|---:|---|
| `activeNozzle` | string | `left` / `right` |
| `leftNozzleTemp` | number | 左喷嘴当前温度 |
| `leftTargetNozzleTemp` | number | 左喷嘴目标温度 |
| `rightNozzleTemp` | number | 右喷嘴当前温度 |
| `rightTargetNozzleTemp` | number | 右喷嘴目标温度 |

兼容字段：

| 数据 | 兼容字段名 |
|---|---|
| 左喷嘴当前温度 | `leftNozzleTemp`, `left_nozzle_temp`, `left_nozzle_temper`, `tool0_nozzle_temp` |
| 左喷嘴目标温度 | `leftTargetNozzleTemp`, `left_target_nozzle_temp`, `tool0_target_nozzle_temp` |
| 右喷嘴当前温度 | `rightNozzleTemp`, `right_nozzle_temp`, `right_nozzle_temper`, `tool1_nozzle_temp` |
| 右喷嘴目标温度 | `rightTargetNozzleTemp`, `right_target_nozzle_temp`, `tool1_target_nozzle_temp` |

部分设备也可能通过嵌套结构返回：

```text
device.extruder.info[]
```

其中常见字段包括：

| 字段 | 说明 |
|---|---|
| `id` | 工具编号 |
| `temp` | 当前温度 |
| `target_temp` | 目标温度 |

注意事项：

- 双喷嘴模式只显示左喷嘴和右喷嘴，不显示主喷嘴。
- 不要把 `nozzleTemp` 当成第三个喷嘴。
- 未上报的喷嘴字段可能为空，应隐藏对应项目，不要显示历史值或默认值。
- 当前项目曾遇到过双喷嘴异常值，比如某个喷嘴温度被拼接成异常大数字，因此温度显示前建议做合理范围校验。

## 6. 热床与仓温

| 数据 | 类型 | 兼容字段名 |
|---|---:|---|
| 热床当前温度 | number | `bedTemp`, `bed_temper`, `bed_temp`, `bedTemperature` |
| 热床目标温度 | number | `targetBedTemp`, `bed_target_temper`, `bed_target_temp` |
| 仓温当前温度 | number | `chamberTemp`, `chamber_temper`, `chamber_temp`, `chamberTemperature` |
| 仓温目标温度 | number | `chamberTargetTemp`, `chamber_target_temper`, `chamber_target_temp` |

注意事项：

- 仓温优先使用 `chamberTemp`。
- 不是所有机型都有仓温传感器。没有仓温传感器时应隐藏仓温，不要显示默认值。
- P1S 等机型可能没有有效仓温传感器；P2S 等机型如果实际返回 `chamberTemp`，则可以显示。
- 不要把无效值、默认值或历史值当成真实仓温。

## 7. 灯光状态

| 字段 | 类型 | 说明 |
|---|---:|---|
| `chamberLight` / `chamber_light` | string | 主腔灯状态，常见值 `on` / `off` |
| `chamberLight2` / `chamber_light2` | string | 第二路腔灯状态，常见值 `on` / `off` |
| `workLight` / `work_light` | string | 工作灯状态，常见值 `on` / `off` |

部分设备可能通过数组返回：

```text
lights_report[]
```

其中可根据 `node` 判断：

| `node` | 说明 |
|---|---|
| `chamber_light` | 主腔灯 |
| `chamber_light2` | 第二路腔灯 |

当前项目 UI 后期只保留一个腔灯状态图标，通常优先使用 `chamberLight`。

## 8. 耗材类型

| 字段 | 类型 | 说明 |
|---|---:|---|
| `trayType` / `tray_type` | string | 当前使用中的耗材类型 |
| `filament_type` | string | 耗材类型兼容字段 |
| `vt_tray.tray_type` | string | 虚拟料盘 / 当前料盘里的耗材类型 |

当前可能值包括：

```text
ABS
ABS-GF
ASA
ASA-AERO
ASA-CF
BVOH
EVA
HIPS
PA
PA-CF
PA-GF
PA6-CF
PC
PCTG
PE
PE-CF
PET-CF
PETG
PETG-CF
PHA
PLA
PLA-AERO
PLA-CF
PP
PP-CF
PP-GF
PPA-CF
PPA-GF
PPS
PPS-CF
PVA
TPU
TPU-AMS
```

注意事项：

- `trayType` 表示当前使用中的耗材类型。
- 耗材类型不一定绝对来自 AMS。AMS 是外置设备，设备未连接 AMS 时也可能通过任务、虚拟料盘或其他状态字段提供耗材信息。
- 不要只依赖 AMS 槽位数据判断当前耗材。
- **`tray_type` / `filament_type` 是"当前正在使用的耗材"，AMS 打印时它来自 AMS 槽位，
  不能据此判断"外挂料盘存在"。** 判断外挂料盘要看 `vt_tray.tray_type`（为空即没有外挂料盘），
  判断外挂是否在用要看 `tray_now == 254`。`tray_now == 255` 表示**没有选中任何料盘**
  （不是外挂），把它当成外挂会在换料时把一个不存在的外挂槽点亮。
- 如果字段为空，UI 应隐藏耗材标签或显示“未知”，不要写死成 `PLA Basic`。

## 9. 错误信息

| 字段 | 类型 | 说明 |
|---|---:|---|
| `hmsErrors` | array | 当前 HMS 错误列表，只包含可展示字段 |

注意事项：

- HMS 错误列表可能为空。
- 另一个项目如果只做状态监控，可以先展示错误数量；后续再展开具体错误内容。

## 10. 项目内部状态，不一定来自打印机 MQTT

这些值当前项目会用到，但不一定是打印机 MQTT 原始字段：

| 数据 | 来源 | 说明 |
|---|---|---|
| Wi-Fi 图标 | ESP32 本机 Wi-Fi 状态 / RSSI | 表示监控屏自身网络连接 |
| MQTT 连接状态 | ESP32 内部状态 | 表示监控屏是否连上 MQTT |
| mDNS 地址 | ESP32 本机服务 | 例如 `bambu-monitor.local` |
| 后台 IP | ESP32 本机 WebServer | 例如 `http://192.168.x.x/` |

## 11. 接入时的重点注意事项

### 11.1 字段名必须兼容

同一含义可能存在多个字段名，例如打印状态可能来自：

```text
printStatus
gcode_state
print_status
status
state
```

不要只读一个字段。

### 11.2 不要显示无效默认值

以下情况建议隐藏，而不是显示假数据：

- 仓温字段不存在。
- 喷嘴字段为空。
- 双喷嘴设备没有上报其中一个喷嘴。
- 目标温度为空。
- 层数总数为 0。

### 11.3 UI 要防止长文本遮挡

圆屏空间很小，以下字段可能过长：

- 打印机名称
- 设备型号
- 耗材类型
- 剩余时间，例如 `122h 30min`
- 任务名称

建议策略：

- 短文本直接居中显示。
- 超过宽度的文本滚动显示。
- 滚动区域必须裁切，不能遮挡进度环或其他元素。

### 11.4 温度要做合理范围校验

建议显示前进行基础校验：

- 喷嘴温度通常不应为异常大数。
- 热床温度通常不应为异常大数。
- 仓温没有字段时不要用默认 0℃ 或 5℃ 误导用户。

### 11.5 耗材来源不要只看 AMS

AMS 是外置设备，不连接 AMS 时仍然可能有当前耗材类型。

推荐优先顺序：

1. 当前任务 / 当前使用中的 `trayType`
2. `vt_tray.tray_type`
3. 兼容字段 `filament_type`
4. AMS 当前槽位信息
5. 全部为空时隐藏或显示未知

### 11.6 状态更新后要触发 UI 刷新

解析成功不代表显示成功。另一个项目如果遇到状态不显示，应检查完整链路：

1. 原始 payload 是否有值。
2. 解析后的状态变量是否更新。
3. UI 刷新是否被触发。
4. label 是否可见。
5. label 是否被其他元素覆盖。
6. label 是否超出屏幕或裁切区域。

## 12. 当前项目尚未重点使用的扩展字段

这些字段后续可以继续扩展，但当前主界面没有作为核心展示：

| 字段 | 说明 |
|---|---|
| `taskImage` | 当前任务封面图 |
| `workLight` | 工作灯 |
| `hmsErrors` | HMS 错误 |
| 耗材颜色 | 当前项目未作为主要显示 |
| 风扇速度 | 当前项目未作为主要显示 |
| 打印任务名称 | 当前项目未作为主要显示 |

