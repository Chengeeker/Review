param(
    [string]$OutputPath = 'D:\App\开发文档\Review.md'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Read-ProjectDocument([string]$relativePath) {
    $path = Join-Path $projectRoot $relativePath
    return [System.IO.File]::ReadAllText($path, $utf8).Replace("`r`n", "`n").TrimEnd()
}

$current = Read-ProjectDocument 'DEVELOPMENT.md'
$changelog = Read-ProjectDocument 'docs/CHANGELOG.md'
$retrospective = Read-ProjectDocument 'docs/RETROSPECTIVE.md'
$history = Read-ProjectDocument 'docs/archive/Review-legacy-2026-09-23.md'

# Make cross-document references point to sections inside this complete file.
$current = $current.Replace('(docs/CHANGELOG.md)', '(#review-changelog)')
$current = $current.Replace('(docs/RETROSPECTIVE.md)', '(#review-retrospective)')
$current = $current.Replace('(docs/archive/Review-legacy-2026-09-23.md)', '(#review-history)')
$changelog = $changelog.Replace('(../DEVELOPMENT.md#', '(#')
$changelog = $changelog.Replace('(../DEVELOPMENT.md)', '(#review-current)')
$changelog = $changelog.Replace('(archive/Review-legacy-2026-09-23.md)', '(#review-history)')
$retrospective = $retrospective.Replace('(../DEVELOPMENT.md#', '(#')
$retrospective = $retrospective.Replace('(../DEVELOPMENT.md)', '(#review-current)')
$retrospective = $retrospective.Replace('(archive/Review-legacy-2026-09-23.md)', '(#review-history)')
$retrospective = $retrospective.Replace('(CHANGELOG.md#', '(#')
$history = $history.Replace(
    '(file:///D:/App/Review/lib/core/constants/api_constants.dart)',
    '(../Review/lib/core/constants/api_constants.dart)'
)

$versionLine = Select-String -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $versionLine) { throw 'pubspec.yaml 中没有版本号。' }
$version = $versionLine.Matches[0].Groups[1].Value

$parts = @(
    '# Review 开发文档（完整汇编）',
    '',
    "> 当前源码版本：``$version``。本文档把当前开发说明、变更记录、工程复盘和旧版综合手册全文放在同一个文件中。当前行为以第一部分和实际源码为准；第四部分是历史记录，旧接口与旧操作建议可能已失效。文档不保存真实凭据。",
    '',
    '- [当前开发说明](#review-current)',
    '- [变更与构建记录](#review-changelog)',
    '- [工程复盘与防回归要点](#review-retrospective)',
    '- [旧版综合手册全文](#review-history)',
    '',
    '---',
    '',
    '<a id="review-current"></a>',
    $current,
    '',
    '---',
    '',
    '<a id="review-changelog"></a>',
    $changelog,
    '',
    '---',
    '',
    '<a id="review-retrospective"></a>',
    $retrospective,
    '',
    '---',
    '',
    '<a id="review-history"></a>',
    '> 以下为截至 2026-09-23 的旧版手册原文。它保留历史事实与当时的判断；发生冲突时以当前开发说明、源码和实测结果为准。',
    '',
    $history,
    ''
)

$output = [string]::Join("`n", $parts)
$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    throw "输出目录不存在：$parent"
}
[System.IO.File]::WriteAllText($OutputPath, $output, $utf8)
Write-Output "已生成：$OutputPath（$($output.Length) 字符）"
