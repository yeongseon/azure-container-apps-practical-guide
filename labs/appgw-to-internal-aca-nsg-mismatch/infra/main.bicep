targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// Lab: Application Gateway to Internal Container Apps Environment
//      with NSG Destination pinned to CAE staticIp (misconfiguration).
//
// This Bicep deploys the BASELINE happy-path state:
//   - VNet with two subnets: snet-appgw (Application Gateway) and snet-cae
//     (workload-profile Container Apps environment, delegated)
//   - NSG attached to snet-cae with NO custom rules (Azure defaults only,
//     so AllowVnetInBound at priority 65000 permits AppGW->CAE traffic).
//   - Internal Container Apps Environment (vnetConfiguration.internal = true)
//     with a Consumption workload profile.
//   - One sample Container App (internal ingress, port 80) that responds
//     200 OK on / so the Application Gateway custom probe passes.
//   - Private DNS Zone matching the CAE defaultDomain, linked to the VNet,
//     with wildcard and apex A records pointing to CAE staticIp so
//     Application Gateway can resolve the container app FQDN.
//   - Application Gateway Standard_v2 with a backend pool targeting the
//     container app FQDN, an HTTP setting that picks Host name from the
//     backend address, an HTTPS custom probe (path /, match 200-399), and
//     a Log Analytics diagnostic setting for AppGWAccessLog and
//     ApplicationGatewayFirewallLog categories.
//
// The BROKEN state is applied by trigger.sh AFTER this Bicep completes:
// trigger.sh reads env.properties.staticIp, then adds three custom NSG
// rules to snet-cae so that inbound rule 100 has Destination = staticIp
// (a single-IP misconfiguration that ignores how NSGs evaluate load-
// balanced pools). See labs/appgw-to-internal-aca-nsg-mismatch/trigger.sh.
//
// The FIXED state is applied by fix.sh: it rewrites rule 100 to use
// Destination = snet-cae CIDR. See labs/appgw-to-internal-aca-nsg-mismatch/fix.sh.
// -----------------------------------------------------------------------------

@description('Base name for all resources (lowercase letters and digits only)')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('VNet address space for the lab')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Application Gateway subnet prefix (dedicated; Azure requires /24 or larger for AppGW v2)')
param appgwSubnetPrefix string = '10.0.1.0/24'

@description('Container Apps environment infrastructure subnet prefix (workload profiles require /27 minimum; /23 recommended for headroom)')
param caeSubnetPrefix string = '10.0.2.0/23'

@description('Placeholder image for the sample container app (Container Apps hello-world, publicly pullable from MCR, listens on port 80)')
param placeholderImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var logAnalyticsName = 'log-${baseName}-${suffix}'
var environmentName = 'cae-${baseName}-${suffix}'
var appName = 'ca-${baseName}-${suffix}'
var vnetName = 'vnet-${baseName}-${suffix}'
var appgwSubnetName = 'snet-appgw'
var caeSubnetName = 'snet-cae'
var caeNsgName = 'nsg-${caeSubnetName}-${suffix}'
var appgwName = 'agw-${baseName}-${suffix}'
var appgwPublicIpName = 'pip-${appgwName}'

// -----------------------------------------------------------------------------
// Observability
// -----------------------------------------------------------------------------

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// -----------------------------------------------------------------------------
// Networking: VNet + snet-appgw + snet-cae + NSG on snet-cae
// -----------------------------------------------------------------------------
//
// The NSG attached to snet-cae is deliberately empty in the BASELINE state:
// only the Azure default rules apply, so `AllowVnetInBound` (priority 65000)
// permits AppGW subnet traffic to reach the CAE workers. This lets the
// Application Gateway backend health check pass immediately after deployment.
//
// trigger.sh introduces the misconfiguration by adding three custom NSG
// rules on top of this empty baseline. See the module-level docstring above.

resource caeNsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: caeNsgName
  location: location
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        // Application Gateway dedicated subnet. AppGW v2 requires a subnet
        // with no other services and no delegation, and Azure Network
        // requires the subnet to be at least /24 for AppGW v2 SKUs.
        // No NSG is attached here so the Azure default rule
        // `GatewayManagerInbound` (65200-65535 from GatewayManager service
        // tag) continues to permit the AppGW v2 health-check traffic that
        // Azure originates against the AppGW.
        name: appgwSubnetName
        properties: {
          addressPrefix: appgwSubnetPrefix
        }
      }
      {
        // Container Apps environment infrastructure subnet. Must be
        // delegated to Microsoft.App/environments and must be at least
        // /27 for workload-profile environments (/23 is recommended so
        // the environment has room for future workload profiles).
        name: caeSubnetName
        properties: {
          addressPrefix: caeSubnetPrefix
          delegations: [
            {
              name: 'aca-env-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          networkSecurityGroup: {
            id: caeNsg.id
          }
        }
      }
    ]
  }
}

