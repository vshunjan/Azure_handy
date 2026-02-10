<# 
.SYNOPSIS
Recreate Azure locks from an exported JSON file.

.REQUIREMENTS
Az.Accounts, Az.Resources

.EXPORT JSON FORMAT (examples)
Single:
{ "Name":"lk_read", "ResourceId":"/subscriptions/.../resourceGroups/rg1/providers/Microsoft.Authorization/locks/lk_read", "Properties":{"level":"ReadOnly","notes":""} }

Array:
[
  { "Name":"lk_read", "ResourceId":"...", "Properties":{"level":"ReadOnly","notes":""} },
  { "Name":"lk_cannotdelete", "ResourceId":"...", "Properties":{"level":"CanNotDelete","notes":"protect prod"} }
]
#>

param(
  [Parameter(Mandatory=$true)]
  [string]$Path,             # Path to JSON file you exported
  [switch]$WhatIfMode        # Add -WhatIfMode to simulate changes
)

# Fail early if modules are missing
$needed = @('Az.Accounts','Az.Resources')
foreach ($m in $needed) {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    throw "Module '$m' is required. Install with: Install-Module $m -Scope CurrentUser"
  }
}

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop

# Sign in if needed
try {
  if (-not (Get-AzContext)) { Connect-AzAccount -ErrorAction Stop | Out-Null }
} catch {
  Connect-AzAccount -ErrorAction Stop | Out-Null
}

# Ingest JSON (supports single object or array)
$content = Get-Content -Path $Path -Raw
try {
  $locks = $content | ConvertFrom-Json -ErrorAction Stop
} catch {
  throw "File '$Path' does not appear to be valid JSON."
}
if ($locks -isnot [System.Collections.IEnumerable]) { $locks = @($locks) }

if (-not $locks -or $locks.Count -eq 0) {
  throw "No lock entries found in '$Path'."
}

function Get-ScopeFromLockId {
  param([string]$LockResourceId)
  # Strip the trailing "/providers/Microsoft.Authorization/locks/<name>"
  return ($LockResourceId -replace '/providers/Microsoft\.Authorization/locks/.*$','')
}

function Ensure-Lock {
  param(
    [string]$Scope,
    [string]$LockName,
    [ValidateSet('ReadOnly','CanNotDelete')]
    [string]$LockLevel,
    [string]$Notes,
    [switch]$Simulate
  )

  # Try to get the existing lock with this name at the scope
  $existing = $null
  try {
    $existing = Get-AzResourceLock -Scope $Scope -LockName $LockName -ErrorAction Stop
  } catch { $existing = $null }

  $params = @{
    Scope     = $Scope
    LockName  = $LockName
    LockLevel = $LockLevel
  }
  if ($Notes) { $params['Notes'] = $Notes }

  if ($existing) {
    $levelMatches = ($existing.Properties.level -eq $LockLevel)
    $notesMatches = ($existing.Notes -eq $Notes)

    if ($levelMatches -and $notesMatches) {
      Write-Host "[SKIP] $LockName @ $Scope already matches ($LockLevel)."
      return
    }

    # Update if different (prefer update over delete/recreate)
    Write-Host "[UPDATE] $LockName @ $Scope -> Level: $LockLevel; Notes: '$Notes'"
    if ($Simulate) {
      Set-AzResourceLock @params -WhatIf | Out-Null
    } else {
      Set-AzResourceLock @params | Out-Null
    }
  } else {
    Write-Host "[CREATE] $LockName @ $Scope -> Level: $LockLevel; Notes: '$Notes'"
    if ($Simulate) {
      New-AzResourceLock @params -WhatIf | Out-Null
    } else {
      New-AzResourceLock @params | Out-Null
    }
  }
}

# MAIN: loop each exported lock entry
foreach ($l in $locks) {
  # Defensive reads (your export uses Properties.level and Properties.notes)
  $lockName = $l.ResourceName
  if (-not $lockName) { $lockName = $l.Name }

  $lockId    = $l.ResourceId
  if (-not $lockId) { $lockId = $l.LockId }

  if (-not $lockId) {
    Write-Warning "Skipping an entry missing ResourceId/LockId."
    continue
  }

  $scope     = Get-ScopeFromLockId -LockResourceId $lockId
  $level     = $l.Properties.level
  $notes     = $l.Properties.notes

  if (-not $level -or -not $lockName) {
    Write-Warning "Skipping '$lockId' due to missing level or name."
    continue
  }

  Ensure-Lock -Scope $scope -LockName $lockName -LockLevel $level -Notes $notes -Simulate:$WhatIfMode
}

Write-Host "`nDone."