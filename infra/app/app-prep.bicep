param containerAppsEnvironmentName string
param containerAppName string
param dnsDomainName string
param dnsWildcard bool = false
param location string = resourceGroup().location
param tags object = {}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-08-01-preview' existing = {
  name: containerAppsEnvironmentName
}

var baseDomain = { name: dnsDomainName, certificateId: null, bindingType: 'Disabled' }
var wildcardDomain = { name: '*.${dnsDomainName}', certificateId: null, bindingType: 'Disabled' }

resource containerApp 'Microsoft.App/containerApps@2023-08-01-preview' = {
  name: containerAppName
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        customDomains: empty(dnsDomainName) ? null : concat([baseDomain], dnsWildcard ? [wildcardDomain] : [])
      }
    }
    template: {
      containers: [
        {
          name: 'hellowrold'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
        }
      ]
    }
  }
}

output fqdn string = containerApp.properties.configuration.ingress.fqdn
