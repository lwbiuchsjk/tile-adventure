param(
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Split-Path -Parent $scriptDir
$bindingPath = Join-Path $scriptDir 'kb.binding.json'
$localPath = Join-Path $scriptDir 'kb.local.json'
$defaultCacheDir = Join-Path $scriptDir 'cache'
$defaultDesignDir = Join-Path $scriptDir 'Design'
$cacheMdPath = Join-Path $defaultCacheDir 'KB_CONTEXT.md'
$cacheJsonPath = Join-Path $defaultCacheDir 'KB_CONTEXT.json'
$readTokenScript = Join-Path $scriptDir 'read_token.js'

function LogInfo([string]$msg) {
  if (-not $Quiet) { Write-Host "[kb-sync] $msg" }
}

function Get-Cfg([string]$name) {
  # local overrides binding; return empty string if not present
  $v = $null
  if ($local -and ($local.PSObject.Properties.Name -contains $name)) { $v = $local.$name }
  if ((-not $v) -and $binding -and ($binding.PSObject.Properties.Name -contains $name)) { $v = $binding.$name }
  if ($null -eq $v) { return '' }
  return [string]$v
}

function Get-CfgArr([string]$name) {
  # Returns @() if missing; local overrides binding.
  if ($local -and ($local.PSObject.Properties.Name -contains $name) -and $local.$name) { return @($local.$name) }
  if ($binding -and ($binding.PSObject.Properties.Name -contains $name) -and $binding.$name) { return @($binding.$name) }
  return @()
}

function Get-CfgCache([string]$name, [object]$defaultValue) {
  # Returns cache.<name> value; local overrides binding.
  $v = $null
  if ($local -and $local.cache -and ($local.cache.PSObject.Properties.Name -contains $name)) { $v = $local.cache.$name }
  if (($null -eq $v) -and $binding -and $binding.cache -and ($binding.cache.PSObject.Properties.Name -contains $name)) { $v = $binding.cache.$name }
  if ($null -eq $v) { return $defaultValue }
  return $v
}

function Resolve-RelPath([string]$baseDir, [string]$p) {
  if (-not $p) { return '' }
  if ([System.IO.Path]::IsPathRooted($p)) { return $p }
  return (Join-Path $baseDir $p)
}

function Resolve-NodeExe {
  $cmd = Get-Command node -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $base = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  $cands = Get-ChildItem -Path $base -Directory -Filter 'OpenJS.NodeJS.LTS_*' -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ChildItem -Path $_.FullName -Directory -Filter 'node-v*-win-x64' -ErrorAction SilentlyContinue } |
    ForEach-Object { Join-Path $_.FullName 'node.exe' } |
    Where-Object { Test-Path $_ }

  return $cands | Select-Object -First 1
}

function Resolve-LarkRoot {
  $hardcoded = 'D:\softwares\Nodejs\node_global\node_modules\@larksuiteoapi\lark-mcp'
  if (Test-Path $hardcoded) { return $hardcoded }

  $cmd = Get-Command npm -ErrorAction SilentlyContinue
  if ($cmd) {
    $npmRoot = (& npm root -g 2>$null | Select-Object -First 1)
    if ($npmRoot) {
      $candidate = Join-Path $npmRoot '@larksuiteoapi\lark-mcp'
      if (Test-Path $candidate) { return $candidate }
    }
  }

  $appDataCandidate = Join-Path $env:APPDATA 'npm\node_modules\@larksuiteoapi\lark-mcp'
  if (Test-Path $appDataCandidate) { return $appDataCandidate }

  return ''
}

