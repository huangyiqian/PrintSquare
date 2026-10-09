$ErrorActionPreference = "Stop"

function CnName($codePoints, $suffix = "") {
  return (-join ($codePoints | ForEach-Object { [char]$_ })) + $suffix
}

function Join-CnPath($base, $codePoints, $suffix = "") {
  return Join-Path $base (CnName $codePoints $suffix)
}

function Copy-Required($from, $to) {
  if (-not (Test-Path -LiteralPath $from)) {
    throw "Missing required file: $from"
  }
  Copy-Item -LiteralPath $from -Destination $to -Force
}

function Copy-Optional($from, $to) {
  if (Test-Path -LiteralPath $from) {
    Copy-Item -LiteralPath $from -Destination $to -Force
  }
}

$root = $PSScriptRoot
$releaseRoot = Join-Path $root "release"

# zip 命名：PrintSquare_v<版本>_<yyyyMMdd>_build.zip
# 版本号自动读后端配置工具\package.json 的 version 字段（改版本只改这一处）
$packageJson = Join-Path $root "后端配置工具\package.json"
if (-not (Test-Path -LiteralPath $packageJson)) {
  throw "Missing required file: $packageJson"
}
$version = (Get-Content -LiteralPath $packageJson -Raw -Encoding UTF8 | ConvertFrom-Json).version
if (-not $version) {
  throw "Cannot read version from $packageJson"
}
$dateStamp = Get-Date -Format "yyyyMMdd"
$pkgName = "PrintSquare_v$version" + "_" + $dateStamp + "_build"

# 同版本同日期多次打包：首次为 _build，之后依次 _build1、_build2…（保留全部历史便于回滚，不覆盖旧包）
$seq = 0
while ((Test-Path -LiteralPath (Join-Path $releaseRoot "$pkgName.zip")) -or
       (Test-Path -LiteralPath (Join-Path $releaseRoot $pkgName))) {
  $seq++
  $pkgName = "PrintSquare_v$version" + "_" + $dateStamp + "_build$seq"
}
if ($seq -gt 0) {
  Write-Host "检测到同日期已有打包历史，本次命名为 ${pkgName}.zip（不覆盖旧包）"
}

$out = Join-Path $releaseRoot $pkgName
$zip = Join-Path $releaseRoot "$pkgName.zip"

$nameFirmware = @(0x56FA, 0x4EF6)
$nameCompanion = @(0x540E, 0x7AEF, 0x914D, 0x7F6E, 0x5DE5, 0x5177)
$nameFlasher = @(0x5237, 0x56FA, 0x4EF6, 0x5DE5, 0x5177)
$nameReadme = @(0x4F7F, 0x7528, 0x8BF4, 0x660E)
$nameDriver = @(0x9A71, 0x52A8)
$fileOpenCompanion = CnName @(0x6253, 0x5F00, 0x914D, 0x7F6E, 0x5DE5, 0x5177) ".bat"
$fileCompanionExe = "PrintSquare" + (CnName @(0x914D, 0x7F6E, 0x5DE5, 0x5177) ".exe")
$fileOneClickFlash = CnName @(0x4E00, 0x952E, 0x5237, 0x5165, 0x56FA, 0x4EF6) ".bat"

$sourceFirmwareDir = Join-CnPath $root $nameFirmware
$sourceCompanionDir = Join-CnPath $root $nameCompanion
$sourceFlasherDir = Join-CnPath $root $nameFlasher

$compiledBin = Join-Path $root ".pio\build\sd2\firmware.bin"
$firmware = Join-Path $sourceFirmwareDir "printsquare-esp8266.bin"

if (Test-Path -LiteralPath $compiledBin) {
  Copy-Item -LiteralPath $compiledBin -Destination $firmware -Force
  Write-Host "Updated firmware bin from compilation output."
}

if (-not (Test-Path -LiteralPath $firmware)) {
  throw "Missing firmware: $firmware"
}

