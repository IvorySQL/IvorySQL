# Creates the pull request for IvorySQL issue #1480 (branch 1480 -> upstream master).
# Run from the repo root. Idempotent-ish: if the PR already exists, prints its URL.
#
# Token resolution order:
#   1. -Token <PAT>            (Personal Access Token)
#   2. $env:GITHUB_TOKEN
#   3. $env:GH_TOKEN
#   4. `gh auth token`         (if gh CLI is installed)
#   5. none                    -> falls back to printing the compare URL
#
# Examples:
#   powershell -ExecutionPolicy Bypass -File scripts\create-pr-1480.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\create-pr-1480.ps1 -Token ghp_xxxx -OpenBrowser

param(
    [string]$Token = "",
    [switch]$OpenBrowser
)

$ErrorActionPreference = "Stop"

$Owner    = "IvorySQL"        # upstream repo owner
$BaseRepo = "IvorySQL"        # upstream repo name
$HeadFork = "leangjia"        # fork where branch 1480 lives
$Head     = "1480"
$Base     = "master"

$Title = "Optimize: ora_regexp_count skips the newline scan unless the pattern needs it"
$Body = @"
Optimize: ora_regexp_count will always count newlines (fixes #1480)

- Gate the O(n) newline scan in ora_regexp_count to patterns starting with
  '.' or '^' -- the only patterns whose num/flag values are consumed below.
  Behavior is unchanged for every existing input.
- Add 3 regression queries covering both the optimized and non-optimized
  paths (expected results 2/5/3).
- Harden .gitignore against accidental commits of credentials, local/editor
  files, and logs/temp artifacts.

NOTE: expected/ora_character_datatype_functions.out must be regenerated on a
build machine before the regression suite goes green. Run:
  scripts\regenerate-ora-regexp-count-expected.ps1
"@

function Get-Token {
    if ($Token) { return $Token }
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }
    if ($env:GH_TOKEN) { return $env:GH_TOKEN }
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($gh) {
        $t = & gh auth token 2>$null
        if ($LASTEXITCODE -eq 0 -and $t) { return $t.Trim() }
    }
    return ""
}

function Get-CompareUrl {
    return "https://github.com/$Owner/$BaseRepo/compare/$Base...${HeadFork}:${Head}"
}

$authToken = Get-Token

if (-not $authToken) {
    $url = Get-CompareUrl
    Write-Host "No GitHub token found (set GITHUB_TOKEN/GH_TOKEN, pass -Token, or install gh)."
    Write-Host "PR compare URL: $url"
    if ($OpenBrowser) { Start-Process $url }
    exit 0
}

$headers = @{
    "Authorization" = "token $authToken"
    "Accept"        = "application/vnd.github.v3+json"
}

$apiUrl = "https://api.github.com/repos/$Owner/$BaseRepo/pulls"

# Check whether the PR already exists.
$existing = $null
try {
    $existing = Invoke-RestMethod -Uri "$apiUrl?state=open&head=${HeadFork}:${Head}" -Headers $headers -Method Get
} catch {
    $existing = $null
}
if ($existing -and $existing.Count -gt 0) {
    Write-Host "PR already exists: $($existing[0].html_url)"
    if ($OpenBrowser) { Start-Process $existing[0].html_url }
    exit 0
}

$payload = @{
    title = $Title
    head  = "${HeadFork}:${Head}"
    base  = $Base
    body  = $Body
} | ConvertTo-Json

$pr = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Post -Body $payload
Write-Host "Created PR: $($pr.html_url)"
if ($OpenBrowser) { Start-Process $pr.html_url }