function Ensure-UserToken(
  [string]$nodeExe,
  [string]$readTokenScript,
  [string]$larkRoot,
  [string]$appId,
  [string]$appSecret,
  [string]$domain,
  [switch]$ForceRefresh
) {
  $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $refreshSkewSeconds = 120

  $tokenRaw = & $nodeExe $readTokenScript --larkRoot $larkRoot --appId $appId
  $tokenInfo = $tokenRaw | ConvertFrom-Json
  if ($tokenInfo.ok -and (-not $ForceRefresh)) {
    $exp = 0.0
    [void][double]::TryParse([string]$tokenInfo.expiresAt, [ref]$exp)
    if (($exp -gt 0) -and ($exp -gt ($nowEpoch + $refreshSkewSeconds))) {
      return $tokenInfo
    }
    LogInfo "User token expired or expiring soon. Attempting lark-mcp login..."
  }

  $err = [string]$tokenInfo.error
  if (($tokenInfo.ok -ne $true) -and ($err -notlike 'no user token*') -and (-not $ForceRefresh)) { return $tokenInfo }

  if (($tokenInfo.ok -ne $true) -and ($err -like 'no user token*')) {
    LogInfo "No user token found for appId=$appId. Attempting lark-mcp login..."
  }
  $larkCmd = Get-Command lark-mcp -ErrorAction SilentlyContinue
  if (-not $larkCmd) {
    throw "Failed to read user token: $err. lark-mcp CLI not found in PATH."
  }

  if (-not $appSecret) {
    throw "Failed to read user token: $err. appSecret is required to auto-login."
  }

  & $larkCmd.Source login --app-id $appId --app-secret $appSecret --domain $domain
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to read user token: $err. lark-mcp login failed with exit code $LASTEXITCODE."
  }

  $tokenRaw = & $nodeExe $readTokenScript --larkRoot $larkRoot --appId $appId
  $tokenInfo = $tokenRaw | ConvertFrom-Json
  return $tokenInfo
}

function Invoke-FeishuGet([string]$url) {
  $maxRetry = 1
  for ($attempt = 0; $attempt -le $maxRetry; $attempt++) {
    try {
      $resp = Invoke-RestMethod -Method Get -Uri $url -Headers $script:headers
      if (($resp -and ($resp.code -eq 99991677)) -and ($attempt -lt $maxRetry)) {
        LogInfo "Feishu token expired (code=99991677). Refreshing token and retrying..."
        $script:tokenInfo = Ensure-UserToken $script:nodeExe $script:readTokenScript $script:larkRoot $script:appId $script:appSecret $script:domain -ForceRefresh
        if (-not $script:tokenInfo.ok) {
          throw "Failed to refresh user token: $($script:tokenInfo.error)"
        }
        $script:userToken = $script:tokenInfo.userAccessToken
        $script:headers = @{ Authorization = "Bearer $($script:userToken)" }
        continue
      }
      return $resp
    } catch {
      $errMsg = [string]$_.Exception.Message
      $detailMsg = ''
      if ($_.ErrorDetails) { $detailMsg = [string]$_.ErrorDetails.Message }
      $isExpired = ($errMsg -like '*99991677*') -or ($detailMsg -like '*99991677*') -or ($errMsg -like '*Authentication token expired*') -or ($detailMsg -like '*Authentication token expired*')
      if ($isExpired -and ($attempt -lt $maxRetry)) {
        LogInfo "Feishu token expired in HTTP error. Refreshing token and retrying..."
        $script:tokenInfo = Ensure-UserToken $script:nodeExe $script:readTokenScript $script:larkRoot $script:appId $script:appSecret $script:domain -ForceRefresh
        if (-not $script:tokenInfo.ok) {
          throw "Failed to refresh user token: $($script:tokenInfo.error)"
        }
        $script:userToken = $script:tokenInfo.userAccessToken
        $script:headers = @{ Authorization = "Bearer $($script:userToken)" }
        continue
      }
      throw
    }
  }

  throw "Feishu GET retry exhausted: $url"
}

function Join-Lines([System.Collections.Generic.List[string]]$lines) {
  return (($lines.ToArray()) -join "`r`n")
}

function Get-SafeFileName([string]$name) {
  # 中文说明：将在线文档标题收束为稳定文件名，便于人工检索且避免非法路径字符。
  if (-not $name) { return 'untitled' }

  $safe = $name.Trim()
  $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
  foreach ($ch in $invalidChars) {
    $safe = $safe.Replace([string]$ch, '_')
  }

  $safe = [System.Text.RegularExpressions.Regex]::Replace($safe, '\s+', '_')
  $safe = [System.Text.RegularExpressions.Regex]::Replace($safe, '_{2,}', '_')
  $safe = $safe.Trim(' ', '.', '_')

  if (-not $safe) { return 'untitled' }
  return $safe
}

