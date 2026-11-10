$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $taskSigning = if ($env:REVIEW_KEY_PROPERTIES) { $env:REVIEW_KEY_PROPERTIES } else { 'key.properties' }
    if (!(Test-Path -LiteralPath $taskSigning -PathType Leaf)) { throw 'Release signing configuration is missing' }
    if (!$env:ANDROID_HOME -and !$env:ANDROID_SDK_ROOT) {
        $env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    }
    $taskTemp = Join-Path $PSScriptRoot 'build\.jvm-temp'
    New-Item -ItemType Directory -Path $taskTemp -Force | Out-Null
    $env:JAVA_TOOL_OPTIONS = "$env:JAVA_TOOL_OPTIONS `"-Djava.io.tmpdir=$taskTemp`" `"-Djdk.net.unixdomain.tmpdir=$taskTemp`""
    & .\gradlew.bat :app:assembleRelease :app:testDebugUnitTest :app:lintRelease --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'Build or verification failed' }
    & python tool/verify_release.py
    if ($LASTEXITCODE -ne 0) { throw 'APK verification failed' }
    $taskVersion = (Select-String -Path 'app\build.gradle.kts' -Pattern 'versionName = "([^"]+)"').Matches.Groups[1].Value
    $taskOutput = Join-Path $PSScriptRoot "Review_v$taskVersion.apk"
    Copy-Item -LiteralPath 'app\build\outputs\apk\release\app-release.apk' -Destination $taskOutput -Force
    Get-FileHash -LiteralPath $taskOutput -Algorithm SHA256
} finally {
    Pop-Location
}
