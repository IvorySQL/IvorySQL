# Regenerates expected/ora_character_datatype_functions.out for the new
# ora_regexp_count regression queries (issue #1480).
# Run from the repo root ON A MACHINE WITH A CONFIGURED + BUILT IvorySQL tree.
# Reproduces plan Task 2, Steps 2-5, deterministically:
#   1. run the oracle-check regression for the test
#   2. verify the three new regexp_count results are exactly 2/5/3
#   3. copy results -> expected
#   4. re-run the test and confirm green
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\regenerate-ora-regexp-count-expected.ps1

$ErrorActionPreference = "Stop"

$SqlFile    = "contrib/ivorysql_ora/sql/ora_character_datatype_functions.sql"
$Expected   = "contrib/ivorysql_ora/expected/ora_character_datatype_functions.out"
$Results    = "contrib/ivorysql_ora/results/ora_character_datatype_functions.out"
$TestName   = "ora_character_datatype_functions"

if (-not (Test-Path $SqlFile)) {
    Write-Error "Run from the repo root: '$SqlFile' not found."
}

# Expected results of the three appended queries, in file order.
$ExpectedValues = @(2, 5, 3)

function Invoke-OracleCheck {
    param([string]$Label)
    Write-Host "== $Label =="
    & make -C "contrib/ivorysql_ora" "oracle-check" "ORA_REGRESS='$TestName'"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "oracle-check failed ($Label). Aborting without touching expected/."
    }
}

Write-Host "This script MUST be run on a machine with a built IvorySQL tree (make/perl toolchain)."
$yes = Read-Host "Continue? [y/N]"
if ($yes -notin @("y", "Y")) {
    Write-Host "Aborted."
    exit 1
}

# Step 1: run the test. The new tail will diff against the stale expected file.
Invoke-OracleCheck "step 1/4 - initial run (expect diff at the new queries only)"

if (-not (Test-Path $Results)) {
    Write-Error "No results file at '$Results' after the run."
}

# Step 2: extract the last three integer results and verify 2/5/3.
$ints = Get-Content $Results |
    ForEach-Object { if ($_ -match '^\s*(\d+)\s*$') { [int]$matches[1] } }
$tail = @($ints[-3..-1])
if ($tail.Count -lt 3) {
    Write-Error "Could not extract three numeric results from '$Results'."
}
for ($i = 0; $i -lt 3; $i++) {
    if ($tail[$i] -ne $ExpectedValues[$i]) {
        Write-Error "Unexpected result at position ${i}: got $($tail[$i]), expected $($ExpectedValues[$i]). " +
                    "Review the diff before copying anything. Aborting."
    }
}
Write-Host "Verified new results: $($tail -join ', ') (expected $($ExpectedValues -join ', '))"

# Step 3: copy results -> expected.
Copy-Item $Results $Expected -Force
Write-Host "Copied '$Results' -> '$Expected'"

# Step 4: re-run and confirm green.
Invoke-OracleCheck "step 4/4 - re-run after copying expected (expect all pass)"

Write-Host "Done. Commit with:"
Write-Host "  git add $Expected"
Write-Host "  git commit -m ""feat: update expected output for ora_regexp_count newline counting"""
