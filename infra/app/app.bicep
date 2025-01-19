param containerAppsEnvironmentName string
param containerAppName string
param location string = resourceGroup().location
param tags object = {}
param storageAccountName string
param appCustomDomainName string = ''
param msTenantId string
param msClientId string
param msClientSecretKV string
param msAllowedGroupId string = ''
param userAssignedIdentityName string

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: userAssignedIdentityName
}

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: storageAccountName
  resource blobService 'blobServices' = {
    name: 'default'
    resource tokenStore 'containers' = {
      name: 'token-store'
    }
  }
  resource fileService 'fileServices' = {
    name: 'default'
    resource nginx 'shares' = {
      name: 'nginx'
    }
  }
}

// See https://learn.microsoft.com/en-us/rest/api/storagerp/storage-accounts/list-service-sas
var tokenStoreSas = storage.listServiceSAS('2022-05-01', {
  canonicalizedResource: '/blob/${storage.name}/${storage::blobService::tokenStore.name}'
  signedProtocol: 'https'
  signedResource: 'c'
  signedPermission: 'rwdl'
  signedExpiry: '3000-01-01T00:00:00Z'
}).serviceSasToken
var tokenStoreUrl = 'https://${storage.name}.blob.${environment().suffixes.storage}/${storage::blobService::tokenStore.name}?${tokenStoreSas}'

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-10-02-preview' existing = {
  name: containerAppsEnvironmentName
  resource nginx 'storages' = {
    name: 'nginx'
    properties: {
      azureFile: {
        accessMode: 'ReadWrite'
        accountName: storage.name
        accountKey: storage.listKeys().keys[0].value
        shareName: storage::fileService::nginx.name
      }
    }
  }
}

resource certificate 'Microsoft.App/managedEnvironments/managedCertificates@2024-10-02-preview' = if (!empty(appCustomDomainName)) {
  parent: containerAppsEnvironment
  name: 'cert-${appCustomDomainName}'
  location: location
  tags: tags
  properties: {
    subjectName: appCustomDomainName
    domainControlValidation: 'CNAME'
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: containerAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        customDomains: empty(appCustomDomainName)
          ? null
          : [
              {
                name: appCustomDomainName
                certificateId: certificate.id
                bindingType: 'SniEnabled'
              }
            ]
      }
      secrets: [
        {
          name: 'microsoft-provider-authentication-secret'
          keyVaultUrl: msClientSecretKV
          identity: userAssignedIdentity.id
        }
        {
          name: 'token-store-url'
          value: tokenStoreUrl
        }
      ]
    }
    template: {
      volumes: [
        {
          name: 'nginx'
          storageName: containerAppsEnvironment::nginx.name
          storageType: 'AzureFile'
        }
      ]
      containers: [
        {
          name: 'nginx'
          image: 'nginx'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          volumeMounts: [
            {
              volumeName: 'nginx'
              subPath: 'templates'
              mountPath: '/etc/nginx/templates'
            }
            {
              volumeName: 'nginx'
              subPath: 'data'
              mountPath: '/data'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
        cooldownPeriod: 3600
      }
    }
  }

  resource authConfigs 'authConfigs' = if (!empty(msTenantId) && !empty(msClientId)) {
    name: 'current'
    properties: {
      identityProviders: {
        azureActiveDirectory: {
          registration: {
            clientId: msClientId
            clientSecretSettingName: 'microsoft-provider-authentication-secret'
            openIdIssuer: 'https://sts.windows.net/${msTenantId}/v2.0'
          }
          validation: {
            allowedAudiences: [
              'api://${msClientId}'
            ]
            defaultAuthorizationPolicy: {
              allowedPrincipals: {
                groups: empty(msAllowedGroupId) ? null : [msAllowedGroupId]
              }
            }
          }
          login: {
            loginParameters: ['scope=openid profile email offline_access']
          }
        }
      }
      platform: {
        enabled: true
      }
      login: {
        tokenStore: {
          enabled: true
          azureBlobStorage: {
            sasUrlSettingName: 'token-store-url'
          }
        }
      }
    }
  }
}

output id string = containerApp.id
output name string = containerApp.name
output fqdn string = containerApp.properties.configuration.ingress.fqdn
output properties object = containerApp.properties
