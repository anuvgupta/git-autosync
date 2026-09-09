<#
.SYNOPSIS
    Remove a git-autosync Scheduled Task.
.EXAMPLE
    .\uninstall.ps1 -Label git-autosync-knowledge
    .\uninstall.ps1 C:\path\to\repo
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$RepoPath,
    [string]$Label,
    [switch]$KeepLog,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help -or (-not $RepoPath -and -not $Label)) {
    @'
Usage: .\uninstall.ps1 [<repo-path>] [options]

Options:
  -Label LABEL   scheduled task name (default: git-autosync-<repo-name>)
  -KeepLog       leave the log file in place
  -Help          show this help
'@ | Write-Host
    if (-not $RepoPath -and -not $Label) { Write-Error 'repo path or -Label is required' }
    exit 0
}

if (-not $Label) {
    $RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
    $Label    = 'git-autosync-{0}' -f (Split-Path -Leaf $RepoPath)
}

$task = Get-ScheduledTask -TaskName $Label -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "No scheduled task named '$Label'; nothing to do."
    exit 0
}

Stop-ScheduledTask   -TaskName $Label -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $Label -Confirm:$false
Write-Host "Removed scheduled task: $Label"

if (-not $KeepLog) {
    $log = Join-Path $env:LOCALAPPDATA "git-autosync\$Label.log"
    if (Test-Path -LiteralPath $log) {
        Remove-Item -LiteralPath $log -Force
        Write-Host "Removed log: $log"
    }
}
