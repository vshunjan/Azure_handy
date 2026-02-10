<#
.SYNOPSIS
  Create an Azure Web App using an existing App Service Plan (no global name check).

.PARAMETER SubscriptionId
  Optional. Subscription ID to use. If omitted, uses current Az context.

.PARAMETER ResourceGroup
  Resource group containing the existing App Service Plan.
  If -CreateResourceGroup is used and it doesn't exist, it's created in -Location.

.PARAMETER CreateResourceGroup
  Optional switch. Create the resource group if it doesn't exist (requires -Location).

.PARAMETER Location
  Optional. Used only when creating the resource group.

.PARAMETER AppServicePlan
  Name of the existing App Service Plan (Linux or Windows).

.PARAMETER WebAppName
  Web App name (must be globally unique under *.azurewebsites.net).

.PARAMETER Runtime
  Optional (Linux only). Examples: "DOTNETCORE|8.0", "NODE|18-lts", "PYTHON|3.12", "PHP|8.2".

.PARAMETER AssignSystemIdentity
  Optional switch. Assign a system-assigned managed identity to the Web App.

.PARAMETER AppSettings
  Optional hashtable of app settings, e.g. @{ "ENV"="prod"; "FEATURE_X"="true" }.

.PARAMETER AppSettingsJsonPath
  Optional path to a JSON file with key/value pairs for app settings.

.PARAMETER DisableFTPS
  Optional switch. Disable FTPS (use if you deploy via zip/GitHub Actions/OIDC).

.PARAMETER HttpsOnly
  Optional (default:$true). Enforce HTTPS-only on the site.
#>

[CmdletBinding()]
param(
  [string]$SubscriptionId,

  [Parameter(Mandatory)][string]$ResourceGroup,
  [switch]$CreateResourceGroup,
  [string]$Location,

  [Parameter(Mandatory)][string]$AppServicePlan,
  [Parameter(Mandatory)][string]$WebAppName,
  [string]$Runtime,

  [switch]$AssignSystemIdentity,
  [hashtable]$AppSettings,
  [string]$AppSettingsJsonPath,

  [switch]$DisableFTPS,
  [bool]$HttpsOnly = $true
)

# -------------------- Prep Az & login --------------------
try {
  # Only install/import necessary modules
  $requiredModules = "Az.Accounts", "Az.Resources", "Az.Websites"
  foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
      Write-Host "Installing required module: $module ..."
      Install-Module $module -Scope CurrentUser -Repository PSGallery -Force
    }
    Import-Module $module -ErrorAction Stop | Out-Null
  }

  if (-not (Get-AzContext)) {
    Write-Host "Sign in to Azure..."
    Connect-AzAccount -ErrorAction Stop | Out-Null
  }
} catch {
  Write-Error "Failed to prepare Az modules or sign in. $_"
  exit 1
}

# -------------------- Subscription handling --------------------
try {
  $ctx = Get-AzContext
  if ($SubscriptionId) {
    if ($ctx.Subscription.Id -ne $SubscriptionId) {
      Write-Host "Switching to subscription: $SubscriptionId"
      Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
      $ctx = Get-AzContext
    }
  }
  Write-Host "✅ Using subscription: $($ctx.Subscription.Name) ($($ctx.Subscription.Id))"
} catch {
  Write-Error "Failed to verify/set subscription. $_"
  exit 1
}

# -------------------- Ensure Microsoft.Web provider --------------------
try {
  $rp = Get-AzResourceProvider -ProviderNamespace Microsoft.Web -ErrorAction Stop
  if ($rp.RegistrationState -ne 'Registered') {
    Write-Host "Registering resource provider: Microsoft.Web ..."
    Register-AzResourceProvider -ProviderNamespace Microsoft.Web -Force | Out-Null
    # Polling is better than a fixed sleep
    while ((Get-AzResourceProvider -ProviderNamespace Microsoft.Web).RegistrationState -ne 'Registered') {
      Start-Sleep -Seconds 5
    }
    Write-Host "✅ Microsoft.Web provider registered."
  }
} catch {
  Write-Warning "Couldn't verify/register Microsoft.Web provider (continuing). $_"
}


# --- Resource group must exist in THIS subscription unless -CreateResourceGroup is used ---
$rg = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue
if (-not $rg) {
  if ($CreateResourceGroup) {
    if (-not $Location) { throw "Location is required when -CreateResourceGroup is used." }
    $rg = New-AzResourceGroup -Name $ResourceGroup -Location $Location -ErrorAction Stop
  } else {
    throw "Resource group '$ResourceGroup' not found in subscription $($ctx.Subscription.Id)."
  }
}
Write-Host "Resource group found: $($rg.ResourceGroupName) [$($rg.Location)]"