function Convert-DocxElementsToMarkdown([object[]]$elements) {
  # 中文说明：将飞书富文本元素尽量转换为 Markdown 行内格式，作为可读缓存层。
  if (-not $elements) { return '' }

  $parts = New-Object 'System.Collections.Generic.List[string]'
  foreach ($el in $elements) {
    if ($null -eq $el) { continue }

    if ($el.PSObject.Properties.Name -contains 'text_run') {
      $textRun = $el.text_run
      $text = [string]$textRun.content
      $style = $textRun.text_element_style

      if ($style) {
        if ([bool]$style.inline_code) { $text = '`' + $text + '`' }
        if ([bool]$style.bold) { $text = "**$text**" }
        if ([bool]$style.italic) { $text = "*$text*" }
        if ([bool]$style.strikethrough) { $text = "~~$text~~" }
        if ([bool]$style.underline) { $text = "<u>$text</u>" }
      }

      $parts.Add($text)
      continue
    }

    if ($el.PSObject.Properties.Name -contains 'mention_user') {
      $name = [string]$el.mention_user.name
      if (-not $name) { $name = '用户' }
      $parts.Add("@$name")
      continue
    }

    if ($el.PSObject.Properties.Name -contains 'reminder') {
      $parts.Add('[提醒]')
      continue
    }

    if ($el.PSObject.Properties.Name -contains 'equation') {
      $parts.Add('`' + [string]$el.equation.content + '`')
      continue
    }

    if ($el.PSObject.Properties.Name -contains 'docs_link') {
      $link = [string]$el.docs_link.url
      $text = [string]$el.docs_link.text
      if (-not $text) { $text = $link }
      if ($link) {
        $parts.Add("[$text]($link)")
      } else {
        $parts.Add($text)
      }
      continue
    }

    $parts.Add(($el | ConvertTo-Json -Depth 6 -Compress))
  }

  return ($parts.ToArray() -join '')
}

function Convert-DocxBlocksToMarkdown([object[]]$items, [string]$documentId) {
  # 中文说明：Markdown 只负责“可读展示”，完整格式仍由 JSON 缓存承载。
  $lines = New-Object 'System.Collections.Generic.List[string]'
  if (-not $items) { return '' }

  foreach ($item in $items) {
    if (-not $item) { continue }
    $blockType = [int]$item.block_type
    $line = ''

    switch ($blockType) {
      1 {
        $title = Convert-DocxElementsToMarkdown @($item.page.elements)
        if ($title) {
          $lines.Add("# $title")
          $lines.Add('')
        }
        continue
      }
      2 { $line = Convert-DocxElementsToMarkdown @($item.text.elements) }
      3 { $line = '# ' + (Convert-DocxElementsToMarkdown @($item.heading1.elements)) }
      4 { $line = '## ' + (Convert-DocxElementsToMarkdown @($item.heading2.elements)) }
      5 { $line = '### ' + (Convert-DocxElementsToMarkdown @($item.heading3.elements)) }
      6 { $line = '#### ' + (Convert-DocxElementsToMarkdown @($item.heading4.elements)) }
      7 { $line = '##### ' + (Convert-DocxElementsToMarkdown @($item.heading5.elements)) }
      8 { $line = '###### ' + (Convert-DocxElementsToMarkdown @($item.heading6.elements)) }
      9 { $line = '**H7** ' + (Convert-DocxElementsToMarkdown @($item.heading7.elements)) }
      10 { $line = '**H8** ' + (Convert-DocxElementsToMarkdown @($item.heading8.elements)) }
      11 { $line = '**H9** ' + (Convert-DocxElementsToMarkdown @($item.heading9.elements)) }
      12 { $line = '- ' + (Convert-DocxElementsToMarkdown @($item.bullet.elements)) }
      13 { $line = '1. ' + (Convert-DocxElementsToMarkdown @($item.ordered.elements)) }
      14 {
        $codeText = Convert-DocxElementsToMarkdown @($item.code.elements)
        $lines.Add('```')
        if ($codeText) { $lines.Add($codeText) }
        $lines.Add('```')
        $lines.Add('')
        continue
      }
      15 { $line = '> ' + (Convert-DocxElementsToMarkdown @($item.quote.elements)) }
      17 {
        $todoText = Convert-DocxElementsToMarkdown @($item.todo.elements)
        $isDone = $false
        if ($item.todo -and $item.todo.style -and ($item.todo.style.PSObject.Properties.Name -contains 'done')) {
          $isDone = [bool]$item.todo.style.done
        }
        $mark = if ($isDone) { 'x' } else { ' ' }
        $line = "- [$mark] $todoText"
      }
      19 { $line = '> [!NOTE] ' + (Convert-DocxElementsToMarkdown @($item.callout.elements)) }
      22 { $line = '---' }
      23 { $line = "[附件块: $([string]$item.block_id)]" }
      27 { $line = "[图片块: $([string]$item.block_id)]" }
      31 { $line = "[表格块: $([string]$item.block_id)]" }
      default { $line = "[未转换块 type=$blockType id=$([string]$item.block_id)]" }
    }

    if ($line -ne '') {
      $lines.Add($line)
      $lines.Add('')
    }
  }

  return (Join-Lines $lines).Trim()
}

