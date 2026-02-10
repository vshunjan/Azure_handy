# ====== SET THESE ======
$SubscriptionId = "02b98042-1212-4509-8d49-0ba32945c9cd"
#$WorkspaceResourceId = "75e5c9cc-edc7-409e-bf58-48d5848cc06c"
$ResourceGroup = $null  # optional

Set-AzContext -SubscriptionId $SubscriptionId
$WorkspaceResourceId = "/subscriptions/02b98042-1212-4509-8d49-0ba32945c9cd/resourceGroups/sub2_core/providers/Microsoft.OperationalInsights/workspaces/core-services-log-analytics-workspace"
$ResourceGroup = $null  # set to "SUB2_SPData" if you want to limit

#Connect-AzAccount | Out-Null

$storageAccounts =
if ($ResourceGroup) {
  Get-AzStorageAccount -ResourceGroupName $ResourceGroup
} else {
  Get-AzStorageAccount
}

$services = @(
  "blobServices/default",
  "fileServices/default",
  "queueServices/default",
  "tableServices/default"
)

foreach ($sa in $storageAccounts) {
  Write-Host "== Storage Account: $($sa.StorageAccountName) =="

  foreach ($svc in $services) {
    $targetId = "$($sa.Id)/$svc"
    $diagName = "to-law-$($svc -replace '/','-')"

    Write-Host "  -> Enabling diagnostics on: $targetId"

    # JSON payload for diagnostic setting
    $payload = @{
      properties = @{
        workspaceId = $WorkspaceResourceId
        logs = @(
          @{ category = "StorageRead";  enabled = $true }
          @{ category = "StorageWrite"; enabled = $true }
          @{ category = "StorageDelete";enabled = $true }
        )
        metrics = @(
          @{ category = "Transaction"; enabled = $true }
        )
        # Optional: destination type (leave out if you don't care)
        # logAnalyticsDestinationType = "Dedicated"
      }
    } | ConvertTo-Json -Depth 10

    try {
      New-AzDiagnosticSetting `
        -Name $diagName `
        -ResourceId $targetId `
        -JsonString $payload `
        -ErrorAction Stop | Out-Null
    }
    catch {
      Write-Warning "    Failed on $targetId : $($_.Exception.Message)"
    }
  }
}
