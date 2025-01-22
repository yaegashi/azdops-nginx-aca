param dnsZoneName string
param principalId string

var roleDnsZoneContributorDefId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'befefa01-2a29-4197-83a8-272ff33ce314'
)

var roleReaderDefId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'acdd72a7-3385-48ef-bd42-f606fba81ae7'
)

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: dnsZoneName
}

resource roleDnsZoneContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: dnsZone
  name: guid(subscription().id, resourceGroup().id, principalId, roleDnsZoneContributorDefId)
  properties: {
    principalId: principalId
    roleDefinitionId: roleDnsZoneContributorDefId
  }
}

resource roleReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: dnsZone
  name: guid(subscription().id, resourceGroup().id, principalId, roleReaderDefId)
  properties: {
    principalId: principalId
    roleDefinitionId: roleReaderDefId
  }
}
