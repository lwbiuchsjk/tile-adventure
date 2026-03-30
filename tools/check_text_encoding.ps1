param(
    [string]$Root = ".",
    [string[]]$Include = @("*.gd", "*.tscn", "*.tres", "*.cfg", "*.csv", "*.json", "*.md", "*.txt", "*.ps1")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 功能：判断字节数组是否以指定前缀开头。
# 说明：用于识别 UTF-8 BOM、UTF-16 LE BOM、UTF-16 BE BOM 等常见文件头标记。
function Test-BytePrefix {
    param(
        [byte[]]$Bytes,
        [byte[]]$Prefix
    )

    if ($Bytes.Length -lt $Prefix.Length) {
        return $false
    }

    for ($i = 0; $i -lt $Prefix.Length; $i++) {
        if ($Bytes[$i] -ne $Prefix[$i]) {
            return $false
        }
    }

    return $true
}

# 功能：识别文件的 BOM 类型。
# 说明：项目默认要求 UTF-8 without BOM；但 .ps1 为兼容 Windows PowerShell，允许 UTF-8 BOM。
function Get-BomKind {
    param([byte[]]$Bytes)

    $utf8Bom = [byte[]]@(0xEF, 0xBB, 0xBF)
    $utf16LeBom = [byte[]]@(0xFF, 0xFE)
    $utf16BeBom = [byte[]]@(0xFE, 0xFF)

    if (Test-BytePrefix -Bytes $Bytes -Prefix $utf8Bom) {
        return "utf8-bom"
    }
    if (Test-BytePrefix -Bytes $Bytes -Prefix $utf16LeBom) {
        return "utf16-le"
    }
    if (Test-BytePrefix -Bytes $Bytes -Prefix $utf16BeBom) {
        return "utf16-be"
    }
    return "none"
}

# 功能：验证文件是否可按 UTF-8 正常解码。
# 说明：throwOnInvalidBytes=true 可以直接识别错误编码或损坏内容；BOM 是否允许由上层规则决定。
function Test-Utf8Decodable {
    param([byte[]]$Bytes)

    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        [void]$encoding.GetString($Bytes)
        return $true
    }
    catch [System.Text.DecoderFallbackException] {
        return $false
    }
}

# 功能：判断给定文件是否应被编码检查忽略。
# 说明：排除编辑器配置目录、Godot 导入缓存和知识库缓存，避免噪音干扰业务文件检查。
function Test-IgnoredPath {
    param([string]$Path)

    return $Path -match '\\.git\\' -or
        $Path -match '\\.godot\\' -or
        $Path -match '\\.vscode\\' -or
        $Path -match '\\_kb_sync\\'
}

# 功能：递归收集需要检查的文本文件。
# 说明：只扫描项目常见文本后缀，避免把二进制资源误判为编码问题。
function Get-TargetFiles {
    param(
        [string]$BasePath,
        [string[]]$Patterns
    )

    $items = foreach ($pattern in $Patterns) {
        Get-ChildItem -Path $BasePath -Recurse -File -Filter $pattern |
            Where-Object { -not (Test-IgnoredPath -Path $_.FullName) }
    }

    return $items | Sort-Object -Property FullName -Unique
}

# 功能：判断给定文件是否允许当前 BOM 类型。
# 说明：默认不允许 BOM；仅 .ps1 为兼容 Windows PowerShell 允许 utf8-bom。
function Test-BomAllowed {
    param(
        [string]$Path,
        [string]$BomKind
    )

    if ($BomKind -eq 'none') {
        return $true
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -eq '.ps1' -and $BomKind -eq 'utf8-bom') {
        return $true
    }

    return $false
}

$issues = New-Object System.Collections.Generic.List[object]
$files = Get-TargetFiles -BasePath $Root -Patterns $Include

foreach ($file in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $bomKind = Get-BomKind -Bytes $bytes

    if (-not (Test-BomAllowed -Path $file.FullName -BomKind $bomKind)) {
        $issues.Add([pscustomobject]@{
            Path = $file.FullName
            Issue = 'unexpected-bom'
            Detail = $bomKind
        })
        continue
    }

    if (-not (Test-Utf8Decodable -Bytes $bytes)) {
        $issues.Add([pscustomobject]@{
            Path = $file.FullName
            Issue = 'invalid-utf8'
            Detail = 'file cannot be decoded as utf-8'
        })
    }
}

if ($issues.Count -eq 0) {
    Write-Output 'OK: all checked text files match the repository encoding rules'
    exit 0
}

$issues | Sort-Object -Property Path | ForEach-Object {
    Write-Output ('{0}`t{1}`t{2}' -f $_.Issue, $_.Detail, $_.Path)
}

exit 1