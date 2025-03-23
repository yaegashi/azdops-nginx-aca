targetScope = 'subscription'

@minLength(1)
@maxLength(64)
param environmentName string

@minLength(1)
param location string

param principalId string

param userAssignedIdentityName string = ''

param resourceGroupName string = ''

param keyVaultName string = ''

param storageAccountName string = ''

param logAnalyticsName string = ''

param applicationInsightsName string = ''

param applicationInsightsDashboardName string = ''

param containerAppsEnvironmentName string = ''

param containerAppName string = ''

param containerAppImage string = ''

param appCertificateExists bool = false

param dnsZoneSubscriptionId string = subscription().subscriptionId

param dnsZoneResourceGroupName string = ''

param dnsZoneName string = ''

param dnsRecordName string = ''

param dnsWildcard bool = false

param dnsCertificateExists bool = false

param legoEmail string = ''

param legoServer string = 'https://acme-staging-v02.api.letsencrypt.org/directory'

param msTenantId string
param msClientId string
@secure()
param msClientSecret string
param msAllowedGroupId string = ''

var abbrs = loadJsonContent('./abbreviations.json')

var tags = {
  'azd-env-name': environmentName
}

#disable-next-line no-unused-vars
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location, rg.name))

var dnsEnable = !empty(dnsZoneResourceGroupName) && !empty(dnsZoneName) && !empty(dnsRecordName)
var dnsDomainName = !dnsEnable ? '' : dnsRecordName == '@' ? dnsZoneName : '${dnsRecordName}.${dnsZoneName}'

resource dnsZoneRG 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (dnsEnable && !appCertificateExists) {
  scope: subscription(dnsZoneSubscriptionId)
  name: dnsZoneResourceGroupName
}

module dnsTXT './app/dns-txt.bicep' = if (dnsEnable && !appCertificateExists) {
  name: 'dnsTXT'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    dnsRecordName: dnsRecordName == '@' ? 'asuid' : 'asuid.${dnsRecordName}'
    txt: env.outputs.customDomainVerificationId
  }
}

module dnsCNAME './app/dns-cname.bicep' = if (dnsEnable && !appCertificateExists && dnsRecordName != '@') {
  name: 'dnsCNAME'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    dnsRecordName: dnsRecordName
    cname: appPrep.outputs.fqdn
  }
}

module dnsCNAMEWildcard './app/dns-cname.bicep' = if (dnsEnable && !appCertificateExists && dnsRecordName != '@' && dnsWildcard) {
  name: 'dnsCNAMEWildcard'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    dnsRecordName: '*.${dnsRecordName}'
    cname: appPrep.outputs.fqdn
  }
}

module dnsA './app/dns-a.bicep' = if (dnsEnable && !appCertificateExists && dnsRecordName == '@') {
  name: 'dnsA'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    dnsRecordName: dnsRecordName
    a: env.outputs.staticIp
  }
}

module dnsAWildcard './app/dns-a.bicep' = if (dnsEnable && !appCertificateExists && dnsRecordName == '@' && dnsWildcard) {
  name: 'dnsAWildcard'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    dnsRecordName: '*'
    a: env.outputs.staticIp
  }
}

module dnsAccess './app/dns-access.bicep' = if (dnsEnable) {
  dependsOn: [KeyVaultAccessUserAssignedIdentity] // Insert delay
  name: 'dnsAccess'
  scope: dnsZoneRG
  params: {
    dnsZoneName: dnsZoneName
    principalId: userAssignedIdentity.outputs.principalId
  }
}

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module userAssignedIdentity './app/identity.bicep' = {
  name: 'userAssignedIdentity'
  scope: rg
  params: {
    name: !empty(userAssignedIdentityName)
      ? userAssignedIdentityName
      : '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
    location: location
    tags: tags
  }
}

module keyVault './core/security/keyvault.bicep' = {
  name: 'keyVault'
  scope: rg
  params: {
    name: !empty(keyVaultName) ? keyVaultName : '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
  }
}

module KeyVaultAccessUserAssignedIdentity './core/security/keyvault-access.bicep' = {
  name: 'KeyVaultAccessUserAssignedIdentity'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: userAssignedIdentity.outputs.principalId
    permissions: {
      secrets: ['list', 'get']
      certificates: ['list', 'get', 'import']
    }
  }
}

