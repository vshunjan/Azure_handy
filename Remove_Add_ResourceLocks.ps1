# Install Az if needed
if (-not (Get-Module -ListAvailable -Name Az)) {
  Install-Module Az -Scope CurrentUser -Repository PSGallery -Force
}

# Sign in (interactive)
Connect-AzAccount

# (Optional) pick subscription
Set-AzContext -Subscription "02b98042-1212-4509-8d49-0ba32945c9cd"


## run separately to output locks on a RG to a file
$rg = "s2-databases"

# Show the RG-level lock(s)
$rgLevelLocks = Get-AzResourceLock -ResourceGroupName $rg -AtScope
$rgLevelLocks | Select-Object Name, LockLevel, Notes, LockId

# Export for safe keeping (optional)
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$exportFile = "C:\junk\locks_rg_${rg}_$ts.json"
$rgLevelLocks | ConvertTo-Json -Depth 5 | Out-File $exportFile -Encoding utf8
Write-Host "Exported RG-level locks to $exportFile"

# Delete the RG-level lock(s)
$rgLevelLocks | ForEach-Object {
  Remove-AzResourceLock -LockId $_.LockId -Force
}