function Fetch-DocxBlocks([string]$domain, [string]$documentId) {
  # 中文说明：分页拉取整篇文档的 block 列表，用于保存完整格式结构。
  $items = @()
  $pageToken = ''
  $hasMore = $true

  while ($hasMore) {
    $url = "$domain/open-apis/docx/v1/documents/$documentId/blocks?page_size=500"
    if ($pageToken) {
      $url += "&page_token=$([uri]::EscapeDataString($pageToken))"
    }

    $resp = Invoke-FeishuGet $url
    if ($resp.code -ne 0) { throw "docx blocks failed ($documentId): $($resp.msg)" }

    if ($resp.data -and $resp.data.items) {
      $items += @($resp.data.items)
    }

    $hasMore = [bool]($resp.data.has_more)
    $pageToken = [string]($resp.data.page_token)
  }

  return ,$items
}

function Normalize-DocLang([object]$v) {
  if ($null -eq $v) { return 0 }

  # API accepts lang as enum: 0/1/2 (see error: options [0,1,2]).
  # Accept ints directly, or common strings in local config.
  if ($v -is [int]) { return $v }
  $s = ([string]$v).Trim().ToLowerInvariant()
  if (-not $s) { return 0 }

  $asInt = 0
  if ([int]::TryParse($s, [ref]$asInt)) { return $asInt }

  switch ($s) {
    '0' { return 0 }
    '1' { return 1 }
    '2' { return 2 }
    'zh' { return 0 }
    'cn' { return 0 }
    'zh_cn' { return 0 }
    'zh-cn' { return 0 }
    'en' { return 1 }
    'ja' { return 2 }
    'jp' { return 2 }
    default { return 0 }
  }
}

function Resolve-SpaceIdByName([string]$domain, [hashtable]$headers, [string]$spaceName) {
  $want = ([string]$spaceName).Trim()
  if (-not $want) { throw 'spaceName is empty' }

  $matches = @()
  $pageToken = ''
  $hasMore = $true
  while ($hasMore) {
    $url = "$domain/open-apis/wiki/v2/spaces?page_size=50"
    if ($pageToken) {
      $url += "&page_token=$([uri]::EscapeDataString($pageToken))"
    }

    $resp = Invoke-FeishuGet $url
    if ($resp.code -ne 0) { throw "spaces list failed: $($resp.msg)" }

    $items = @()
    if ($resp.data -and $resp.data.items) { $items = @($resp.data.items) }
    foreach ($s in $items) {
      $name = ([string]$s.name).Trim()
      if ([string]::Equals($name, $want, [System.StringComparison]::OrdinalIgnoreCase)) {
        $matches += $s
      }
    }

    $hasMore = [bool]($resp.data.has_more)
    $pageToken = [string]($resp.data.page_token)
  }

  if ($matches.Count -eq 1) { return [string]$matches[0].space_id }
  if ($matches.Count -eq 0) { throw "spaceName not found (no visible wiki space matched): $want" }

  $ids = ($matches | ForEach-Object { [string]$_.space_id }) -join ', '
  throw "spaceName matched multiple spaces. Please set spaceId explicitly. name=$want ids=$ids"
}

if (-not (Test-Path $bindingPath)) {
  throw "Binding file not found: $bindingPath"
}

$binding = Get-Content -Raw $bindingPath | ConvertFrom-Json

$local = $null
if (Test-Path $localPath) {
  try {
    $local = Get-Content -Raw $localPath | ConvertFrom-Json
    LogInfo "Loaded local overrides: $localPath"
  } catch {
    throw "Failed to parse $localPath as JSON: $($_.Exception.Message)"
  }
}