module keyVaultAccessDeployment './core/security/keyvault-access.bicep' = {
  name: 'keyVaultAccessDeployment'
  scope: rg
  params: {
    keyVaultName: keyVault.outputs.name
    principalId: principalId
    permissions: {
      secrets: ['list', 'get', 'set']
      certificates: ['list', 'get', 'import']
    }
  }
}

module keyVaultSecretMsClientSecret './core/security/keyvault-secret.bicep' = {
  name: 'keyVaultSecretMsClientSecret'
  scope: rg
  params: {
    name: 'MS-CLIENT-SECRET'
    tags: tags
    keyVaultName: keyVault.outputs.name
    secretValue: msClientSecret
  }
}

module storageAccount './core/storage/storage-account.bicep' = {
  name: 'storageAccount'
  scope: rg
  params: {
    location: location
    tags: tags
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
  }
}

module storageAccess './app/storage-access.bicep' = {
  name: 'storageAccess'
  scope: rg
  params: {
    storageAccountName: storageAccount.outputs.name
    principalId: principalId
  }
}

module monitoring './core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName)
      ? logAnalyticsName
      : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName)
      ? applicationInsightsName
      : '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: !empty(applicationInsightsDashboardName)
      ? applicationInsightsDashboardName
      : '${abbrs.portalDashboards}${resourceToken}'
  }
}

var xContainerAppsEnvironmentName = !empty(containerAppsEnvironmentName)
  ? containerAppsEnvironmentName
  : '${abbrs.appManagedEnvironments}${resourceToken}'
var xContainerAppName = !empty(containerAppName) ? containerAppName : '${abbrs.appContainerApps}${resourceToken}'
var xContainerAppImage = !empty(containerAppImage)
  ? containerAppImage
  : 'ghcr.io/yaegashi/azure-easy-auth-njs/nginx:latest'

module env './app/env.bicep' = {
  name: 'env'
  scope: rg
  params: {
    location: location
    tags: tags
    containerAppsEnvironmentName: xContainerAppsEnvironmentName
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
    userAssignedIdentityName: userAssignedIdentity.outputs.name
  }
}

module appPrep './app/app-prep.bicep' = if (dnsEnable && !appCertificateExists) {
  dependsOn: [dnsTXT]
  name: 'appPrep'
  scope: rg
  params: {
    location: location
    tags: tags
    containerAppsEnvironmentName: env.outputs.name
    containerAppName: xContainerAppName
    dnsDomainName: dnsDomainName
    dnsWildcard: dnsWildcard
  }
}

module app './app/app.bicep' = {
  dependsOn: [KeyVaultAccessUserAssignedIdentity, dnsCNAME, dnsA, appPrep]
  name: 'app'
  scope: rg
  params: {
    location: location
    tags: tags
    containerAppsEnvironmentName: env.outputs.name
    containerAppName: xContainerAppName
    containerAppImage: xContainerAppImage
    storageAccountName: storageAccount.outputs.name
    userAssignedIdentityName: userAssignedIdentity.outputs.name
    dnsDomainName: dnsDomainName
    dnsWildcard: dnsWildcard
    domainControlValidation: dnsRecordName == '@' ? 'HTTP' : 'CNAME'
    dnsCertificateKV: dnsCertificateExists ? '${keyVault.outputs.endpoint}secrets/DNS-CERTIFICATE' : ''
    msTenantId: msTenantId
    msClientId: msClientId
    msClientSecretKV: '${keyVault.outputs.endpoint}secrets/MS-CLIENT-SECRET'
    msAllowedGroupId: msAllowedGroupId
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
output AZURE_PRINCIPAL_ID string = principalId
output AZURE_RESOURCE_GROUP_NAME string = rg.name
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.endpoint
output AZURE_CONTAINER_APPS_APP_NAME string = app.outputs.name
output AZURE_STORAGE_ACCOUNT_NAME string = storageAccount.outputs.name
output APP_CERTIFICATE_EXISTS bool = !empty(dnsDomainName)
