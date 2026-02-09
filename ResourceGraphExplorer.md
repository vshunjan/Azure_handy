# Azure Resource Graph Explorer 

🔎 Public IPs not attached to anything (classic drift)

```
resources
| where type == "microsoft.network/publicipaddresses"
// Filter for orphaned IPs (those with no ID in the ipConfiguration property)
| where isnull(properties.ipConfiguration.id)
| extend ipconfigid = properties.ipConfiguration.id
| join kind=leftouter (
    resourcecontainers 
    | where type == "microsoft.resources/subscriptions" 
    | project subscriptionName = name, subscriptionId
) on subscriptionId
| project name, ipconfigid, resourceGroup, location, subscriptionName, subscriptionId
```


