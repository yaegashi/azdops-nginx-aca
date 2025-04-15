param storageAccountName string
param storageShareName string = ''
param principalId string = ''

var shareName = !empty(storageShareName) ? storageShareName : 'nginx'

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: storageAccountName
  resource fileService 'fileServices' existing = {
    name: 'default'
    resource nginx 'shares' = {
      name: shareName
    }
    // Resource ID "fileShares/nginx" is needed for the role assignment (nginxRole)
    // https://github.com/Azure/bicep-types-az/issues/1532
    #disable-next-line BCP081
    resource nginxForRole 'fileShares' existing = {
      name: shareName
    }
  }
}

// Azure built-in role: Storage File Data Privileged Contributor
var nginxRoleDefId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '69566ab7-960f-475b-8e7c-b3118f30c6bd'
)

// Grant file share acecss to NGINX content contributor
resource nginxRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  dependsOn: [storage::fileService::nginx]
  scope: storage::fileService::nginxForRole
  name: guid(subscription().id, resourceGroup().id, principalId, nginxRoleDefId)
  properties: {
    principalId: principalId
    roleDefinitionId: nginxRoleDefId
  }
}

output storageAccountName string = storage.name
output storageShareName string = storage::fileService::nginx.name
output principalId string = principalId