New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null
if (Test-Path -LiteralPath $out) {
  Remove-Item -LiteralPath $out -Recurse -Force
}

$firmwareOut = Join-CnPath $out $nameFirmware
$companionOut = Join-CnPath $out $nameCompanion
$flasherOut = Join-CnPath $out $nameFlasher

New-Item -ItemType Directory -Force -Path `
  $firmwareOut, `
  $companionOut, `
  (Join-Path $flasherOut "tools"), `
  (Join-CnPath $flasherOut $nameDriver) | Out-Null

Copy-Required $firmware (Join-Path $firmwareOut "printsquare-esp8266.bin")
Copy-Required (Join-Path $root "README.md") (Join-CnPath $out $nameReadme ".md")

# 使用说明.md 是 README.md 的副本，里面引用的预览图（docs/images/…）必须按相同的
# 相对路径一起打进包，否则用户解压后看到的是空框。这里直接从 README 里解析引用，
# 引用到不存在的图片会由 Copy-Required 直接报错，避免再次出现静默的坏图。
$readmeText = Get-Content -LiteralPath (Join-Path $root "README.md") -Raw -Encoding UTF8
$imageRefs = [regex]::Matches($readmeText, 'docs/images/[^"''\)\s>]+') |
  ForEach-Object { $_.Value } | Sort-Object -Unique
if (-not $imageRefs) {
  throw "README.md 中未解析到任何 docs/images 引用，请检查打包逻辑"
}
foreach ($ref in $imageRefs) {
  $rel = $ref -replace '/', '\'
  $dst = Join-Path $out $rel
  New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($dst)) | Out-Null
  Copy-Required (Join-Path $root $rel) $dst
}
Write-Host ("Included {0} preview image(s) referenced by README." -f $imageRefs.Count)

# 只发 exe 方案：单文件 exe 内嵌 Node 运行时与 server.js，
# 不再打包 node\、server.js、package.json、打开配置工具.bat（避免重复，zip 约 34MB）
Copy-Required (Join-Path $sourceCompanionDir "README.md") (Join-Path $companionOut "README.md")
Copy-Required (Join-Path $sourceCompanionDir "VERSIONS.md") (Join-Path $companionOut "VERSIONS.md")

$companionExe = Join-Path $sourceCompanionDir $fileCompanionExe
if (-not (Test-Path -LiteralPath $companionExe)) {
  throw "Missing required file: $companionExe — 先在 后端配置工具 目录运行 build-exe.ps1 打包单文件 exe"
}
Copy-Item -LiteralPath $companionExe -Destination (Join-Path $companionOut $fileCompanionExe) -Force
Write-Host "Included single-file setup tool exe."

Copy-Required (Join-Path $sourceFlasherDir $fileOneClickFlash) (Join-Path $flasherOut $fileOneClickFlash)
Copy-Required (Join-Path $sourceFlasherDir "flash-firmware.ps1") (Join-Path $flasherOut "flash-firmware.ps1")
Copy-Required (Join-Path $sourceFlasherDir "README.md") (Join-Path $flasherOut "README.md")
# tools\ 与 驱动\ 的 exe 固定从 release\刷固件工具打包要用的两个exe\ 取（见 docs/DSH开发约定.md）
$flasherExeSource = Join-Path $releaseRoot "刷固件工具打包要用的两个exe"
Copy-Required (Join-Path $flasherExeSource "tools\esptool.exe") (Join-Path $flasherOut "tools\esptool.exe")
Copy-Required (Join-Path $flasherExeSource "驱动\CH341SER.EXE") (Join-Path (Join-CnPath $flasherOut $nameDriver) "CH341SER.EXE")

Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

Write-Host ""
Write-Host "Release package created successfully!"
Write-Host "Project Release Zip: $zip"
Write-Host ""
Write-Host "Runtime private data under 后端配置工具/data was not included."
