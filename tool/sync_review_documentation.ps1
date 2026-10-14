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
$topBarSpec = Read-ProjectDocument 'docs/FROSTED_TOP_BAR_DESIGN_SPEC.md'
$uiReuseSpec = Read-ProjectDocument 'docs/REVIEW_UI_REUSE_SPEC.md'
$gallerySwipeGuide = Read-ProjectDocument 'docs/IMAGE_GALLERY_SWIPE_PERFORMANCE_GUIDE.md'

# Make cross-document references point to sections inside this complete file.
$current = $current.Replace('(docs/CHANGELOG.md)', '(#review-changelog)')
$current = $current.Replace('(docs/RETROSPECTIVE.md)', '(#review-retrospective)')
$current = $current.Replace('(docs/FROSTED_TOP_BAR_DESIGN_SPEC.md)', '(#review-topbar-spec)')
$current = $current.Replace('(docs/REVIEW_UI_REUSE_SPEC.md)', '(#review-ui-reuse-spec)')
$current = $current.Replace('(docs/IMAGE_GALLERY_SWIPE_PERFORMANCE_GUIDE.md)', '(#review-gallery-swipe-guide)')
$current = $current.Replace('(docs/archive/Review-legacy-2026-09-23.md)', '(#review-history)')
$changelog = $changelog.Replace('(../DEVELOPMENT.md#', '(#')
$changelog = $changelog.Replace('(../DEVELOPMENT.md)', '(#review-current)')
$changelog = $changelog.Replace('(archive/Review-legacy-2026-09-23.md)', '(#review-history)')
$retrospective = $retrospective.Replace('(../DEVELOPMENT.md#', '(#')
$retrospective = $retrospective.Replace('(../DEVELOPMENT.md)', '(#review-current)')
$retrospective = $retrospective.Replace('(archive/Review-legacy-2026-09-23.md)', '(#review-history)')
$retrospective = $retrospective.Replace('(CHANGELOG.md#', '(#')
$versionLine = Select-String -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $versionLine) { throw 'pubspec.yaml 中没有版本号。' }
$version = $versionLine.Matches[0].Groups[1].Value

$parts = @(
    '# Review 开发文档（完整汇编）',
    '',
    "> 当前源码版本：``$version``。本文档汇编当前开发说明、完整变更记录、工程复盘、可迁移的磨砂顶栏设计规范、M3 UI 复用规范与图片画廊连续滑动指南。过时旧版手册不再混入现行内容，仓库原件仅供追溯。当前行为以开发说明、源码和验证结果为准；文档不保存真实凭据。",
    '',
    '- [当前开发说明](#review-current)',
    '- [变更与构建记录](#review-changelog)',
    '- [工程复盘与防回归要点](#review-retrospective)',
    '- [可迁移的磨砂顶栏设计规范](#review-topbar-spec)',
    '- [M3 UI 复用规范与提示词](#review-ui-reuse-spec)',
    '- [图片画廊连续滑动性能修复方案](#review-gallery-swipe-guide)',
    '- [历史归档边界](#review-history)',
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
    '<a id="review-topbar-spec"></a>',
    $topBarSpec,
    '',
    '---',
    '',
    '<a id="review-ui-reuse-spec"></a>',
    $uiReuseSpec,
    '',
    '---',
    '',
    '<a id="review-gallery-swipe-guide"></a>',
    $gallerySwipeGuide,
    '',
    '---',
    '',
    '<a id="review-history"></a>',
    '## 历史归档边界',
    '',
    '> 截至 2026-09-23 的旧版综合手册包含已被后续实现修订的接口判断、配置和操作建议，为避免过时做法混入现行说明，全文不再拼入本汇编。原件仍保存在 Review 仓库的 `docs/archive/Review-legacy-2026-09-23.md`，仅供追溯；当前规则以本文件前述开发说明、源码和验证结果为准。',
    ''
)

$output = [string]::Join("`n", $parts)
$parent = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    throw "输出目录不存在：$parent"
}
[System.IO.File]::WriteAllText($OutputPath, $output, $utf8)
Write-Output "已生成：$OutputPath（$($output.Length) 字符）"