$spaceId = Get-Cfg 'spaceId'
$spaceToken = Get-Cfg 'spaceToken'
$spaceName = Get-Cfg 'spaceName'

$appConfigRel = $binding.appConfigPath
if ($local -and $local.appConfigPath) { $appConfigRel = $local.appConfigPath }
if (-not $appConfigRel) { $appConfigRel = '../lark-mcp.config.json' }
$appConfigPath = Resolve-Path (Join-Path $scriptDir $appConfigRel)
$config = Get-Content -Raw $appConfigPath | ConvertFrom-Json

$appId = $config.appId
if (-not $appId) { throw "appId missing in $appConfigPath" }
$appSecret = [string]$config.appSecret

$domain = $config.domain
if (-not $domain) { $domain = 'https://open.feishu.cn' }
$domain = $domain.TrimEnd('/')

$nodeExe = Resolve-NodeExe
if (-not $nodeExe) { throw 'node.exe not found. install Node.js LTS first.' }

$larkRoot = Resolve-LarkRoot
if (-not $larkRoot) { throw 'Cannot locate @larksuiteoapi/lark-mcp installation.' }

LogInfo "Using lark-mcp root: $larkRoot"

$tokenInfo = Ensure-UserToken $nodeExe $readTokenScript $larkRoot $appId $appSecret $domain
if (-not $tokenInfo.ok) {
  throw "Failed to read user token: $($tokenInfo.error)"
}

$userToken = $tokenInfo.userAccessToken
$headers = @{ Authorization = "Bearer $userToken" }

$effectiveSpaceId = $spaceId
if (-not $effectiveSpaceId) {
  # spaceToken is a human-friendly identifier in kb.binding.json.
  # Current implementation treats it as:
  # - numeric => spaceId
  # - otherwise => spaceName (resolved via spaces list API)
  if ($spaceToken) {
    if ($spaceToken -match '^\d+$') {
      $effectiveSpaceId = $spaceToken
    } else {
      $spaceName = $spaceToken
    }
  }

  if (-not $effectiveSpaceId) {
    if ($spaceName) {
      LogInfo "Resolving spaceId by spaceName: $spaceName"
      $effectiveSpaceId = Resolve-SpaceIdByName $domain $headers $spaceName
    } else {
      throw 'spaceId is required, or provide spaceToken/spaceName (kb.binding.json or kb.local.json)'
    }
  }
}

$spaceResp = Invoke-FeishuGet "$domain/open-apis/wiki/v2/spaces/$effectiveSpaceId"
if ($spaceResp.code -ne 0) { throw "space query failed: $($spaceResp.msg)" }

function Fetch-NodesPage([string]$spaceId, [string]$parentNodeToken) {
  $items = @()
  $pageToken = ''
  $hasMore = $true
  while ($hasMore) {
    $url = "$domain/open-apis/wiki/v2/spaces/$spaceId/nodes?page_size=50"
    if ($parentNodeToken) {
      $url += "&parent_node_token=$([uri]::EscapeDataString($parentNodeToken))"
    }
    if ($pageToken) {
      $url += "&page_token=$([uri]::EscapeDataString($pageToken))"
    }

    $nodeResp = Invoke-FeishuGet $url
    if ($nodeResp.code -ne 0) { throw "nodes query failed: $($nodeResp.msg)" }

    if ($nodeResp.data.items) { $items += @($nodeResp.data.items) }
    $hasMore = [bool]$nodeResp.data.has_more
    $pageToken = [string]$nodeResp.data.page_token
  }
  return ,$items
}

# Recursively traverse all nodes in the space (tree walk via parent_node_token).
$allNodes = @()
$nodeByToken = @{}
$seenParents = @{}
$q = New-Object 'System.Collections.Generic.Queue[string]'
$q.Enqueue('')

while ($q.Count -gt 0) {
  $parent = [string]$q.Dequeue()
  if ($seenParents.ContainsKey($parent)) { continue }
  $seenParents[$parent] = $true

  $nodes = Fetch-NodesPage $effectiveSpaceId $parent
  foreach ($n in $nodes) {
    $nt = [string]$n.node_token
    if (-not $nt) { continue }

    if (-not $nodeByToken.ContainsKey($nt)) {
      $nodeByToken[$nt] = $n
      $allNodes += $n
    }

    if ([bool]$n.has_child) {
      $q.Enqueue($nt)
    }
  }
}

