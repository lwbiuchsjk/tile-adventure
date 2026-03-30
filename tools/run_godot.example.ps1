# 功能：统一调用本项目约定的 Godot 可执行文件。
# 说明：固定 Godot 路径，并将调用参数原样透传，避免每次会话重复说明路径。

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GodotArgs
)

$ErrorActionPreference = "Stop"

# 说明：这里维护项目级固定 Godot 路径；如后续升级版本，只需修改这一处。
$godotExe = "\godot.exe"

if (-not (Test-Path $godotExe)) {
    throw "Godot executable not found: $godotExe"
}

# 说明：默认补齐项目路径，避免在仓库根目录外调用时找不到 project.godot。
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$finalArgs = @("--path", $projectRoot)

if ($GodotArgs) {
    $finalArgs += $GodotArgs
}

& $godotExe @finalArgs
$exitCode = $LASTEXITCODE

if ($null -ne $exitCode) {
    exit $exitCode
}
