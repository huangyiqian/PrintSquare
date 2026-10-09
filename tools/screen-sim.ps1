<#
.SYNOPSIS
  PrintSquare 屏幕仿真器 —— 在电脑上把 240x240 ST7789 屏幕按固件真实坐标画成 PNG，省去手机拍屏。

.DESCRIPTION
  状态来源：设备 GET /api/status（或 -Json 指定的离线快照）。
  画法与固件一一对应：
    - 字体直接解析 TFT_eSPI 的字体源文件：font1=glcdfont.c(5x8列向LSB在上)、
      font2=Font16.c(宽表+MSB位图)、font4=Font32rle.c(RLE)、font7=Font7srle.c(RLE)
      RLE 解码规则与 TFT_eSPI.cpp 一致：高位1=前景、长度=(字节&0x7F)+1；高位0=背景、长度=字节+1，
      按 width*height 线性行优先填充。
    - 中文点阵解析 src/cn_stage_glyphs.h（16x16、2字节/行、MSB 先行）
    - 颜色按 BGR565 解码（固件注释明确 ((B<<11)|(G<<5)|R)）
    - 三套布局的坐标、脏检查绘制顺序均抄自 src/main.cpp

  局限（诚实声明）：它是"按状态重画"，**不能复现渲染类 bug**（例如某处绘制被后一个函数覆盖、
  字宽溢出等实机才会出现的问题）——那种情况仍需实机拍照。定位是替代"日常看屏幕状态"的拍照。

.PARAMETER Url      设备地址，默认 http://192.168.31.114:8081
.PARAMETER Json     改为读本地 /api/status 快照（离线可用）
.PARAMETER Layout   auto=跟随设备 / all=三套都出 / classic|dashboard|clock
.PARAMETER Scale    放大倍数 1..8，默认 3（输出 720x720）
.PARAMETER OutDir   输出目录，默认 %TEMP%\PrintSquareSim
.PARAMETER ClockTime  时钟布局显示的时间，格式 HH:mm[:ss]，默认本机当前时间
.PARAMETER Alias    模拟设备端"别名"stored.alias（接口未暴露），默认空
.PARAMETER SplitSide  双喷嘴时固定显示哪一侧（0=左 1=右），固件按 millis 轮换，仿真固定

.EXAMPLE
  pwsh -File tools\screen-sim.ps1
.EXAMPLE
  pwsh -File tools\screen-sim.ps1 -Layout all -Scale 2
.EXAMPLE
  pwsh -File tools\screen-sim.ps1 -Json snapshot.json -Layout classic
#>
[CmdletBinding()]
param(
    [string]$Url = 'http://192.168.31.114:8081',
    [string]$Json = '',
    [ValidateSet('auto','all','classic','dashboard','clock')]
    [string]$Layout = 'auto',
    [ValidateRange(1,8)]
    [int]$Scale = 3,
    [string]$OutDir = '',
    [string]$ClockTime = '',
    [string]$Alias = '',
    [ValidateSet(0,1)]
    [int]$SplitSide = 0
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# ============================ 路径 ============================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
$RepoRoot = Split-Path -Parent $ScriptDir
$FontDir  = Join-Path $RepoRoot '.pio\libdeps\sd2\TFT_eSPI\Fonts'
$GlyphHdr = Join-Path $RepoRoot 'src\cn_stage_glyphs.h'
if (-not $OutDir) { $OutDir = Join-Path ([System.IO.Path]::GetTempPath()) 'PrintSquareSim' }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
if (-not (Test-Path $FontDir))  { throw "找不到 TFT_eSPI 字体目录：$FontDir（先跑一次 pio run 生成 .pio）" }
if (-not (Test-Path $GlyphHdr)) { throw "找不到中文字模：$GlyphHdr" }

# ============================ 颜色（BGR565） ============================
$BG_BLACK = 0x0000; $C_RING = 0x07E0; $C_TRACK = 0x2104; $C_TEXT = 0xFFFF
$C_DIM    = 0x8410; $C_CYAN = 0xFFE0; $C_ORANGE = 0x061F; $C_YELLOW = 0x07FF
$C_BLUE   = 0xF800; $C_RED  = 0x001F; $C_CARD  = 0x2903
$C_GLASS_BG = 0x1881; $C_GLASS_HI = 0x7B4A; $C_GLASS_LO = 0x1061
$FRAME_X = 4; $FRAME_Y = 4; $FRAME_SIZE = 232; $FRAME_THICK = 10; $FRAME_SIDE = 232
$FRAME_TOTAL = 928

$brushCache = @{}
function Get-Bgr565Color([int]$v565) {
    $b = ($v565 -shr 11) -band 0x1F
    $g = ($v565 -shr 5) -band 0x3F
    $r = $v565 -band 0x1F
    return [System.Drawing.Color]::FromArgb(255, [int]($r * 255 / 31), [int]($g * 255 / 63), [int]($b * 255 / 31))
}
function Get-Brush([int]$v565) {
    if (-not $brushCache.ContainsKey($v565)) {
        $brushCache[$v565] = New-Object System.Drawing.SolidBrush (Get-Bgr565Color $v565)
    }
    return $brushCache[$v565]
}
function New-Canvas {
    $script:Bmp = New-Object System.Drawing.Bitmap((240 * $Scale), (240 * $Scale))
    $script:Gfx = [System.Drawing.Graphics]::FromImage($script:Bmp)
    $script:Gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $script:Gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $script:Gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $script:Gfx.Clear((Get-Bgr565Color $BG_BLACK))
}
function Save-Canvas([string]$path) {
    $script:Bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $script:Gfx.Dispose(); $script:Bmp.Dispose()
}

# ============================ 像素原语（逻辑坐标 0..239） ============================
function Fill-Rect([int]$x, [int]$y, [int]$wid, [int]$hei, [int]$c) {
    if ($wid -le 0 -or $hei -le 0) { return }
    $s = $Scale
    $script:Gfx.FillRectangle((Get-Brush $c), ($x * $s), ($y * $s), ($wid * $s), ($hei * $s))
}
function Fill-HLine([int]$x, [int]$y, [int]$wid, [int]$c) { Fill-Rect $x $y $wid 1 $c }
function Fill-VLine([int]$x, [int]$y, [int]$hei, [int]$c) { Fill-Rect $x $y 1 $hei $c }

function Fill-RoundRect([int]$x, [int]$y, [int]$wid, [int]$hei, [int]$rad, [int]$c) {
    if ($wid -lt 2 -or $hei -lt 2) { return }
    if ($rad -lt 0) { $rad = 0 }
    if ($rad -gt [int]($wid / 2)) { $rad = [int]($wid / 2) }
    if ($rad -gt [int]($hei / 2)) { $rad = [int]($hei / 2) }
    if ($rad -le 0) { Fill-Rect $x $y $wid $hei $c; return }
    for ($row = 0; $row -lt $hei; $row++) {
        $cut = 0
        if ($row -le $rad) {
            $dy = $rad - $row
            $cut = $rad - [int][Math]::Floor([Math]::Sqrt([Math]::Max(0, $rad * $rad - $dy * $dy)))
        } elseif ($row -ge ($hei - 1 - $rad)) {
            $dy = $row - ($hei - 1 - $rad)
            $cut = $rad - [int][Math]::Floor([Math]::Sqrt([Math]::Max(0, $rad * $rad - $dy * $dy)))
        }
        Fill-Rect ($x + $cut) ($y + $row) ($wid - 2 * $cut) 1 $c
    }
}
function Outline-RoundRect([int]$x, [int]$y, [int]$wid, [int]$hei, [int]$rad, [int]$c, [int]$bg) {
    Fill-RoundRect $x $y $wid $hei $rad $c
    if ($wid -gt 2 -and $hei -gt 2) {
        Fill-RoundRect ($x + 1) ($y + 1) ($wid - 2) ($hei - 2) ([Math]::Max(0, $rad - 1)) $bg
    }
}
function Fill-Circle([int]$cx, [int]$cy, [int]$rad, [int]$c) {
    if ($rad -lt 0) { return }
    for ($dy = -$rad; $dy -le $rad; $dy++) {
        $hw = [int][Math]::Floor([Math]::Sqrt([Math]::Max(0, $rad * $rad - $dy * $dy)))
        Fill-Rect ($cx - $hw) ($cy + $dy) (2 * $hw + 1) 1 $c
    }
}
function Draw-CircleOutline([int]$cx, [int]$cy, [int]$rad, [int]$c) {
    for ($dy = -$rad; $dy -le $rad; $dy++) {
        $hw = [int][Math]::Floor([Math]::Sqrt([Math]::Max(0, $rad * $rad - $dy * $dy)))
        Fill-Rect ($cx - $hw) ($cy + $dy) 1 1 $c
        Fill-Rect ($cx + $hw) ($cy + $dy) 1 1 $c
    }
}
function Fill-Triangle([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$x3, [int]$y3, [int]$c) {
    $s = $Scale
    $pts = @(
        (New-Object System.Drawing.Point(($x1 * $s), ($y1 * $s))),
        (New-Object System.Drawing.Point(($x2 * $s), ($y2 * $s))),
        (New-Object System.Drawing.Point(($x3 * $s), ($y3 * $s)))
    )
    $script:Gfx.FillPolygon((Get-Brush $c), $pts)
}
# 1bpp 位图（MSB 先行、行优先）——BAMBU_LOGO 与中文字模共用
function Draw-GlyphBits([byte[]]$bytes, [int]$wid, [int]$hei, [int]$px, [int]$py, [int]$c) {
    $bpr = [int][Math]::Floor(($wid + 7) / 8)
    for ($row = 0; $row -lt $hei; $row++) {
        for ($col = 0; $col -lt $wid; $col++) {
            $bi = $row * $bpr + [int][Math]::Floor($col / 8)
            if ($bi -ge $bytes.Length) { break }
            if (($bytes[$bi] -band (0x80 -shr ($col % 8))) -ne 0) { Fill-Rect ($px + $col) ($py + $row) 1 1 $c }
        }
    }
}

# ============================ 预处理器（字体源里的 #ifdef） ============================
# 固件未定义 TFT_ESPI_GRAVE_IS_DEGREE / FONT_4_GBP 等宏，等价于取 #else 分支
function Resolve-CPreprocessor([string]$text) {
    $out = New-Object System.Text.StringBuilder
    $stack = New-Object System.Collections.ArrayList
    foreach ($line in ($text -split "`r?`n")) {
        $trim = $line.Trim()
        if ($trim -match '^#\s*(ifdef|ifndef)\s+(\S+)') {
            $active = $false
            if ($Matches[1] -eq 'ifndef') { $active = $true }
            [void]$stack.Add(@{ Active = $active })
            continue
        }
        if ($trim -match '^#\s*if\b') { [void]$stack.Add(@{ Active = $false }); continue }
        if ($trim -match '^#\s*else') { if ($stack.Count -gt 0) { $stack[$stack.Count - 1].Active = -not $stack[$stack.Count - 1].Active }; continue }
        if ($trim -match '^#\s*endif') { if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count - 1) }; continue }
        $keep = $true
        foreach ($fr in $stack) { if (-not $fr.Active) { $keep = $false; break } }
        if ($keep) { [void]$out.AppendLine($line) }
    }
    return $out.ToString()
}

