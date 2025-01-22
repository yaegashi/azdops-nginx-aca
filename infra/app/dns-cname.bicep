param dnsZoneName string
param dnsRecordName string
param cname string
param wildcard bool = false

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: dnsZoneName
}

resource dnsRecord 'Microsoft.Network/dnsZones/CNAME@2018-05-01' = {
  parent: dnsZone
  name: dnsRecordName
  properties: {
    TTL: 3600
    CNAMERecord: {
      cname: cname
    }
  }
}

resource dnsRecordWildcard 'Microsoft.Network/dnsZones/CNAME@2018-05-01' = if (wildcard) {
  parent: dnsZone
  name: '*.${dnsRecordName}'
  properties: {
    TTL: 3600
    CNAMERecord: {
      cname: cname
    }
  }
}
