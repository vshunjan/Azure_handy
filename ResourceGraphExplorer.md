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
