[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path = "."
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

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

$resolvedItem = Get-Item -LiteralPath (Resolve-Path -LiteralPath $Path).Path
$resolvedPath = if ($resolvedItem.PSIsContainer) { $resolvedItem.FullName } else { $resolvedItem.DirectoryName }
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
$isGitRepository = $false
$workspaceRoot = $resolvedPath
$branch = $null
$head = $null
$upstream = $null
$statusLines = @()
$worktreeCount = 0
$nestedRepositoryCount = 0
$remoteCount = 0

if ($null -ne $gitCommand) {
    $rootResult = Invoke-GitReadOnly -WorkingPath $resolvedPath -Arguments @("rev-parse", "--show-toplevel")
    if ($rootResult.ExitCode -eq 0 -and $rootResult.Output.Count -gt 0) {
        $isGitRepository = $true
        $workspaceRoot = [System.IO.Path]::GetFullPath([string]$rootResult.Output[0])

        $branchResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("branch", "--show-current")
        if ($branchResult.ExitCode -eq 0 -and $branchResult.Output.Count -gt 0) {
            $branch = [string]$branchResult.Output[0]
        }
        if ([string]::IsNullOrWhiteSpace($branch)) { $branch = "DETACHED" }

        $headResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("rev-parse", "HEAD")
        if ($headResult.ExitCode -eq 0 -and $headResult.Output.Count -gt 0) {
            $head = [string]$headResult.Output[0]
        }

        $upstreamResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
        if ($upstreamResult.ExitCode -eq 0 -and $upstreamResult.Output.Count -gt 0) {
            $upstream = [string]$upstreamResult.Output[0]
        }

        $statusResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("status", "--porcelain=v1")
        if ($statusResult.ExitCode -eq 0) {
            $statusLines = @($statusResult.Output | ForEach-Object { [string]$_ })
        }

        $worktreeResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("worktree", "list", "--porcelain")
        if ($worktreeResult.ExitCode -eq 0) {
            $worktreeCount = @($worktreeResult.Output | Where-Object { $_ -like "worktree *" }).Count
        }

        $remoteResult = Invoke-GitReadOnly -WorkingPath $workspaceRoot -Arguments @("remote")
        if ($remoteResult.ExitCode -eq 0) { $remoteCount = $remoteResult.Output.Count }
    }
}

$untrackedCount = @($statusLines | Where-Object { $_ -like "??*" }).Count
$conflictCodes = @("DD", "AU", "UD", "UA", "DU", "AA", "UU")
$conflictCount = @($statusLines | Where-Object { $_.Length -ge 2 -and $conflictCodes -contains $_.Substring(0, 2) }).Count
$stagedCount = @($statusLines | Where-Object {
    $_.Length -ge 2 -and $_ -notlike "??*" -and $_.Substring(0, 1) -ne " "
}).Count
$unstagedCount = @($statusLines | Where-Object {
    $_.Length -ge 2 -and $_ -notlike "??*" -and $_.Substring(1, 1) -ne " "
}).Count

if ($null -ne $gitCommand) {
    $nestedRepositoryCount = @(
        Get-ChildItem -Force -Directory -LiteralPath $workspaceRoot |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName ".git") }
    ).Count
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
    SchemaVersion = 2
    CollectedAt = [DateTimeOffset]::Now.ToString("o")
    RequestedPath = "<WORKSPACE_ROOT>"
    WorkspaceRoot = "<WORKSPACE_ROOT>"
    RepositoryName = Split-Path -Leaf $workspaceRoot
    IsGitRepository = $isGitRepository
    GitAvailable = ($null -ne $gitCommand)
    Branch = $branch
    Head = $head
    Upstream = $upstream
    RemoteCount = $remoteCount
    GitStatus = [ordered]@{
        IsDirty = ($statusLines.Count -gt 0)
        Staged = $stagedCount
        Unstaged = $unstagedCount
        Untracked = $untrackedCount
        Conflicts = $conflictCount
    }
    WorktreeCount = $worktreeCount
    NestedRepositoryCount = $nestedRepositoryCount
    EntryFiles = @($entryFiles)
    TopLevelEntryCount = $topLevelEntryCount
}

$result | ConvertTo-Json -Depth 8