# -------------------- Get existing App Service Plan --------------------
try {
  $plan = Get-AzAppServicePlan -ResourceGroupName $ResourceGroup -Name $AppServicePlan -ErrorAction Stop
} catch {
  Write-Error "App Service Plan '$AppServicePlan' not found in RG '$ResourceGroup'. $_"
  exit 1
}

$planIsLinux  = ($plan.Kind -match 'linux')
$planLocation = $plan.Location
Write-Host "Found App Service Plan: $($plan.Name) ($($plan.Sku.Tier)/$($plan.Sku.Name)) in $planLocation [Kind: $($plan.Kind)]"

# -------------------- Create the Web App (no pre-check) --------------------
try {
  if ($planIsLinux) {
    if ($Runtime) {
      Write-Host "Creating Linux Web App '$WebAppName' (runtime '$Runtime') in '$planLocation'..."
      $app = New-AzWebApp -ResourceGroupName $ResourceGroup -Name $WebAppName `
        -Location $planLocation -AppServicePlan $AppServicePlan -RuntimeVersion $Runtime
    } else {
      Write-Host "Creating Linux Web App '$WebAppName' (no runtime) in '$planLocation'..."
      $app = New-AzWebApp -ResourceGroupName $ResourceGroup -Name $WebAppName `
        -Location $planLocation -AppServicePlan $AppServicePlan
    }
  } else {
    Write-Host "Creating Windows Web App '$WebAppName' in '$planLocation'..."
    $app = New-AzWebApp -ResourceGroupName $ResourceGroup -Name $WebAppName `
      -Location $planLocation -AppServicePlan $AppServicePlan
  }

  if (-not $app) { throw "New-AzWebApp returned no object." }
}
catch {
  $msg = $_.Exception.Message
  if ($msg -match 'already in use|already taken|already exists|Conflict') {
    Write-Error "Web App name '$WebAppName' appears to be in use globally. Choose another name and rerun."
  } else {
    Write-Error "Failed to create Web App. $msg"
  }
  exit 1
}

# -------------------- Secure defaults & options --------------------
try {
  if ($HttpsOnly) {
    Set-AzWebApp -ResourceGroupName $ResourceGroup -Name $WebAppName -HttpsOnly $true | Out-Null
  }

  if ($DisableFTPS) {
    # FTPS state via generic resource update for broad Az compatibility
    Set-AzResource -ResourceGroupName $ResourceGroup `
      -ResourceType "Microsoft.Web/sites/config" `
      -ResourceName "$WebAppName/web" `
      -ApiVersion "2023-12-01" `
      -Properties @{ ftpsState = "Disabled" } -Force | Out-Null
  }

  if ($AssignSystemIdentity) {
    try {
      if ((Get-Command Set-AzWebApp -ErrorAction SilentlyContinue).Parameters.ContainsKey('AssignIdentity')) {
        Set-AzWebApp -ResourceGroupName $ResourceGroup -Name $WebAppName -AssignIdentity | Out-Null
      } else {
        $siteResourceId = "/subscriptions/$($ctx.Subscription.Id)/resourceGroups/$ResourceGroup/providers/Microsoft.Web/sites/$WebAppName"
        Set-AzResource -ResourceId $siteResourceId -ApiVersion "2023-12-01" -PropertyObject @{ identity = @{ type = "SystemAssigned" } } -Force | Out-Null
      }
      Write-Host "✅ System-assigned managed identity enabled."
    } catch {
      Write-Warning "Couldn't assign system identity. $_"
    }
  }

  # Merge app settings (inline + JSON) and apply
  $mergedSettings = @{}
  if ($AppSettings) { $AppSettings.GetEnumerator() | ForEach-Object { $mergedSettings[$_.Key] = [string]$_.Value } }
  if ($AppSettingsJsonPath) {
    if (-not (Test-Path $AppSettingsJsonPath)) { throw "AppSettingsJsonPath not found: $AppSettingsJsonPath" }
    $json = Get-Content $AppSettingsJsonPath -Raw | ConvertFrom-Json
    $json.PSObject.Properties | ForEach-Object { $mergedSettings[$_.Name] = [string]$_.Value }
  }
  if ($mergedSettings.Count -gt 0) {
    Set-AzWebApp -ResourceGroupName $ResourceGroup -Name $WebAppName -AppSettings $mergedSettings | Out-Null
    Write-Host "✅ Applied $(($mergedSettings.Keys | Measure-Object).Count) app settings."
  }
} catch {
  Write-Warning "Post-create configuration encountered issues. $_"
}

# -------------------- Output --------------------
Write-Host ""
Write-Host "🎉 Web App created:"
[PSCustomObject]@{
  Name          = $app.Name
  DefaultHost   = "https://$($app.DefaultHostName)"
  ResourceGroup = $ResourceGroup
  Plan          = $AppServicePlan
  Location      = $planLocation
  Kind          = $app.Kind
  HttpsOnly     = $HttpsOnly
  LinuxRuntime  = if ($planIsLinux) { $Runtime } else { $null }
} | Format-List