$space = $spaceResp.data.space
$generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

# 中文说明：这里先统一确定缓存与展示目录，保证后续所有产物都落到约定位置。
$cacheEnabled = $true
$cacheDir = $defaultCacheDir
$designDir = $defaultDesignDir
$bundlePath = Join-Path $cacheDir 'KB_CACHE.md'
$indexPath = Join-Path $cacheDir 'cache_index.json'
$cacheLang = 0
$cacheTtlHours = 24
$cacheForceRefresh = $true
$includeNodeTokens = @()
$cacheAllNodes = $true

$cacheEnabled = [bool](Get-CfgCache 'enabled' $cacheEnabled)
$cacheDir = Resolve-RelPath $scriptDir ([string](Get-CfgCache 'dir' $cacheDir))
$designDir = Resolve-RelPath $scriptDir ([string](Get-CfgCache 'designDir' $designDir))
$bundlePath = Resolve-RelPath $scriptDir ([string](Get-CfgCache 'bundlePath' $bundlePath))
$indexPath = Resolve-RelPath $scriptDir ([string](Get-CfgCache 'indexPath' $indexPath))
$cacheLang = Normalize-DocLang (Get-CfgCache 'lang' $cacheLang)
$cacheTtlHours = [int](Get-CfgCache 'ttlHours' $cacheTtlHours)
$cacheForceRefresh = [bool](Get-CfgCache 'forceRefresh' $cacheForceRefresh)
$includeNodeTokens = @(Get-CfgArr 'includeNodeTokens')
$cacheAllNodes = [bool](Get-CfgCache 'allNodes' $cacheAllNodes)

$cacheMdPath = Join-Path $cacheDir 'KB_CONTEXT.md'
$cacheJsonPath = Join-Path $cacheDir 'KB_CONTEXT.json'
New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
New-Item -ItemType Directory -Path $designDir -Force | Out-Null

$md = @()
$md += '# Feishu KB Context'
$md += ''
$md += "- GeneratedAt: $generated"
$md += "- SpaceId: $($space.space_id)"
$md += "- SpaceName: $($space.name)"
$md += "- Visibility: $($space.visibility)"
$md += "- NodeCount: $($allNodes.Count)"
$md += "- Scopes: $([string]::Join(', ', $tokenInfo.scopes))"
$md += ''
$md += '## Nodes'
$md += ''

if ($allNodes.Count -eq 0) {
  $md += '- (no nodes visible)'
} else {
  foreach ($n in $allNodes) {
    $md += "- [$($n.obj_type)] $($n.title)"
    $md += "  - node_token: $($n.node_token)"
    $md += "  - obj_token: $($n.obj_token)"
  }
}

$mdText = ($md -join "`r`n") + "`r`n"
Set-Content -Path $cacheMdPath -Value $mdText -Encoding UTF8

$jsonOut = [ordered]@{
  generatedAt = $generated
  space = $space
  nodes = $allNodes
  scopes = $tokenInfo.scopes
}
$jsonOut | ConvertTo-Json -Depth 8 | Set-Content -Path $cacheJsonPath -Encoding UTF8

LogInfo "KB synced: $($space.name) / nodes=$($allNodes.Count)"

