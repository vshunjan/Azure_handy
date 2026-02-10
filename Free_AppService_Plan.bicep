@description('Name of the App Service Plan')
param appServicePlanName string = 'test-app-plan-${uniqueString(resourceGroup().id)}'

@description('Location for the App Service Plan')
param location string = resourceGroup().location

@description('Environment tag (e.g. devtest, staging, prod)')
param environmentTag string = 'devtest'

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  tags: {
    'resource-usage': 'rts'
    'resource-user': environmentTag
  }
  sku: {
    name: 'F1'
    tier: 'Free'
    size: 'F1'
    family: 'F'
    capacity: 0
  }
  kind: 'app'
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: false
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
  }
}
