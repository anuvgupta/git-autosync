<#
.SYNOPSIS
    Register a git-autosync Scheduled Task for a repo.
.EXAMPLE
    .\install.ps1 C:\path\to\repo -Interval 300
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$RepoPath,
    [string]$Label,
    [int]$Interval = 300,
    [string]$Log,
    [string]$Python,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    @'
Usage: .\install.ps1 <repo-path> [options]

Options:
  -Label LABEL        scheduled task name   (default: git-autosync-<repo-name>)
  -Interval SECS      sync interval         (default: 300; minimum 60)
  -Log PATH           log file path         (default: %LOCALAPPDATA%\git-autosync\<label>.log)
  -Python PATH        python interpreter    (default: first python.exe on PATH)
  -Help               show this help
'@ | Write-Host
}

if ($Help -or -not $RepoPath) {
    Show-Usage
    if (-not $RepoPath) { Write-Error 'repo path is required' }
    exit 0
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Resolve-Path (Join-Path $scriptDir '..\..')

# Task Scheduler repetition has a one-minute floor.
if ($Interval -lt 60) { Write-Error "-Interval must be >= 60 (Task Scheduler granularity); got $Interval" }

if (-not $Python) {
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $cmd) { Write-Error 'python.exe not found on PATH (pass -Python)' }
    $Python = $cmd.Source
}
if (-not (Test-Path -LiteralPath $Python)) { Write-Error "python not found: $Python" }

# Reject the WSL/Store shim: it cannot be launched by Task Scheduler.
if ($Python -like '*\WindowsApps\python*.exe') {
    Write-Error "refusing the Microsoft Store python shim ($Python); install real Python or pass -Python"
}

$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
    Write-Error "$RepoPath is not a git repository"
}
$repoName = Split-Path -Leaf $RepoPath

if (-not $Label) { $Label = "git-autosync-$repoName" }
if (-not $Log)   { $Log   = Join-Path $env:LOCALAPPDATA "git-autosync\$Label.log" }

$scriptPath = (Join-Path $repoRoot 'sync.py')
if (-not (Test-Path -LiteralPath $scriptPath)) { Write-Error "sync.py not found at $scriptPath" }

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Log) | Out-Null

$userId      = "$env:USERDOMAIN\$env:USERNAME"
$intervalIso = 'PT{0}M' -f [int][math]::Round($Interval / 60)
# Time trigger starts now, so repetition arms in the current session
# rather than waiting for the next logon.
$startBoundary = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')

Write-Host 'Configuring git-autosync (Task Scheduler):'
Write-Host "  Repo:     $RepoPath"
Write-Host "  Label:    $Label"
Write-Host "  Interval: ${Interval}s  ($intervalIso)"
Write-Host "  Log:      $Log"
Write-Host "  Python:   $Python"

$xml = Get-Content -LiteralPath (Join-Path $scriptDir 'scheduledtask.xml.template') -Raw
foreach ($pair in @(
    @{ k = '{{LABEL}}';        v = $Label },
    @{ k = '{{SCRIPT_PATH}}';  v = $scriptPath },
    @{ k = '{{REPO_PATH}}';    v = $RepoPath },
    @{ k = '{{INTERVAL_ISO}}'; v = $intervalIso },
    @{ k = '{{LOG_PATH}}';     v = $Log },
    @{ k = '{{PYTHON}}';       v = $Python },
    @{ k = '{{USER_ID}}';      v = $userId },
    @{ k = '{{START_BOUNDARY}}'; v = $startBoundary }
)) { $xml = $xml.Replace($pair.k, $pair.v) }

Register-ScheduledTask -TaskName $Label -Xml $xml -Force | Out-Null
Start-ScheduledTask -TaskName $Label

Write-Host "Done. Status: Get-ScheduledTask -TaskName $Label | Get-ScheduledTaskInfo"
Write-Host "Logs:        Get-Content -Wait '$Log'"
Write-Host ''
Write-Host 'Note: the task runs at logon and repeats on the interval, so it syncs only'
Write-Host '      while this user is logged in (same scope as a macOS LaunchAgent).'
Write-Host '      git push uses your credential helper -- confirm push works manually first.'