# 中文说明：目录已在前面统一初始化，这里直接进入缓存产物生成。
if ($cacheEnabled) {
  LogInfo "Caching enabled. cacheDir=$cacheDir designDir=$designDir ttlHours=$cacheTtlHours forceRefresh=$cacheForceRefresh"

  $tokenSet = @{}
  if ((-not $cacheAllNodes) -and ($includeNodeTokens.Count -gt 0)) {
    foreach ($t in $includeNodeTokens) { if ($t) { $tokenSet[[string]$t] = $true } }
  }

  $cacheIndex = @()
  foreach ($n in $allNodes) {
    if ((-not $cacheAllNodes) -and ($includeNodeTokens.Count -gt 0) -and (-not $tokenSet.ContainsKey([string]$n.node_token))) {
      continue
    }

    # 中文说明：当前缓存仅处理 docx，但会同时输出 Markdown 可读缓存和 JSON 结构缓存。
    $isDocx = ([string]$n.obj_type) -eq 'docx'
    if (-not $isDocx) {
      $cacheIndex += [ordered]@{
        node_token = [string]$n.node_token
        obj_type = [string]$n.obj_type
        obj_token = [string]$n.obj_token
        title = [string]$n.title
        cached = $false
        reason = 'unsupported obj_type (only docx blocks are cached)'
      }
      continue
    }

    $docId = [string]$n.obj_token
    if (-not $docId) { continue }

    # 中文说明：文件名采用“文档标题 + 文档ID”，兼顾人工检索与稳定唯一性。
    $safeTitle = Get-SafeFileName ([string]$n.title)
    $cacheBaseName = "{0}_{1}" -f $safeTitle, $docId
    $cacheFileMd = Join-Path $designDir ("{0}.md" -f $cacheBaseName)
    $cacheFileJson = Join-Path $cacheDir ("{0}.json" -f $cacheBaseName)
    $needFetch = $true
    if ((-not $cacheForceRefresh) -and (Test-Path $cacheFileMd) -and (Test-Path $cacheFileJson)) {
      if ($cacheTtlHours -le 0) {
        $needFetch = $false
      } else {
        $age = (New-TimeSpan -Start (Get-Item $cacheFileJson).LastWriteTime -End (Get-Date)).TotalHours
        if ($age -lt $cacheTtlHours) { $needFetch = $false }
      }
    }

    if ($needFetch) {
      LogInfo "Fetching docx blocks: $($n.title) ($docId)"
      $docBlocks = Fetch-DocxBlocks $domain $docId

      # 中文说明：JSON 保存完整块结构，作为后续解析和格式还原的真实来源。
      $jsonPayload = [ordered]@{
        document_id = $docId
        title = [string]$n.title
        fetched_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        source_api = 'docx/v1/documents/{document_id}/blocks'
        lang = $cacheLang
        items = @($docBlocks)
      }
      $jsonPayload | ConvertTo-Json -Depth 12 | Set-Content -Path $cacheFileJson -Encoding UTF8

      # 中文说明：Markdown 只做阅读友好缓存，方便代理和人工快速查看。
      $markdown = Convert-DocxBlocksToMarkdown @($docBlocks) $docId
      Set-Content -Path $cacheFileMd -Value $markdown -Encoding UTF8
    } else {
      LogInfo "Cache hit: $($n.title) ($docId)"
    }

    $fiMd = Get-Item $cacheFileMd
    $fiJson = Get-Item $cacheFileJson
    $cacheIndex += [ordered]@{
      node_token = [string]$n.node_token
      obj_type = [string]$n.obj_type
      obj_token = $docId
      title = [string]$n.title
      cache_file_md = [string]$cacheFileMd
      cache_file_json = [string]$cacheFileJson
      cached_at = $fiJson.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
      md_bytes = [int]$fiMd.Length
      json_bytes = [int]$fiJson.Length
      source_api = 'docx blocks'
      cached = $true
    }
  }

  $cacheIndex | ConvertTo-Json -Depth 6 | Set-Content -Path $indexPath -Encoding UTF8

  $bundle = @()
  $bundle += '# Feishu KB Cache'
  $bundle += ''
  $bundle += "- GeneratedAt: $generated"
  $bundle += "- SpaceId: $($space.space_id)"
  $bundle += "- SpaceName: $($space.name)"
  $bundle += "- ItemsIndexed: $($cacheIndex.Count)"
  $bundle += "- DocsCached: $((@($cacheIndex | Where-Object { $_.cached -eq $true })).Count)"
  $bundle += ''

  foreach ($e in $cacheIndex) {
    if (-not $e.cached) { continue }
    $bundle += "## [docx] $($e.title)"
    $bundle += ''
    $bundle += "- node_token: $($e.node_token)"
    $bundle += "- obj_token: $($e.obj_token)"
    $bundle += "- cached_at: $($e.cached_at)"
    $bundle += "- source_api: $($e.source_api)"
    $bundle += "- cache_file_md: $($e.cache_file_md)"
    $bundle += "- cache_file_json: $($e.cache_file_json)"
    $bundle += ''
    $bundle += '```md'
    $bundle += (Get-Content -Raw $e.cache_file_md)
    $bundle += '```'
    $bundle += ''
  }

  Set-Content -Path $bundlePath -Value (($bundle -join "`r`n") + "`r`n") -Encoding UTF8
  LogInfo "KB cache bundle written: $bundlePath"
}










