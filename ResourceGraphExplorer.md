# Azure Resource Graph Explorer 

## 🌐 Network / Attack Surface

### 🔎 Public IPs not attached to anything (classic drift)

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

### 🔎 NSGs allowing inbound from anywhere

```
resources
| where type == "microsoft.network/networksecuritygroups"
| mv-expand rule = properties.securityRules
| where rule.properties.direction == "Inbound"
| where rule.properties.access == "Allow"
| where rule.properties.sourceAddressPrefix == "0.0.0.0/0"
| project nsg=name, rule=rule.name, port=rule.properties.destinationPortRange
```

### 🔎 High-Risk Management Ports
```
resources
| where type == "microsoft.network/networksecuritygroups"
| mv-expand rules = properties.securityRules
| where rules.properties.access == "Allow" 
    and rules.properties.direction == "Inbound"
    and rules.properties.protocol in ("Tcp", "*")
| extend destinationPort = tostring(rules.properties.destinationPortRange)
| where destinationPort in ("3389", "22", "445") 
    or destinationPort == "*"
| project nsgName = name, ruleName = rules.name, destinationPort, resourceGroup
```

### 🔎 Public-facing exposure check (attack surface)
```
resources
| where type in (
  "microsoft.network/publicipaddresses",
  "microsoft.storage/storageaccounts",
  "microsoft.web/sites"
)
| project name, type, resourceGroup, subscriptionId
```

## 🌐 Storage 

### 🔎 Storage Accounts with Public Access

```
resources
| where type == "microsoft.storage/storageaccounts"
// Ensure the property exists and check for 'Allow'
| where properties.networkAcls.defaultAction == "Allow"
| join kind=leftouter (
    resourcecontainers 
    | where type == "microsoft.resources/subscriptions" 
    | project subscriptionName = name, subscriptionId
) on subscriptionId
| project name, resourceGroup, subscriptionName, location
```

```
resources
| where type == "microsoft.storage/storageaccounts"
| where properties.networkAcls.defaultAction == "Allow" 
    or isnull(properties.networkAcls)
| join kind=leftouter (
    resourcecontainers | where type == "microsoft.resources/subscriptions" 
    | project subscriptionName = name, subscriptionId
) on subscriptionId
| project name, resourceGroup, subscriptionName, location
```

### 🔎 Find Storage Accounts with "Public Access" Switch Enabled

```
resources
| where type == "microsoft.storage/storageaccounts"
| where properties.allowBlobPublicAccess == true
| project name, resourceGroup, location
```
**OR**
```
resources
| where type == "microsoft.storage/storageaccounts"
| where
    properties.allowBlobPublicAccess == true
    or properties.networkAcls.defaultAction == "Allow"
| project name, resourceGroup, subscriptionId
```


### 🔎 Finding Unattached (Orphaned) Managed Disks

```
resources
| where type == "microsoft.compute/disks"
// 'Unattached' means it's not currently plugged into a VM
| where properties.diskState == "Unattached"
| project name, resourceGroup, diskSizeGB = properties.diskSizeGB, subscriptionId
```

### 🔎 Storage accounts missing firewall rules

```
resources
| where type == "microsoft.storage/storageaccounts"
| where properties.networkAcls.defaultAction == "Allow"
| project name, resourceGroup
```

## Web Apps 

### Web Apps with "Easy" Security Gaps

```resources
| where type == "microsoft.web/sites"
| where properties.httpsOnly == false 
    or properties.siteConfig.minTlsVersion != "1.2"
| project name, 
    httpsOnly = properties.httpsOnly, 
    tlsVersion = properties.siteConfig.minTlsVersion, 
    resourceGroup
```

### App Services without Managed Identity (secrets risk)
```
resources
| where type == "microsoft.web/sites"
| where isnull( identity )
| project name, resourceGroup, subscriptionId
``` 

**Daily question answered:**

“Where are secrets probably hard-coded?”

## General 

### 🔎 New resources without tags (ownership + cost risk)

```
resources
| where isempty(tags)
| project name, type, resourceGroup, subscriptionId
```

Daily question answered:

“Who owns this and who’s paying for it?”

🔐 From a security POV, untagged = unmanaged.

### 🔎 What changed overnight? (silent drift detector)

```
resources
| where properties.provisioningState == "Succeeded"
| project name, type, resourceGroup, subscriptionId, location
```

💡 Why
Confirms everything is still in a good state
Useful before deployments / after change windows


### 🔎 Orphaned resources (cost + clutter)

```
resources
| where type in~ (
    "microsoft.network/publicipaddresses",
    "microsoft.compute/disks",
    "microsoft.network/networkinterfaces"
)
| extend isOrphaned = case(
    type == "microsoft.network/publicipaddresses", isnull(properties.ipConfiguration.id),
    type == "microsoft.compute/disks", properties.diskState == "Unattached",
    type == "microsoft.network/networkinterfaces", isnull(properties.virtualMachine.id),
    false
)
| where isOrphaned == true
| project name, type, resourceGroup, location, subscriptionId
| join kind=leftouter (resourcecontainers | where type == "microsoft.resources/subscriptions" | project subscriptionName = name, subscriptionId) on subscriptionId
| project name, type, resourceGroup, subscriptionName, location
``` 

### 🔎 Resources created in the wrong region

```
resources
| where location !in ("uksouth","ukwest")
| project name, type, location, resourceGroup
```

### 🔎 Function Apps / Web Apps still referencing old storage

```
resources
| where type == "microsoft.web/sites"
| extend appSettings = properties.siteConfig.appSettings
| where appSettings has "AzureWebJobsStorage"
| project name, resourceGroup, subscriptionId
```

*“What runtime dependencies still exist?”*

