# Run from the repository root. Arguments are forwarded to `flutter test`.
# The SDK itself is never patched; see docs/GALLERY.md for the affected versions.
$ErrorActionPreference = 'Stop'
$testFlutterCommand = Get-Command flutter -CommandType Application -ErrorAction Stop | Select-Object -First 1
$testFlutterRoot = Split-Path -Parent (Split-Path -Parent $testFlutterCommand.Source)
$testDart = Join-Path $testFlutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
$testPackages = Join-Path $testFlutterRoot 'packages/flutter_tools/.dart_tool/package_config.json'
$testRunnerTemplate = Join-Path $PSScriptRoot 'windows_test_runner.dart.template'
$testRepository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$testOutputDirectory = Join-Path $testRepository 'build/gallery'
if (!(Test-Path -LiteralPath $testDart) -or !(Test-Path -LiteralPath $testPackages)) {
    throw 'Flutter SDK is not initialized. Run flutter --version first.'
}
New-Item -ItemType Directory -Path $testOutputDirectory -Force | Out-Null
$testRunner = Join-Path $testOutputDirectory 'windows_test_runner.dart'
Copy-Item -LiteralPath $testRunnerTemplate -Destination $testRunner -Force
& $testDart "--packages=$testPackages" $testRunner @args
exit $LASTEXITCODE
