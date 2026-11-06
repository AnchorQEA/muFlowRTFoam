<#
.SYNOPSIS
Checks the assembled runtime's launcher from installation paths with and without spaces.
#>
param([Parameter(Mandatory)][string]$BundleDirectory)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('muflowrt-startup-' + [guid]::NewGuid().ToString('N'))
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Write-Output "Startup-test staging: $testRoot"

foreach ($relative in 'NoSpaces', 'Program Files\Anchor QEA') {
    $installation = Join-Path $testRoot $relative
    [void][IO.Directory]::CreateDirectory($installation)
    $bundle = Join-Path $installation 'muflowrt-ucrt64-x86_64'
    Copy-Item -LiteralPath $BundleDirectory -Destination $bundle -Recurse
    $launcher = Join-Path $bundle 'run-muflowrt.ps1'
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $powershell
    $startInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
        $launcher + '" -CaseDirectory "' + $installation + '" -SolverArguments "-help"'
    $startInfo.WorkingDirectory = $installation
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($key in @($startInfo.EnvironmentVariables.Keys)) {
        if ($key -match '^(WM_|FOAM_|PYTHONHOME$|PYTHONPATH$|_MEIPASS2$)') {
            $startInfo.EnvironmentVariables.Remove($key)
        }
    }

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        Write-Output "Testing: $launcher"
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            # Stop the launcher AND its solver; killing PowerShell alone leaves the solver running.
            & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F
            throw 'Packaged muFlowRT startup exceeded 30 seconds.'
        }
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        Write-Output $output
        if ($process.ExitCode -ne 0 -or $output -match 'stripInvalid\(' -or
            $output -notmatch '(?m)^Usage: muFlowRT\b') {
            throw "Packaged muFlowRT startup failed (exit $($process.ExitCode)): $relative"
        }
    }
    finally {
        $process.Dispose()
    }
}
Write-Output 'MUFLOWRT_STARTUP_OK'