resource appgwSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: appgwSubnetName
  parent: vnet
}

resource caeSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  name: caeSubnetName
  parent: vnet
}

// -----------------------------------------------------------------------------
// Internal Container Apps Environment + sample Container App
// -----------------------------------------------------------------------------
//
// vnetConfiguration.internal = true provisions an internal-only environment.
// The environment gets a private ILB frontend IP (env.properties.staticIp)
// that is inside caeSubnetPrefix. Container apps in this environment are
// only reachable via that ILB from clients that can resolve
// <app-name>.<env.defaultDomain> to env.properties.staticIp.

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      internal: true
      infrastructureSubnetId: caeSubnet.id
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  properties: {
    environmentId: environment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        // external: true is REQUIRED even on internal CAE environments for
        // the AppGW-via-ILB path to work. When external=false on an internal
        // env, the app FQDN gets `.internal.` prefix and is only reachable
        // via the internal service mesh (100.100.x.x range), NOT via the
        // ILB frontend (staticIp). AppGW hitting staticIp:443 with the
        // .internal. FQDN as Host header would get a 404 "Container App is
        // stopped or does not exist" from CAE edge-proxy — the app is not
        // registered in the external-facing envoy routing table.
        //
        // With external=true on an internal env, the app FQDN is
        // <app>.<defaultDomain> (no .internal.), the app IS registered in
        // envoy at the ILB, and reachability from the VNet is still gated
        // by NSG rules on snet-cae — which is exactly the scenario this
        // lab reproduces.
        external: true
        targetPort: 80
        transport: 'auto'
        allowInsecure: false
      }
    }
    template: {
      containers: [
        {
          name: 'app'
          image: placeholderImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Private DNS Zone + Application Gateway (module)
// -----------------------------------------------------------------------------
//
// The Private DNS Zone name must equal env.properties.defaultDomain, and the
// A records must resolve to env.properties.staticIp. Neither value is known
// until the environment finishes deploying. Bicep evaluates resource names
// at the START of the enclosing deployment (see BCP120), so referencing
// `environment.properties.defaultDomain` directly on a PDZ resource in this
// file fails. The workaround is a nested module: module parameters are
// evaluated when the module's inner deployment starts, so by that time
// the environment outputs are resolved.
//
// The module also creates the Application Gateway so that appFqdn (which
// depends on env.properties.defaultDomain via ingress.fqdn) is likewise
// resolvable when the AppGW resource is materialized.

module dnsAndAppgw './dns-and-appgw.bicep' = {
  name: 'deploy-dns-and-appgw'
  params: {
    location: location
    defaultDomain: environment.properties.defaultDomain
    staticIp: environment.properties.staticIp
    appFqdn: app.properties.configuration.ingress.fqdn
    vnetId: vnet.id
    appgwSubnetId: appgwSubnet.id
    appgwName: appgwName
    appgwPublicIpName: appgwPublicIpName
    vnetName: vnetName
    logAnalyticsId: logAnalytics.id
  }
}

// -----------------------------------------------------------------------------
// Outputs (consumed by trigger.sh / verify.sh / fix.sh / cleanup.sh)
// -----------------------------------------------------------------------------

output resourceGroupName string = resourceGroup().name
output environmentName string = environmentName
output environmentStaticIp string = environment.properties.staticIp
output environmentDefaultDomain string = environment.properties.defaultDomain
output appName string = appName
output appFqdn string = app.properties.configuration.ingress.fqdn
output vnetName string = vnetName
output appgwSubnetName string = appgwSubnetName
output appgwSubnetPrefix string = appgwSubnetPrefix
output caeSubnetName string = caeSubnetName
output caeSubnetPrefix string = caeSubnetPrefix
output caeNsgName string = caeNsgName
output appgwName string = appgwName
output appgwPublicIpName string = appgwPublicIpName
output appgwPublicIpAddress string = dnsAndAppgw.outputs.appgwPublicIpAddress
output privateDnsZoneName string = dnsAndAppgw.outputs.privateDnsZoneName
output logAnalyticsName string = logAnalyticsName
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
