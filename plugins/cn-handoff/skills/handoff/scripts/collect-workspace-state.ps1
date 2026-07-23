[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path = "."
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Stop-Collector {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code
    )

    [Console]::Error.WriteLine("collector_error=$Code")
    exit 2
}

function Invoke-GitReadOnly {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkingPath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& git -C $WorkingPath @Arguments 2>$null)
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = $output
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Test-GitMarkerInAncestry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StartPath
    )

    $currentItem = Get-Item -LiteralPath $StartPath
    while ($null -ne $currentItem) {
        if (Test-Path -LiteralPath (Join-Path $currentItem.FullName ".git")) {
            return $true
        }
        $currentItem = $currentItem.Parent
    }
    return $false
}

$resolvedItem = Get-Item -LiteralPath (Resolve-Path -LiteralPath $Path).Path
$resolvedPath = if ($resolvedItem.PSIsContainer) { $resolvedItem.FullName } else { $resolvedItem.DirectoryName }
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
$isGitRepository = $false
$workspaceRoot = $resolvedPath
$branch = $null
$head = $null
$upstream = $null
$upstreamHead = $null
$ahead = $null
$behind = $null
$statusLines = @()
$gitStatusAvailable = $false
$worktreeCount = 0
$nestedRepositoryCount = 0
$remoteCount = 0

if ($null -ne $gitCommand) {
    $rootResult = Invoke-GitReadOnly -WorkingPath $resolvedPath -Arguments @("rev-parse", "--show-toplevel")
    if ($rootResult.ExitCode -eq 0 -and $rootResult.Output.Count -gt 0) {
        $isGitRepository = $true
        $workspaceRoot = [System.IO.Path]::GetFullPath([string]$rootResult.Output[0])

        $branchResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("branch", "--show-current")
        if ($branchResult.ExitCode -ne 0) { Stop-Collector -Code "git_branch_unavailable" }
        if ($branchResult.Output.Count -gt 0) {
            $branch = [string]$branchResult.Output[0]
        }
        if ([string]::IsNullOrWhiteSpace($branch)) { $branch = "DETACHED" }

        $headResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("rev-parse", "HEAD")
        if ($headResult.ExitCode -ne 0 -or $headResult.Output.Count -eq 0) { Stop-Collector -Code "git_head_unavailable" }
        $head = [string]$headResult.Output[0]

        $upstreamResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
        if ($upstreamResult.ExitCode -eq 0 -and $upstreamResult.Output.Count -gt 0) {
            $upstream = [string]$upstreamResult.Output[0]

            $upstreamHeadResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("rev-parse", "@{u}")
            if ($upstreamHeadResult.ExitCode -ne 0 -or $upstreamHeadResult.Output.Count -eq 0) {
                Stop-Collector -Code "git_upstream_head_unavailable"
            }
            $upstreamHead = [string]$upstreamHeadResult.Output[0]

            $driftResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("rev-list", "--left-right", "--count", "HEAD...@{u}")
            if ($driftResult.ExitCode -ne 0 -or $driftResult.Output.Count -eq 0) {
                Stop-Collector -Code "git_drift_unavailable"
            }
            $driftParts = ([string]$driftResult.Output[0]).Trim() -split "\s+"
            if ($driftParts.Count -ne 2) { Stop-Collector -Code "git_drift_invalid" }
            $aheadValue = 0
            $behindValue = 0
            $aheadParsed = [int]::TryParse($driftParts[0], [ref]$aheadValue)
            $behindParsed = [int]::TryParse($driftParts[1], [ref]$behindValue)
            if (-not $aheadParsed -or -not $behindParsed) {
                Stop-Collector -Code "git_drift_invalid"
            }
            $ahead = $aheadValue
            $behind = $behindValue
        }
        elseif ($branch -ne "DETACHED") {
            $configuredRemoteResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("config", "--get", "branch.$branch.remote")
            $configuredMergeResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("config", "--get", "branch.$branch.merge")
            if ($configuredRemoteResult.ExitCode -gt 1 -or $configuredMergeResult.ExitCode -gt 1) {
                Stop-Collector -Code "git_config_unavailable"
            }
            if ($configuredRemoteResult.Output.Count -gt 0 -or $configuredMergeResult.Output.Count -gt 0) {
                Stop-Collector -Code "git_upstream_unavailable"
            }
        }

        $statusResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("status", "--porcelain=v1")
        if ($statusResult.ExitCode -ne 0) { Stop-Collector -Code "git_status_unavailable" }
        $statusLines = @($statusResult.Output | ForEach-Object { [string]$_ })
        $gitStatusAvailable = $true

        $worktreeResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("worktree", "list", "--porcelain")
        if ($worktreeResult.ExitCode -ne 0) { Stop-Collector -Code "git_worktree_unavailable" }
        $worktreeCount = @($worktreeResult.Output | Where-Object { $_ -like "worktree *" }).Count

        $remoteResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("remote")
        if ($remoteResult.ExitCode -ne 0) { Stop-Collector -Code "git_remote_unavailable" }
        $remoteCount = $remoteResult.Output.Count
    }
    elseif (Test-GitMarkerInAncestry -StartPath $resolvedPath) {
        Stop-Collector -Code "git_root_unavailable"
    }
}