# ============================ 字体解析 ============================
function Read-HexArray([string]$text, [string]$re) {
    $m = [regex]::Match($text, $re)
    if (-not $m.Success) { throw "解析失败：$re" }
    $body = ($m.Groups[1].Value -replace '//[^\r\n]*', '')
    $bytes = [regex]::Matches($body, '0x([0-9A-Fa-f]{1,2})') | ForEach-Object { [Convert]::ToByte($_.Groups[1].Value, 16) }
    return ,[byte[]]$bytes
}
function Read-WidthTable([string]$text, [string]$name) {
    $m = [regex]::Match($text, [regex]::Escape($name) + '\s*\[\s*96\s*\]\s*=\s*(?://[^\r\n]*)?\s*\{([\s\S]*?)\}')
    if (-not $m.Success) { throw "找不到宽度表 $name" }
    $body = ($m.Groups[1].Value -replace '//[^\r\n]*', '')
    $nums = @([regex]::Matches($body, '\d+') | ForEach-Object { [int]$_.Value })
    if ($nums.Count -lt 96) { throw "$name 解析出 $($nums.Count) 个值，期望 96" }
    return ,$nums[0..95]
}
function Read-GlyphMap([string]$text, [string]$prefix, [int]$minCount = 90) {
    $map = @{}
    $pat = [regex]::Escape($prefix) + '_(?<n>[0-9A-Fa-f]{2})\s*\[\s*\d*\s*\]\s*=\s*(?://[^\r\n]*)?\r?\n?\s*\{(?<body>[\s\S]*?)\}'
    foreach ($m in [regex]::Matches($text, $pat)) {
        $code = [Convert]::ToInt32($m.Groups['n'].Value, 16)
        $body = $m.Groups['body'].Value -replace '//[^\r\n]*', ''
        $bb = [regex]::Matches($body, '0x([0-9A-Fa-f]{1,2})') | ForEach-Object { [Convert]::ToByte($_.Groups[1].Value, 16) }
        $map[$code] = [byte[]]$bb
    }
    if ($map.Count -lt $minCount) { throw "$prefix 只解析到 $($map.Count) 个字形" }
    return $map
}
function Get-FontMacro([string]$text, [string]$name) {
    if ($text -match "#define\s+$name\s+(\d+)") { return [int]$Matches[1] }
    return 0
}

Write-Host '[1/4] 解析字体与字模...'
$glcdSrc = Resolve-CPreprocessor (Get-Content -LiteralPath (Join-Path $FontDir 'glcdfont.c') -Raw -Encoding UTF8)
$GlcdFont = Read-HexArray $glcdSrc 'font\s*\[\s*\]\s*PROGMEM\s*=\s*\{([\s\S]*?)\}'

$f16Src = Resolve-CPreprocessor (Get-Content -LiteralPath (Join-Path $FontDir 'Font16.c') -Raw -Encoding UTF8)
$W16 = Read-WidthTable $f16Src 'widtbl_f16'
$G16 = Read-GlyphMap $f16Src 'chr_f16'

$f32Src = Resolve-CPreprocessor (Get-Content -LiteralPath (Join-Path $FontDir 'Font32rle.c') -Raw -Encoding UTF8)
$W32 = Read-WidthTable $f32Src 'widtbl_f32'
$G32 = Read-GlyphMap $f32Src 'chr_f32'
$h32 = Get-FontMacro (Get-Content -LiteralPath (Join-Path $FontDir 'Font32rle.h') -Raw -Encoding UTF8) 'chr_hgt_f32'
if ($h32 -le 0) { $h32 = 26 }

$f7sSrc = Resolve-CPreprocessor (Get-Content -LiteralPath (Join-Path $FontDir 'Font7srle.c') -Raw -Encoding UTF8)
$W7S = Read-WidthTable $f7sSrc 'widtbl_f7s'
$G7S = Read-GlyphMap $f7sSrc 'chr_f7s' 12   # font7 是精简字体：只有 空格 - . 0-9 :
$h7s = Get-FontMacro (Get-Content -LiteralPath (Join-Path $FontDir 'Font7srle.h') -Raw -Encoding UTF8) 'chr_hgt_f7s'
if ($h7s -le 0) { $h7s = 48 }

