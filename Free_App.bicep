@description('Name of the App Service (Web App)')
param webAppName string = 'test-webapp-${uniqueString(resourceGroup().id)}'

@description('Location for the App Service')
param location string = resourceGroup().location

@description('Name of the App Service Plan')
param appServicePlanName string

@description('Environment tag')
param environmentTag string = 'devtest'

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  tags: {
    'resource-usage': 'rts'
    'resource-user': environmentTag
  }
  kind: 'app'
  properties: {
    serverFarmId: appServicePlanName
    httpsOnly: true
    siteConfig: {
      alwaysOn: false
      netFrameworkVersion: 'v6.0'  // or empty string for Node/PHP etc.
      scmType: 'None'
    }
  }
}
