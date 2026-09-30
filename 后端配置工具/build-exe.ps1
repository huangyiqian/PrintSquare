<#
=============================================================================
 build-exe.ps1 — 把后端配置工具打包成单文件 exe（Node SEA）

 用法（在仓库根目录或本目录均可）：
   powershell -NoProfile -File "后端配置工具\build-exe.ps1"

 产物：
   后端配置工具\PrintSphere配置工具.exe   （约 90MB，内含 Node 运行时与后端代码）

 说明：
   * 底座用本目录下 node\node.exe，保证 exe 里的 Node 版本与开发时一致
   * server.js 以 SEA asset 形式嵌进 exe，不再需要外部 js 文件
   * 首次构建会联网下载 postject 工具链（缓存在 .exe-build\，不随发布包分发）
   * 本脚本不生成也不修改 data\ 目录；data\ 由 exe 首次运行时自己创建
   * 文件编码必须是 UTF-8 with BOM：Windows PowerShell 5.1 否则按 GBK 解析中文会报语法错误
=============================================================================
#>
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$node = Join-Path $PSScriptRoot 'node\node.exe'
if (-not (Test-Path -LiteralPath $node)) {
  throw "未找到 $node —— SEA 需要一个 node.exe 作为底座"
}

$buildDir = Join-Path $PSScriptRoot '.exe-build'
$blob = Join-Path $buildDir 'sea-prep.blob'
$exeName = 'PrintSphere配置工具.exe'
$outExe = Join-Path $PSScriptRoot $exeName
$postjectCli = Join-Path $buildDir 'node_modules\postject\dist\cli.js'
$stderrFile = Join-Path $buildDir 'native-stderr.txt'

# 从 node.exe 里读出 SEA 哨兵串，避免 Node 升级后硬编码值失效
function Get-SeaFuse {
  param([string]$NodePath)
  $bytes = [System.IO.File]::ReadAllBytes($NodePath)
  $text = [System.Text.Encoding]::ASCII.GetString($bytes)
  $marker = 'NODE_SEA_FUSE_'
  $idx = $text.IndexOf($marker)
  if ($idx -lt 0) { return '' }
  $sb = New-Object System.Text.StringBuilder
  for ($i = $idx + $marker.Length; $i -lt $text.Length; $i++) {
    $ch = $text[$i]
    if (($ch -ge '0' -and $ch -le '9') -or ($ch -ge 'a' -and $ch -le 'f')) { [void]$sb.Append($ch) } else { break }
  }
  return $marker + $sb.ToString()
}

# PS 5.1 在 ErrorActionPreference=Stop 时会把原生命令写到 stderr 的正常提示当成
# 终止错误，而 node/pio 这类工具确实会用 stderr 输出提示，所以这里单独降级并自行判断退出码。
function Invoke-Node {
  param([string[]]$NodeArgs, [string]$Label)
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $node @NodeArgs 2> $stderrFile
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  if ($code -ne 0) {
    $detail = ''
    if (Test-Path -LiteralPath $stderrFile) { $detail = Get-Content -LiteralPath $stderrFile -Raw }
    throw "$Label 失败（exit $code）`n$detail"
  }
  if (Test-Path -LiteralPath $stderrFile) { Remove-Item -LiteralPath $stderrFile -Force }
}

function Ensure-Toolchain {
  if (Test-Path -LiteralPath $postjectCli) { return }
  Write-Host '首次构建：下载 postject 工具链...'
  $tmp = Join-Path $buildDir 'tmp'
  New-Item -ItemType Directory -Force -Path (Join-Path $buildDir 'node_modules\postject'), (Join-Path $buildDir 'node_modules\commander'), $tmp | Out-Null
  Invoke-WebRequest 'https://registry.npmjs.org/postject/-/postject-1.0.0-alpha.6.tgz' -OutFile (Join-Path $tmp 'postject.tgz') -TimeoutSec 120
  Invoke-WebRequest 'https://registry.npmjs.org/commander/-/commander-9.5.0.tgz' -OutFile (Join-Path $tmp 'commander.tgz') -TimeoutSec 120
  tar -xzf (Join-Path $tmp 'postject.tgz') -C (Join-Path $buildDir 'node_modules\postject') --strip-components=1
  tar -xzf (Join-Path $tmp 'commander.tgz') -C (Join-Path $buildDir 'node_modules\commander') --strip-components=1
  Remove-Item -LiteralPath $tmp -Recurse -Force
}

Ensure-Toolchain
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

$fuse = Get-SeaFuse -NodePath $node
if (-not $fuse) {
  $fuse = 'NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2'
  Write-Host "警告：未从 node.exe 读到哨兵串，回退到默认值 $fuse"
}
Write-Host "SEA 哨兵串：$fuse"

Write-Host '1/3 生成 SEA blob（内嵌 launcher.js + server.js）...'
Invoke-Node -NodeArgs @('--experimental-sea-config', 'sea-config.json') -Label 'SEA blob 生成'
if (-not (Test-Path -LiteralPath $blob)) { throw "未生成 $blob" }

Write-Host '2/3 复制 node.exe 作为底座...'
Copy-Item -LiteralPath $node -Destination $outExe -Force

Write-Host '3/3 注入 blob（postject）...'
Invoke-Node -NodeArgs @($postjectCli, $outExe, 'NODE_SEA_BLOB', $blob, '--sentinel-fuse', $fuse) -Label 'postject 注入'

$size = (Get-Item -LiteralPath $outExe).Length
Write-Host ''
Write-Host ('构建完成：{0}（{1:N1} MB）' -f $exeName, ($size / 1MB))
Write-Host '自检：直接运行该 exe 应打印启动信息并自动打开浏览器。'