$CnHdr = Resolve-CPreprocessor (Get-Content -LiteralPath $GlyphHdr -Raw -Encoding UTF8)
$CnGlyphs = @{}
$mG = [regex]::Match($CnHdr, 'CN_GLYPH\[CN_GLYPH_COUNT\]\[[^\]]*\]\s*PROGMEM\s*=\s*\{([\s\S]*?)\n\};')
if (-not $mG.Success) { throw '解析 CN_GLYPH 失败' }
foreach ($m in [regex]::Matches($mG.Groups[1].Value, '"([0-9a-f]{64})"')) {
    $hx = $m.Groups[1].Value
    $bb = New-Object byte[] 32
    for ($ix = 0; $ix -lt 32; $ix++) { $bb[$ix] = [Convert]::ToByte($hx.Substring($ix * 2, 2), 16) }
    $CnGlyphs[$CnGlyphs.Count] = [byte[]]$bb
}
$CnLabelGlyph = @{}
$mL = [regex]::Match($CnHdr, 'CN_LABEL_GLYPH\[CN_LABEL_COUNT\][\s\S]*?=\s*\{([\s\S]*?)\n\};')
if (-not $mL.Success) { throw '解析 CN_LABEL_GLYPH 失败' }
$li = 0
foreach ($m in [regex]::Matches($mL.Groups[1].Value, '\{([^}]*)\}')) {
    $vals = @($m.Groups[1].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    # 字形索引是十进制，填充用的 0xFF 是十六进制字面量 —— 两种都要认
    $arr = @()
    foreach ($v in $vals) {
        if ($v -like '0x*') { $arr += [Convert]::ToByte($v.Substring(2), 16) }
        else { $arr += [Convert]::ToByte($v, 10) }
    }
    $CnLabelGlyph[$li] = $arr; $li++
}
$StageEn = @()
$mE = [regex]::Match($CnHdr, 'CN_STAGE_EN\[78\]\[\d+\]\s*PROGMEM\s*=\s*\{([\s\S]*?)\n\};')
if (-not $mE.Success) { throw '解析 CN_STAGE_EN 失败' }
foreach ($m in [regex]::Matches($mE.Groups[1].Value, '"([A-Z0-9]*)"')) { $StageEn += $m.Groups[1].Value }
Write-Host ("      字体1={0}字节 font2字形={1} font4字形={2}(h{3}) font7字形={4}(h{5}) 中文字模={6} 标签={7} 缩写={8}" -f `
    $GlcdFont.Length, $G16.Count, $G32.Count, $h32, $G7S.Count, $h7s, $CnGlyphs.Count, $CnLabelGlyph.Count, $StageEn.Count)

# ============================ 读状态 ============================
Write-Host '[2/4] 读取设备状态...'
if ($Json) {
    $state = Get-Content -LiteralPath $Json -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $state = (Invoke-WebRequest -Uri "$Url/api/status" -TimeoutSec 20 -UseBasicParsing).Content | ConvertFrom-Json
}
$SOnline   = [bool]($state.online)
$SMqtt     = [bool]($state.mqtt_connected)
$SStatus   = [string]($state.status)
$SLang     = [string]($state.lang)
if (-not $SLang) { $SLang = 'en' }
$SStageCur = if ($null -ne $state.stage_cur) { [int]$state.stage_cur } else { -1 }
$SProg     = if ($null -ne $state.progress) { [double]$state.progress } else { -1.0 }
$SNozzle   = if ($null -ne $state.nozzle_temp) { [double]$state.nozzle_temp } else { -1.0 }
$SLeftNz   = if ($null -ne $state.left_nozzle_temp) { [double]$state.left_nozzle_temp } else { -1.0 }
$SRightNz  = if ($null -ne $state.right_nozzle_temp) { [double]$state.right_nozzle_temp } else { -1.0 }
$SDual     = [bool]($state.dual_nozzle)
$SBed      = if ($null -ne $state.bed_temp) { [double]$state.bed_temp } else { -1.0 }
$SChamber  = if ($null -ne $state.chamber_temp) { [double]$state.chamber_temp } else { -1.0 }
$SHasCham  = [bool]($state.has_chamber_sensor)
$SRemain   = if ($null -ne $state.remaining_min) { [int]$state.remaining_min } else { -1 }
$SCurLay   = if ($null -ne $state.current_layer) { [int]$state.current_layer } else { -1 }
$STotLay   = if ($null -ne $state.total_layers) { [int]$state.total_layers } else { -1 }
$SSpdLvl   = if ($null -ne $state.spd_lvl) { [int]$state.spd_lvl } else { -1 }
$SSpdMag   = if ($null -ne $state.spd_mag) { [int]$state.spd_mag } else { -1 }
$SName     = [string]($state.name)
$SModel    = [string]($state.model)
$SAms      = $state.ams
$SExt      = $state.ext
$SDevLang  = $SLang

if ($Layout -eq 'auto') {
    $devLayout = [string]($state.layout)
    if (-not $devLayout) { $devLayout = 'dashboard' }
    $layouts = @($devLayout)
} elseif ($Layout -eq 'all') { $layouts = @('classic','dashboard','clock') } else { $layouts = @($Layout) }

Write-Host ('      layout={0} lang={1} status={2} stage_cur={3} progress={4}% model={5} name={6}' -f `
    ($layouts -join ','), $SLang, $SStatus, $SStageCur, $SProg, $SModel, $SName)

# ============================ 状态谓词（抄固件） ============================
function Test-Has([string]$txt, [string]$tok) {
    if (-not $txt) { return $false }
    return $txt.ToLower().Contains($tok)
}
$SOnlineCalc = $SMqtt -and $SOnline -and (-not (Test-Has $SStatus 'offline')) -and (-not (Test-Has $SStatus 'disconnect'))
function Test-Printing   { $t = $SStatus; (Test-Has $t 'running') -or (Test-Has $t 'printing') -or (Test-Has $t 'processing') }
function Test-Preparing  { $t = $SStatus; (Test-Has $t 'prepare') -or (Test-Has $t 'starting') -or (Test-Has $t 'heating') -or (Test-Has $t 'download') -or ($t -ieq 'init') -or ($t -ieq 'slicing') }
function Test-Paused     { Test-Has $SStatus 'pause' }
function Test-Finished   { $t = $SStatus; (Test-Has $t 'finish') -or (Test-Has $t 'success') -or (Test-Has $t 'done') -or (Test-Has $t 'complete') }
function Test-Failed     { $t = $SStatus; (Test-Has $t 'fail') -or (Test-Has $t 'error') -or (Test-Has $t 'cancel') }
function Get-StatusText {
    if (-not $SOnlineCalc) { return 'offline' }
    if (Test-Printing)  { return 'printing' }
    if (Test-Preparing) { return 'prepare' }
    if (Test-Paused)    { return 'paused' }
    if (Test-Finished)  { return 'done' }
    if (Test-Failed)    { return 'error' }
    return 'idle'
}
function Get-DashStatusText {
    if (-not $SOnlineCalc) { return 'OFFLINE' }
    if (Test-Printing)  { return 'PRINT' }
    if (Test-Preparing) { return 'PREP' }
    if (Test-Paused)    { return 'PAUSE' }
    if (Test-Finished)  { return 'DONE' }
    if (Test-Failed)    { return 'ERR' }
    return 'IDLE'
}
function Get-StatusColor {
    if (-not $SOnlineCalc) { return $C_ORANGE }
    if (Test-Printing)  { return $C_RING }
    if (Test-Preparing) { return $C_CYAN }
    if (Test-Paused)    { return $C_ORANGE }
    if (Test-Finished)  { return $C_BLUE }
    if (Test-Failed)    { return $C_RED }
    return $C_DIM
}
$IsEn = ($SLang -ne 'zh')
function Get-StageAbbrev {
    if ($SStageCur -lt 0 -or $SStageCur -ge $StageEn.Count) { return '' }
    return $StageEn[$SStageCur]
}
function Get-HeaderStatusText([string]$fallback) {
    if ($SOnlineCalc -and ((Test-Printing) -or (Test-Preparing) -or (Test-Paused))) {
        $stage = Get-StageAbbrev
        if ($stage) { return $stage }
    }
    return $fallback
}
function Get-GenericCnLabel {
    if (-not $SOnlineCalc) { return 84 }
    if (Test-Printing)  { return 78 }
    if (Test-Preparing) { return 79 }
    if (Test-Paused)    { return 80 }
    if (Test-Finished)  { return 81 }
    if (Test-Failed)    { return 82 }
    return 83
}
function Get-CurrentCnLabel {
    if ($SOnlineCalc -and ((Test-Printing) -or (Test-Preparing) -or (Test-Paused))) {
        if ((Get-StageAbbrev)) { return $SStageCur }
    }
    return (Get-GenericCnLabel)
}
function Test-PureAscii([string]$s) {
    if (-not $s -or $s.Length -eq 0) { return $false }
    foreach ($ch in $s.ToCharArray()) { if ([int][char]$ch -gt 127) { return $false } }
    return $true
}
function Get-NormalizedModel([string]$value) {
    $raw = ''; if ($value) { $raw = $value.Trim() }
    $key = $raw.ToUpper().Replace('-', '').Replace('_', '').Replace(' ', '')
    if (-not $key) { return $raw }
    if ($key -eq 'BLP001' -or $key.Contains('X1C') -or $key.Contains('X1CARBON')) { return 'X1C' }
    if ($key -eq 'C11' -or $key.Contains('P1P'))  { return 'P1P' }
    if ($key -eq 'C12' -or $key.Contains('P1S'))  { return 'P1S' }
    if ($key -eq 'C13' -or $key.Contains('X1E'))  { return 'X1E' }
    if ($key -eq 'N1' -or $key.Contains('A1MINI')) { return 'A1 mini' }
    if ($key -eq 'N2S' -or $key -eq 'A1') { return 'A1' }
    if ($key -eq 'N6V2' -or $key.Contains('X2D')) { return 'X2D' }
    if ($key -eq 'N7V2' -or $key.Contains('P2S')) { return 'P2S' }
    if ($key -eq 'O1C2V2' -or $key.Contains('H2C')) { return 'H2C' }
    if ($key -eq 'O1D' -or $key.Contains('H2D'))  { return 'H2D' }
    if ($key -eq 'O1S' -or $key.Contains('H2S'))  { return 'H2S' }
    return $raw
}
function Get-TopLeftDisplayName {
    $candidate = ''
    if ($Alias -and $Alias.Length -gt 0) { $candidate = $Alias }
    elseif ($SName) { $candidate = $SName }
    if ($candidate -and (Test-PureAscii $candidate)) { return $candidate }
    return (Get-NormalizedModel $SModel)
}
function Get-NozzleSide {
    if ($SDual -and $SLeftNz -ge 0 -and $SRightNz -ge 0) { return $SplitSide }
    if ($SDual -and $SLeftNz -ge 0) { return 0 }
    if ($SDual -and $SRightNz -ge 0) { return 1 }
    return -1
}
function Get-DisplayedNozzle {
    $side = Get-NozzleSide
    if ($side -eq 0) { return $SLeftNz }
    if ($side -eq 1) { return $SRightNz }
    return $SNozzle
}
function Get-TimeText([int]$mins) {
    if ($mins -lt 0) { return '--' }
    $hh = [int][Math]::Floor($mins / 60); $mm = $mins % 60
    if ($hh -gt 0) { return ('{0}h{1:d2}m' -f $hh, $mm) }
    return ('{0}m' -f $mm)
}
function Get-ClassicRemaining([int]$mins) {
    if ($mins -lt 0) { return '--' }
    $hh = [int][Math]::Floor($mins / 60); $mm = $mins % 60
    if ($hh -gt 0) { return ('{0}h{1:d2}' -f $hh, $mm) }
    return ('{0}m' -f $mm)
}
function Get-EtaText([int]$mins) {
    if ($mins -lt 0) { return '--' }
    $now = [int][Math]::Floor(((Get-Date).ToUniversalTime() - [datetime]'1970-01-01').TotalSeconds)
    if ($now -lt 1700000000) { return '~' }
    $t = (Get-Date).AddMinutes($mins)
    return ('{0:d2}:{1:d2}' -f $t.Hour, $t.Minute)
}
function Get-CompactSpeed {
    if ($SSpdLvl -eq 1) { return 'SIL {0}%' -f $(if ($SSpdMag -gt 0) { $SSpdMag } else { 50 }) }
    if ($SSpdLvl -eq 2) { return 'STD {0}%' -f $(if ($SSpdMag -gt 0) { $SSpdMag } else { 100 }) }
    if ($SSpdLvl -eq 3) { return 'SPT {0}%' -f $(if ($SSpdMag -gt 0) { $SSpdMag } else { 124 }) }
    if ($SSpdLvl -eq 4) { return 'LUD {0}%' -f $(if ($SSpdMag -gt 0) { $SSpdMag } else { 166 }) }
    return 'SPD --'
}
function Get-ProgressLen {
    $p = $SProg
    if ($p -lt 0) { return 0 }
    if ($p -gt 100) { $p = 100 }
    $len = [int]($p * $FRAME_TOTAL / 100 + 0.5)
    if ($p -gt 0 -and $len -lt 1) { $len = 1 }
    if ($len -gt $FRAME_TOTAL) { $len = $FRAME_TOTAL }
    return $len
}

# ============================ 文本状态与字体渲染 ============================
$TxtFont = 2; $TxtDatum = 'TL'; $TxtFg = $C_TEXT; $TxtBg = $BG_BLACK
function Set-Txt([int]$font, [string]$datum, [int]$fg, [int]$bg) {
    $script:TxtFont = $font; $script:TxtDatum = $datum; $script:TxtFg = $fg; $script:TxtBg = $bg
}
function Get-FontHeight([int]$font) {
    switch ($font) { 1 { return 8 } 2 { return 16 } 4 { return $h32 } 7 { return $h7s } default { return 16 } }
}
function Get-TextWidth([string]$text, [int]$font) {
    if (-not $text -or $text.Length -eq 0) { return 0 }
    if ($font -eq 1) { return $text.Length * 6 }
    $tbl = $null
    switch ($font) { 2 { $tbl = $W16 } 4 { $tbl = $W32 } 7 { $tbl = $W7S } }
    if (-not $tbl) { return $text.Length * 6 }
    $sum = 0
    foreach ($ch in $text.ToCharArray()) {
        $code = [int][char]$ch
        if ($code -gt 31 -and $code -lt 128) { $sum += $tbl[$code - 32] } else { $sum += $tbl[0] }
    }
    return $sum
}
function Get-FitText([string]$text, [int]$font, [int]$maxW, [bool]$bold) {
    $boldPad = $(if ($bold) { 1 } else { 0 })
    $suffixW = (Get-TextWidth '..' $font) + $boldPad
    if ((Get-TextWidth $text $font) + $boldPad -le $maxW) { return $text }
    $t = $text
    while ($t.Length -gt 0 -and ((Get-TextWidth $t $font) + $suffixW + $boldPad) -gt $maxW) {
        $t = $t.Substring(0, $t.Length - 1)
    }
    if ($t.Length -gt 0) { return $t + '..' } else { return '..' }
}
function Draw-GlcdChar([int]$code, [int]$px, [int]$py, [int]$fg, [int]$bg) {
    if ($bg -ne $fg) { Fill-Rect $px $py 6 8 $bg }
    for ($col = 0; $col -lt 5; $col++) {
        $idx = $code * 5 + $col
        if ($idx -ge $GlcdFont.Length) { break }
        $bits = $GlcdFont[$idx]
        if ($bits -eq 0) { continue }
        for ($row = 0; $row -lt 8; $row++) {
            if (($bits -band (1 -shl $row)) -ne 0) { Fill-Rect ($px + $col) ($py + $row) 1 1 $fg }
        }
    }
}
function Draw-F16Char([int]$code, [int]$px, [int]$py, [int]$fg, [int]$bg) {
    $wid = $W16[$code - 32]
    if ($wid -le 0) { return }
    $data = $G16[$code]
    if (-not $data) { return }
    $bpr = [int][Math]::Floor(($wid + 6) / 8)
    if ($bg -ne $fg) { Fill-Rect $px $py $wid 16 $bg }
    for ($row = 0; $row -lt 16; $row++) {
        for ($k = 0; $k -lt $bpr; $k++) {
            $idx = $row * $bpr + $k
            if ($idx -ge $data.Length) { break }
            $bits = $data[$idx]
            if ($bits -eq 0) { continue }
            for ($bit = 0; $bit -lt 8; $bit++) {
                $col = $k * 8 + $bit
                if ($col -ge $wid) { break }
                if (($bits -band (0x80 -shr $bit)) -ne 0) { Fill-Rect ($px + $col) ($py + $row) 1 1 $fg }
            }
        }
    }
}
function Draw-RleChar([hashtable]$map, [int[]]$tbl, [int]$code, [int]$px, [int]$py, [int]$hei, [int]$fg, [int]$bg) {
    $wid = $tbl[$code - 32]
    if ($wid -le 0) { return }
    $data = $map[$code]
    if (-not $data) {
        # chrtbl_f7s 把未定义字符全部指向空格字形 —— 复刻这个别名
        $data = $map[32]
        if (-not $data) { return }
    }
    $total = $wid * $hei
    $lin = 0; $ix = 0
    $transparent = ($bg -eq $fg)
    while ($lin -lt $total -and $ix -lt $data.Length) {
        $byte = $data[$ix]; $ix++
        $isFg = (($byte -band 0x80) -ne 0)
        $n = if ($isFg) { ($byte -band 0x7F) + 1 } else { $byte + 1 }
        $colr = if ($isFg) { $fg } else { $bg }
        $skip = $transparent -and (-not $isFg)
        while ($n -gt 0 -and $lin -lt $total) {
            $colX = $lin % $wid
            $rowY = [int][Math]::Floor($lin / $wid)
            $run = [Math]::Min($n, ($wid - $colX))
            if (-not $skip) { Fill-Rect ($px + $colX) ($py + $rowY) $run 1 $colr }
            $lin += $run; $n -= $run
        }
    }
}
function Draw-Text([string]$text, [int]$x, [int]$y) {
    if (-not $text -or $text.Length -eq 0) { return }
    $font = $TxtFont; $datum = $TxtDatum; $fg = $TxtFg; $bg = $TxtBg
    $wid = Get-TextWidth $text $font
    $hei = Get-FontHeight $font
    $left = $x; $top = $y
    if ($datum -eq 'TR')     { $left = $x - $wid }
    elseif ($datum -eq 'MC') { $left = $x - [int]([Math]::Floor($wid / 2)); $top = $y - [int]([Math]::Floor($hei / 2)) }
    $cursor = $left
    foreach ($ch in $text.ToCharArray()) {
        $code = [int][char]$ch
        if ($code -lt 32 -or $code -gt 126) { $cursor += 6; continue }
        switch ($font) {
            1 { Draw-GlcdChar $code $cursor $top $fg $bg; $cursor += 6 }
            2 { Draw-F16Char $code $cursor $top $fg $bg; $cursor += $W16[$code - 32] }
            4 { Draw-RleChar $G32 $W32 $code $cursor $top $h32 $fg $bg; $cursor += $W32[$code - 32] }
            7 { Draw-RleChar $G7S $W7S $code $cursor $top $h7s $fg $bg; $cursor += $W7S[$code - 32] }
            default { $cursor += 6 }
        }
    }
}
function Draw-TextBox([int]$x, [int]$y, [int]$wid, [int]$hei, [int]$font, [int]$color, [string]$text, [bool]$bold, [int]$bg) {
    Fill-Rect $x $y $wid $hei $bg
    Set-Txt $font 'MC' $color $bg
    $cx = $x + [int][Math]::Floor($wid / 2); $cy = $y + [int][Math]::Floor($hei / 2)
    if ($bold) { Draw-Text $text $cx $cy; Draw-Text $text ($cx + 1) $cy } else { Draw-Text $text $cx $cy }
}
function Draw-CnLabelRight([int]$rightX, [int]$topY, [int]$labelIdx, [int]$color) {
    $ids = $CnLabelGlyph[$labelIdx]
    if (-not $ids) { return }
    $chars = @()
    foreach ($gi in $ids) { if ($gi -eq 0xFF) { break }; $chars += $gi }
    $n = $chars.Count
    if ($n -le 0) { return }
    $totalW = (16 * $n) + (2 * ($n - 1))
    $startX = $rightX - $totalW
    for ($k = 0; $k -lt $n; $k++) {
        # 注意：$chars 是 byte，字模表键是 int —— 必须显式转 int 才能查到
        Draw-GlyphBits $CnGlyphs[[int]$chars[$k]] 16 16 ($startX + ($k * 18)) $topY $color
    }
}
function Draw-HeaderStatus([int]$rightX, [int]$topY, [string]$enFallback, [int]$color) {
    if (-not $IsEn) {
        $label = Get-CurrentCnLabel
        if ($label -ne 255) { Draw-CnLabelRight $rightX $topY $label $color; return }
    }
    Set-Txt 2 'TR' $color $C_CARD
    $txt = Get-HeaderStatusText $enFallback
    Draw-Text (Get-FitText $txt 2 58 $false) $rightX $topY
}

# ============================ 玻璃组件（抄固件） ============================
function Glass-Card([int]$x, [int]$y, [int]$wid, [int]$hei, [int]$rad, [int]$bg, [int]$border, [int]$accent) {
    if ($wid -lt 4 -or $hei -lt 4) { return }
    Fill-RoundRect $x $y $wid $hei $rad $bg
    Outline-RoundRect $x $y $wid $hei $rad $border $bg
    $inset = [Math]::Min($rad, [Math]::Min([int][Math]::Floor($wid / 2), [int][Math]::Floor($hei / 2)))
    Fill-HLine ($x + $inset) ($y + 1) ($wid - 2 * $inset) $C_GLASS_HI
    Fill-VLine ($x + 1) ($y + $inset) ($hei - 2 * $inset) $C_GLASS_HI
    Fill-HLine ($x + $inset) ($y + $hei - 2) ($wid - 2 * $inset) $C_GLASS_LO
    Fill-VLine ($x + $wid - 2) ($y + $inset) ($hei - 2 * $inset) $C_GLASS_LO
    Fill-Rect ($x + 3) ($y + 5) 2 ($hei - 10) $accent
}
function Glass-Progress([int]$x, [int]$y, [int]$wid, [int]$hei, [int]$pct, [int]$rad) {
    if ($pct -lt 0) { $pct = 0 }
    if ($pct -gt 100) { $pct = 100 }
    Fill-RoundRect $x $y $wid $hei $rad $C_GLASS_BG
    Outline-RoundRect $x $y $wid $hei $rad $C_GLASS_LO $C_GLASS_BG
    if ($pct -le 0) { return }
    $filled = [int][Math]::Floor($pct * $wid / 100)
    if ($filled -lt $rad) { $filled = $rad }
    Fill-RoundRect $x $y $filled $hei $rad $C_RING
    for ($i = 0; $i -lt $filled; $i++) {
        $step = [Math]::Max(1, $wid - 1)
        $fb = ($C_RING -shr 11) -band 0x1F; $fgg = ($C_RING -shr 5) -band 0x3F; $fr = $C_RING -band 0x1F
        $tb = ($C_CYAN -shr 11) -band 0x1F;  $tg = ($C_CYAN -shr 5) -band 0x3F;  $tr = $C_CYAN -band 0x1F
        $nb = $fb + [int](($tb - $fb) * $i / $step)
        $ng = $fgg + [int](($tg - $fgg) * $i / $step)
        $nr = $fr + [int](($tr - $fr) * $i / $step)
        Fill-VLine ($x + $i) ($y + 2) ($hei - 4) (($nb -shl 11) -bor ($ng -shl 5) -bor $nr)
    }
}
function Draw-FrameTrack {
    Fill-Rect $FRAME_X $FRAME_Y $FRAME_SIZE $FRAME_THICK $C_TRACK
    Fill-Rect ($FRAME_X + $FRAME_SIZE - $FRAME_THICK) $FRAME_Y $FRAME_THICK $FRAME_SIZE $C_TRACK
    Fill-Rect $FRAME_X ($FRAME_Y + $FRAME_SIZE - $FRAME_THICK) $FRAME_SIZE $FRAME_THICK $C_TRACK
    Fill-Rect $FRAME_X $FRAME_Y $FRAME_THICK $FRAME_SIZE $C_TRACK
}
function Draw-FrameProgress([int]$len) {
    if ($len -le 0) { return }
    $seg = [Math]::Min($len, $FRAME_SIDE); Fill-Rect $FRAME_X $FRAME_Y $seg $FRAME_THICK $C_RING; $len -= $seg
    $seg = [Math]::Min($len, $FRAME_SIDE); Fill-Rect ($FRAME_X + $FRAME_SIZE - $FRAME_THICK) $FRAME_Y $FRAME_THICK $seg $C_RING; $len -= $seg
    $seg = [Math]::Min($len, $FRAME_SIDE); Fill-Rect ($FRAME_X + $FRAME_SIZE - $seg) ($FRAME_Y + $FRAME_SIZE - $FRAME_THICK) $seg $FRAME_THICK $C_RING; $len -= $seg
    $seg = [Math]::Min($len, $FRAME_SIDE); if ($seg -gt 0) { Fill-Rect $FRAME_X ($FRAME_Y + $FRAME_SIZE - $seg) $FRAME_THICK $seg $C_RING }
}
function Draw-BambuLogo([int]$x, [int]$y) {
    Draw-GlyphBits $BambuLogoBytes 24 32 $x $y $C_RING
}
function Get-Filament565([string]$colorHex) {
    # /api/status 给的是网页标准 #RRGGBB（可带 AA 后缀）。整体 UI 的画法是"屏幕字面值 + Get-Bgr565Color 解码"，
    # 色块必须走同一条链：先把 RGB 按屏幕约定压成 565 字面值，再交给同一个解码器，否则会脱离整体色域。
    $clean = ([string]$colorHex).Trim().TrimStart('#')
    if ($clean.Length -eq 8) { $clean = $clean.Substring(0, 6) }   # 容错 RRGGBBAA
    if ($clean.Length -ne 6 -or $clean -notmatch '^[0-9A-Fa-f]{6}$') { return 0x0000 }
    $r = [Convert]::ToInt32($clean.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($clean.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($clean.Substring(4, 2), 16)
    # 编码方向必须与画布解码器 Get-Bgr565Color 一致（高位=B、低位=R，即屏幕注释里的
    # ((B<<11)|(G<<5)|R) 约定），否则红/蓝通道会互换——不能用标准 RGB565 的方向。
    $enc = ((($b -shr 3) -shl 11) -bor (($g -shr 2) -shl 5) -bor ($r -shr 3))
    return [int]$enc
}
function Draw-SlotCard([int]$slotX, $slot, [bool]$active, [string]$label, [string]$emptyLabel) {
    $bgCol   = if ($active) { 0x1A04 } else { $C_CARD }
    $border  = if ($active) { $C_RING } else { 0x294A }
    Glass-Card $slotX 102 44 46 6 $bgCol $border $C_RING
    if ($active) { Fill-Triangle ($slotX + 19) 100 ($slotX + 25) 100 ($slotX + 22) 103 $C_RING }
    else         { Fill-Rect ($slotX + 18) 99 9 3 $C_CARD }
    $valid = $false; if ($null -ne $slot) { $valid = [bool]$slot.valid }
    if ($valid) {
        $colorHex = [string]$slot.color
        $c565 = Get-Filament565 $colorHex
        Fill-RoundRect ($slotX + 4) 106 12 12 3 $c565
        Outline-RoundRect ($slotX + 4) 106 12 12 3 $C_TEXT $c565
        Set-Txt 1 'TL' $(if ($active) { $C_RING } else { $C_DIM }) $bgCol
        Draw-Text $label ($slotX + 18) 107
        $short = [string]$slot.type
        foreach ($pair in @(@('PLA','PLA'),@('ABS','ABS'),@('PETG','PETG'),@('TPU','TPU'),@('PA','PA'),@('PC','PC'),@('ASA','ASA'),@('Support','SPT'))) {
            if ($short.StartsWith($pair[0])) { $short = $pair[1]; break }
        }
        if ($short.Length -gt 5) { $short = $short.Substring(0, 5) }
        Set-Txt 1 'MC' $C_TEXT $bgCol
        Draw-Text $short ($slotX + 22) 124
        $remain = -1; if ($null -ne $slot.remain) { $remain = [int]$slot.remain }
        if ($slot.official -eq $true -and $remain -ge 0 -and $remain -le 100) {
            Set-Txt 1 'MC' $C_DIM $bgCol
            Draw-Text ('{0}%' -f $remain) ($slotX + 22) 137
        }
    } else {
        Set-Txt 1 'MC' $C_DIM $bgCol
        Draw-Text $emptyLabel ($slotX + 22) 118
        Draw-Text '--' ($slotX + 22) 132
    }
}

# ============================ Bambu Logo 位图 ============================
$BambuLogoBytes = Read-HexArray (Get-Content -LiteralPath (Join-Path $RepoRoot 'src\main.cpp') -Raw -Encoding UTF8) 'BAMBU_LOGO\s*\[\s*\]\s*PROGMEM\s*=\s*\{([\s\S]*?)\}'

# ============================ 布局渲染 ============================
function Render-Classic {
    $model = Get-TopLeftDisplayName
    $status = Get-StatusText
    # ---- 基底（drawClassicBaseSafe） ----
    Fill-Rect 0 0 240 240 $BG_BLACK
    Draw-FrameTrack
    Glass-Card 16 16 208 26 8 $C_CARD $C_GLASS_LO $C_RING
    Glass-Card 16 48 208 56 8 $C_CARD $C_GLASS_LO $C_RING
    Glass-Card 16 112 98 48 8 $C_CARD $C_GLASS_LO $C_CARD
    Glass-Card 126 112 98 48 8 $C_CARD $C_GLASS_LO $C_CARD
    Glass-Card 16 168 208 52 8 $C_CARD $C_GLASS_LO $C_RING
    # drawClassicLabelsSafe
    Fill-Rect 20 116 90 15 $C_CARD; Fill-Rect 130 116 90 15 $C_CARD
    Set-Txt 1 'MC' $C_DIM $C_CARD
    Draw-Text 'NOZZLE' 65 123; Draw-Text 'BED' 175 123
    # drawClassicFooterSafe 底值
    Draw-BambuLogo 22 178
    Set-Txt 1 'TL' $C_DIM $C_CARD; Draw-Text 'PRINTER' 56 177
    Set-Txt 2 'TL' $C_CYAN $C_CARD; Draw-Text (Get-FitText '--' 2 154 $false) 56 193
    # ---- 顶栏（drawClassicHeaderSafe，我的统一入口版） ----
    Glass-Card 16 16 208 26 8 $C_CARD $C_GLASS_LO $C_RING
    Set-Txt 2 'TL' $C_TEXT $C_CARD
    Draw-Text (Get-FitText $(if ($model) { $model } else { '--' }) 2 90 $false) 24 20
    $statusUpper = (Get-HeaderStatusText $status).ToUpper()
    Draw-HeaderStatus 194 20 $statusUpper (Get-StatusColor)
    Fill-Circle 207 29 4 $(if ($SOnlineCalc) { Get-StatusColor } else { $C_ORANGE })
    # ---- 外框进度 ----
    Draw-FrameTrack
    Draw-FrameProgress (Get-ProgressLen)
    # ---- Hero（drawClassicHeroSafe） ----
    Glass-Card 16 48 208 56 8 $C_CARD $C_GLASS_LO $C_RING
    $numText = '--'; if ($SProg -ge 0) { $numText = '{0}' -f [int][Math]::Round($SProg) }
    Set-Txt 7 'TL' $C_TEXT $C_CARD; Draw-Text $numText 24 51
    $numW = Get-TextWidth $numText 7
    Set-Txt 4 'TL' $C_RING $C_CARD; Draw-Text '%' (27 + $numW) 76
    $layerText = 'L --'
    if ($SCurLay -ge 0 -and $STotLay -gt 0) { $layerText = 'L {0}/{1}' -f $SCurLay, $STotLay }
    elseif ($SCurLay -ge 0) { $layerText = 'L {0}' -f $SCurLay }
    Set-Txt 2 'TR' $C_CYAN $C_CARD; Draw-Text (Get-FitText $layerText 2 92 $false) 216 53
    Set-Txt 1 'TR' $(if ($SSpdLvl -eq 3) { $C_ORANGE } else { $C_DIM }) $C_CARD
    Draw-Text (Get-FitText (Get-CompactSpeed) 1 60 $false) 216 84
    # ---- 温度 ----
    $side = Get-NozzleSide
    $nozzleV = Get-DisplayedNozzle
    $nozInt = -1; if ($nozzleV -ge 0) { $nozInt = [int][Math]::Round($nozzleV) }
    $bedV = $SBed; $bedInt = -1; if ($bedV -ge 0) { $bedInt = [int][Math]::Round($bedV) }
    $nozText = if ($nozInt -lt 0) { '--' } else { '{0}C' -f $nozInt }
    if ($side -ge 0) { $nozText = ('{0} ' -f $(if ($side -eq 1) { 'R' } else { 'L' })) + $nozText }
    Draw-TextBox 20 133 90 23 4 $(if ($nozInt -ge 0) { $C_YELLOW } else { $C_DIM }) $nozText $true $C_CARD
    $bedText = if ($bedInt -lt 0) { '--' } else { '{0}C' -f $bedInt }
    Draw-TextBox 130 133 90 23 4 $(if ($bedInt -ge 0) { $C_ORANGE } else { $C_DIM }) $bedText $true $C_CARD
    # ---- 底部 footer（实际值） ----
    $showRem = ($SRemain -gt 0) -and ($SProg -lt 100) -and (-not (Test-Finished)) -and (-not (Test-Failed))
    $footerLabel = 'PRINTER'; $footerValue = if ($SName) { $SName } else { $SModel }
    $large = $false
    if ($showRem) { $footerLabel = 'REMAIN'; $footerValue = (Get-ClassicRemaining $SRemain); $large = $true }
    Draw-BambuLogo 22 178
    Set-Txt 1 'TL' $C_DIM $C_CARD; Draw-Text $footerLabel 56 177
    if ($large) {
        $vf = 4
        if ((Get-TextWidth $footerValue 4) + 1 -gt 78) { $vf = 2 }
        Draw-TextBox 132 176 84 34 $vf $C_CYAN (Get-FitText $footerValue $vf 78 $true) $true $C_CARD
    } else {
        Set-Txt 2 'TL' $C_CYAN $C_CARD
        Draw-Text (Get-FitText $footerValue 2 154 $false) 56 193
    }
}

function Render-Dashboard {
    $model = Get-TopLeftDisplayName
    # ---- 基底（drawDashboardBase） ----
    Fill-Rect 0 0 240 240 $BG_BLACK
    Outline-RoundRect 4 4 232 232 8 0x294A $BG_BLACK
    Glass-Card 14 10 212 22 11 $C_CARD $C_GLASS_LO $C_RING
    Glass-Card 14 36 212 118 10 $C_CARD $C_GLASS_LO $C_RING
    Glass-Progress 24 86 192 12 0 6
    Glass-Card 14 160 102 68 8 $C_CARD $C_GLASS_LO $C_RING
    Glass-Card 124 160 102 68 8 $C_CARD $C_GLASS_LO $C_RING
    # ---- 顶栏 ----
    Glass-Card 14 10 212 22 11 $C_CARD $C_GLASS_LO $C_RING
    Set-Txt 2 'TL' $C_TEXT $C_CARD
    Draw-Text (Get-FitText $(if ($model) { $model } else { '--' }) 2 92 $false) 24 13
    Fill-Circle 206 21 4 $(if ($SOnlineCalc) { Get-StatusColor } else { $C_ORANGE })
    Draw-HeaderStatus 196 13 (Get-DashStatusText) (Get-StatusColor)
    # ---- Hero ----
    Fill-Rect 16 38 208 46 $C_CARD
    Fill-Rect 17 41 2 43 $C_RING
    Fill-HLine 24 82 192 $C_RING
    $pctInt = -1; if ($SProg -ge 0) { $pctInt = [int][Math]::Round($SProg) }
    $numText = '--'; if ($pctInt -ge 0) { $numText = '{0}' -f $pctInt }
    Set-Txt 7 'TL' $C_TEXT $C_CARD; Draw-Text $numText 24 37
    if ($pctInt -ge 0) {
        $pctX = 24 + (Get-TextWidth $numText 7) + 2
        Set-Txt 4 'TL' $C_RING $C_CARD; Draw-Text '%' $pctX 58
    }
    # 层数（缺层时退回状态，与顶栏同一入口）
    if ($SCurLay -ge 0 -and $STotLay -gt 0) {
        $layerText = 'L {0}/{1}' -f $SCurLay, $STotLay
        Set-Txt 2 'TR' $C_CYAN $C_CARD; Draw-Text $layerText 216 40
    } elseif ($SCurLay -ge 0) {
        Set-Txt 2 'TR' $C_CYAN $C_CARD; Draw-Text ('L {0}' -f $SCurLay) 216 40
    } else {
        Draw-HeaderStatus 216 40 (Get-DashStatusText) $C_CYAN
    }
    # 速度
    $spdColor = $C_DIM; $spdStr = '----'
    if ($SSpdLvl -eq 1) { $spdColor = $C_RING;   $spdStr = 'Silent {0}%' -f $(if ($SSpdMag -gt 0) { $SSpdMag } else { 50 }) }
    elseif ($SSpdLvl -eq 3) { $spdColor = $C_ORANGE; $spdStr = 'Sport {0}%' -f $(if ($SSpdMag -gt 0) { $SSpdMag } else { 124 }) }
    elseif ($SSpdLvl -eq 4) { $spdColor = $C_RED;   $spdStr = 'Ludicrous {0}%' -f $(if ($SSpdMag -gt 0) { $SSpdMag } else { 166 }) }
    elseif ($SSpdLvl -eq 2) { $spdColor = $C_CYAN;  $spdStr = 'Std {0}%' -f $(if ($SSpdMag -gt 0) { $SSpdMag } else { 100 }) }
    Set-Txt 2 'TR' $spdColor $C_CARD; Draw-Text $spdStr 216 58
    Glass-Progress 24 86 192 12 $pctInt 6
    # ---- AMS / 外挂 ----
    $hasAms = $false
    if ($null -ne $SAms) {
        if ($SAms -is [System.Array]) { $hasAms = $true }
        elseif ($SAms.valid) { $hasAms = $true }
    }
    $stageTray = $SStageCur
    if ($hasAms) {
        for ($k = 0; $k -lt 4; $k++) {
            $slot = $null
            if ($SAms -is [System.Array] -and $k -lt $SAms.Count) { $slot = $SAms[$k] }
            $active = $false
            if ($null -ne $slot -and $null -ne $slot.active) { $active = [bool]$slot.active }
            $slotLabel = '{0}' -f ($k + 1); $emptyLabel = 'A{0}' -f ($k + 1)
            Draw-SlotCard (22 + ($k * 47)) $slot $active $slotLabel $emptyLabel
        }
    } else {
        $extActive = $false
        if ($null -ne $SExt -and $null -ne $SExt.active) { $extActive = [bool]$SExt.active }
        Draw-SlotCard 22 $SExt $extActive 'ext' 'ext'
        Fill-Rect 68 99 142 51 $C_CARD
    }
    # ---- 温度卡 ----
    $nozzleV = Get-DisplayedNozzle
    $nozInt = -1; if ($nozzleV -ge 0) { $nozInt = [int][Math]::Round($nozzleV) }
    $bedInt = -1; if ($SBed -ge 0) { $bedInt = [int][Math]::Round($SBed) }
    $chamberInt = -1; if ($SChamber -ge 0) { $chamberInt = [int][Math]::Round($SChamber) }
    Set-Txt 2 'TL' $C_DIM $C_CARD; Draw-Text 'NOZ' 20 166
    Set-Txt 2 'TL' $(if ($nozInt -ge 0) { $C_YELLOW } else { $C_DIM }) $C_CARD
    Draw-Text $(if ($nozInt -ge 0) { '{0}C' -f $nozInt } else { '--' }) 62 166
    Set-Txt 2 'TL' $C_DIM $C_CARD; Draw-Text 'BED' 20 186
    Set-Txt 2 'TL' $(if ($bedInt -ge 0) { $C_ORANGE } else { $C_DIM }) $C_CARD
    Draw-Text $(if ($bedInt -ge 0) { '{0}C' -f $bedInt } else { '--' }) 62 186
    Set-Txt 2 'TL' $C_DIM $C_CARD; Draw-Text 'CHM' 20 206
    $chmText = '--'
    $chmColor = $C_DIM
    if ($chamberInt -ge 0) { $chmText = '{0}C' -f $chamberInt; $chmColor = $C_CYAN }
    elseif (-not $SHasCham) { $chmText = 'N/A' }
    Set-Txt 2 'TL' $chmColor $C_CARD; Draw-Text $chmText 62 206
    # ---- 剩余时间卡 ----
    $done = (Test-Finished) -or ($SProg -ge 100)
    $rmText = if ($done) { 'DONE' } else { Get-TimeText $SRemain }
    $etaText = if ($done) { 'DONE' } else { ('ETA ' + (Get-EtaText $SRemain)) }
    Set-Txt 1 'MC' $C_DIM $C_CARD; Draw-Text 'REMAINING' 175 170
    Set-Txt 4 'MC' $C_CYAN $C_CARD; Draw-Text $rmText 175 190
    Set-Txt 1 'MC' $C_ORANGE $C_CARD; Draw-Text $etaText 175 213
}

function Render-Clock {
    # 时间来源：-ClockTime 或本机当前时间
    $now = Get-Date
    if ($ClockTime) {
        try { $now = [datetime]::ParseExact($ClockTime, 'HH:mm:ss', $null) }
        catch { try { $now = [datetime]::ParseExact($ClockTime, 'HH:mm', $null) } catch { $now = Get-Date } }
        if ($now.Year -lt 2000) { $now = (Get-Date).Date.Add($now.TimeOfDay) }
    }
    $hh = '{0:d2}' -f $now.Hour; $mm = '{0:d2}' -f $now.Minute; $ss = $now.Second
    Fill-Rect 0 0 240 240 $BG_BLACK
    Outline-RoundRect 4 4 232 232 8 0x294A $BG_BLACK
    # 日期胶囊
    Glass-Card 14 12 108 22 11 $C_CARD $C_GLASS_LO $C_RING
    Set-Txt 2 'MC' $C_TEXT $C_CARD
    $dateStr = '{0:D4}.{1:D2}.{2:D2}' -f $now.Year, $now.Month, $now.Day
    Draw-Text $dateStr 68 23
    Glass-Card 128 12 64 22 11 $C_CARD $C_GLASS_LO $C_RING
    Set-Txt 2 'MC' 0xFF40 $C_CARD
    $weekdays = @('SUN','MON','TUE','WED','THU','FRI','SAT')
    Draw-Text $weekdays[[int]$now.DayOfWeek] 160 23
    # 在线灯
    $led = if ($SOnline) { $C_RING } else { $C_ORANGE }
    Fill-Circle 208 23 5 $led
    Draw-CircleOutline 208 23 5 $BG_BLACK
    # 主钟卡
    Glass-Card 14 42 212 108 10 $C_CARD $C_GLASS_LO $C_RING
    $timeStr = '{0} {1}' -f $hh, $mm
    Set-Txt 7 'MC' 0x5940 $C_CARD
    Draw-Text $timeStr 122 90; Draw-Text $timeStr 118 90; Draw-Text $timeStr 122 86; Draw-Text $timeStr 118 86
    Set-Txt 7 'MC' 0x9C40 $C_CARD
    Draw-Text $timeStr 121 89; Draw-Text $timeStr 119 89; Draw-Text $timeStr 121 87; Draw-Text $timeStr 119 87
    Set-Txt 7 'MC' 0xFF40 $C_CARD
    Draw-Text $timeStr 120 88
    Fill-RoundRect 26 136 188 5 2 $BG_BLACK
    if (($ss % 2) -eq 0) { Fill-Circle 120 77 3 0xFF40; Fill-Circle 120 99 3 0xFF40 }
    else                 { Fill-Circle 120 77 3 $C_CARD; Fill-Circle 120 99 3 $C_CARD }
    if ($ss -gt 0) { Fill-Rect 26 136 ([int][Math]::Floor($ss * 188 / 59)) 5 0xFF40 }
    # 底部状态卡（drawClockStatusSafe）
    Glass-Card 14 158 212 68 8 $C_CARD $C_GLASS_LO $C_RING
    $active = $SOnline -and ((Test-Printing) -or (Test-Preparing) -or (Test-Paused))
    if ($active) {
        Set-Txt 2 'TL' $C_TEXT $C_CARD
        $clockModel = Get-NormalizedModel $SModel
        Draw-Text (Get-FitText $(if ($clockModel) { $clockModel } else { 'PRINT' }) 2 100 $false) 24 166
        Draw-HeaderStatus 204 166 (Get-DashStatusText) (Get-StatusColor)
        $pctInt = 0; if ($SProg -ge 0) { $pctInt = [int][Math]::Round($SProg) }
        Glass-Progress 24 186 180 6 $pctInt 3
        $nozInt = 0; if ($SNozzle -ge 0) { $nozInt = [int][Math]::Round($SNozzle) }
        $bedInt = 0; if ($SBed -ge 0) { $bedInt = [int][Math]::Round($SBed) }
        Set-Txt 1 'TL' $C_DIM $C_CARD
        Draw-Text (Get-FitText ('NOZ {0}C  BED {1}C' -f $nozInt, $bedInt) 1 108 $false) 24 198
        $done = (Test-Finished) -or ($SProg -ge 100)
        $rmText = if ($done) { 'DONE' } else { Get-TimeText $SRemain }
        Set-Txt 2 'TR' $C_CYAN $C_CARD
        Draw-Text (Get-FitText $rmText 2 56 $false) 204 198
    } else {
        Draw-BambuLogo 24 176
        $standbyName = $SName; if (-not $standbyName) { $standbyName = Get-NormalizedModel $SModel }
        Set-Txt 2 'TL' $C_TEXT $C_CARD
        Draw-Text (Get-FitText $standbyName 2 90 $false) 56 174
        Set-Txt 1 'TL' $C_DIM $C_CARD
        Draw-Text (Get-FitText (Get-NormalizedModel $SModel) 1 112 $false) 56 196
        Set-Txt 2 'TR' $(if ($SOnline) { $C_CYAN } else { $C_ORANGE }) $C_CARD
        Draw-Text $(if ($SOnline) { 'READY' } else { 'OFFLINE' }) 204 184
    }
}

# ============================ 输出 ============================
Write-Host '[3/4] 渲染中...'
$paths = @()
foreach ($lay in $layouts) {
    New-Canvas
    switch ($lay) {
        'classic'   { Render-Classic }
        'dashboard' { Render-Dashboard }
        'clock'     { Render-Clock }
        default     { throw "未知布局：$lay" }
    }
    $outPath = Join-Path $OutDir ("sim-{0}.png" -f $lay)
    Save-Canvas $outPath
    $paths += $outPath
    Write-Host ("      {0} -> {1}" -f $lay, $outPath)
}

# ============================ 摘要 ============================
Write-Host '[4/4] 完成'
Write-Host '--- 状态摘要 ---'
Write-Host ("  布局      : {0}" -f ($layouts -join ', '))
Write-Host ("  语言      : {0}" -f $(if ($IsEn) { 'English（英文缩写）' } else { '中文（点阵）' }))
Write-Host ("  在线/状态 : online={0} mqtt={1} status={2} 计算={3}" -f $SOnline, $SMqtt, $SStatus, $SOnlineCalc)
Write-Host ("  状态词    : statusText='{0}' dashboard='{1}' 颜色=0x{2:X4}" -f (Get-StatusText), (Get-DashStatusText), (Get-StatusColor))
Write-Host ("  细分阶段  : stg_cur={0} 英文='{1}' 中文标签索引={2}" -f $SStageCur, (Get-StageAbbrev), (Get-CurrentCnLabel))
Write-Host ("  进度/层   : {0}%  {1}/{2}  剩余={3}分" -f $SProg, $SCurLay, $STotLay, $SRemain)
Write-Host ("  温度      : NOZ={0} BED={1} CHM={2}(has={3}) dual={4}" -f $SNozzle, $SBed, $SChamber, $SHasCham, $SDual)
Write-Host ("  模型/名称 : model={0} name='{1}' 显示名='{2}'" -f $SModel, $SName, (Get-TopLeftDisplayName))
Write-Host ""
Write-Host "输出文件:"
$paths | ForEach-Object { Write-Host "  $_" }