$untrackedCount = @($statusLines | Where-Object {
    $_.Length -ge 2 -and $_.Substring(0, 2) -eq "??"
}).Count
$conflictCodes = @("DD", "AU", "UD", "UA", "DU", "AA", "UU")
$conflictCount = @($statusLines | Where-Object { $_.Length -ge 2 -and $conflictCodes -contains $_.Substring(0, 2) }).Count
$stagedCount = @($statusLines | Where-Object {
    $_.Length -ge 2 -and $_.Substring(0, 2) -ne "??" -and $_.Substring(0, 1) -ne " "
}).Count
$unstagedCount = @($statusLines | Where-Object {
    $_.Length -ge 2 -and $_.Substring(0, 2) -ne "??" -and $_.Substring(1, 1) -ne " "
}).Count

if ($isGitRepository) {
    $pendingDirectories = New-Object 'System.Collections.Generic.Queue[string]'
    $pendingDirectories.Enqueue($workspaceRoot)
    while ($pendingDirectories.Count -gt 0) {
        $currentDirectory = $pendingDirectories.Dequeue()
        try {
            $entries = @(Get-ChildItem -Force -LiteralPath $currentDirectory -ErrorAction Stop)
        }
        catch {
            Stop-Collector -Code "nested_repository_scan_failed"
        }

        foreach ($entry in $entries) {
            if ($entry.Name -eq ".git") {
                if ($entry.FullName -ne (Join-Path $workspaceRoot ".git")) {
                    $nestedRepositoryCount++
                }
                continue
            }
            if ($entry.PSIsContainer -and -not ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                $pendingDirectories.Enqueue($entry.FullName)
            }
        }
    }
}

$entryNames = @(
    "AGENTS.md",
    "AGENT.md",
    "CLAUDE.md",
    "HANDOFF_交班.md",
    "HANDOFF_交班.html",
    "HANDOFF.md",
    "SESSION.md",
    "SESSION.html",
    "PROJECT.md",
    "STATUS.md",
    "RESULTS.md",
    "TODO.md",
    "README.md"
)

$entryFiles = foreach ($name in $entryNames) {
    $candidate = Join-Path $workspaceRoot $name
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $item = Get-Item -LiteralPath $candidate
        [ordered]@{
            Name = $name
            Path = $name
            Length = $item.Length
            LastWriteTime = $item.LastWriteTime.ToString("o")
            Sha256 = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}

$topLevelEntryCount = @(Get-ChildItem -Force -LiteralPath $workspaceRoot).Count
$result = [ordered]@{
    SchemaVersion = 3
    CollectedAt = [DateTimeOffset]::Now.ToString("o")
    RequestedPath = "<WORKSPACE_ROOT>"
    WorkspaceRoot = "<WORKSPACE_ROOT>"
    RepositoryName = Split-Path -Leaf $workspaceRoot
    IsGitRepository = $isGitRepository
    GitAvailable = ($null -ne $gitCommand)
    Branch = $branch
    Head = $head
    Upstream = $upstream
    UpstreamHead = $upstreamHead
    Ahead = $ahead
    Behind = $behind
    RemoteCount = $remoteCount
    GitStatus = [ordered]@{
        Available = $gitStatusAvailable
        IsDirty = if ($gitStatusAvailable) { ($statusLines.Count -gt 0) } else { $null }
        Staged = if ($gitStatusAvailable) { $stagedCount } else { $null }
        Unstaged = if ($gitStatusAvailable) { $unstagedCount } else { $null }
        Untracked = if ($gitStatusAvailable) { $untrackedCount } else { $null }
        Conflicts = if ($gitStatusAvailable) { $conflictCount } else { $null }
    }
    WorktreeCount = $worktreeCount
    NestedRepositoryCount = $nestedRepositoryCount
    EntryFiles = @($entryFiles)
    TopLevelEntryCount = $topLevelEntryCount
}

$result | ConvertTo-Json -Depth 8
