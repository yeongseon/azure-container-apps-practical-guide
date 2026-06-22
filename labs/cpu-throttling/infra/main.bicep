targetScope = 'resourceGroup'

@description('Base name for all resources')
param baseName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Initial CPU allocation per replica. Intentionally low (0.25 vCPU) so trigger.sh can demonstrate throttling under burst load. verify.sh raises this to 1.0 vCPU and re-runs the same load test to prove the bottleneck was per-replica CPU.')
param initialCpu string = '0.25'

@description('Initial memory allocation per replica. 0.5 Gi is the smallest valid pair for 0.25 vCPU per the Container Apps CPU/memory matrix.')
param initialMemory string = '0.5Gi'

@description('Public Python image used to host the inline CPU-burn HTTP server. The lab uses python:3.12-slim because (a) it is small, (b) it carries the standard library so no pip install is required, and (c) it is identical across the cpu=0.25 and cpu=1.0 runs so the only experimental variable is the per-replica CPU allocation.')
param baseImage string = 'python:3.12-slim'

// Inline Python CPU-burn HTTP server. Each GET / executes 80 SHA-256 hashes
// over a 200 KiB buffer, which costs ~40 ms of CPU on a full vCPU and ~160 ms
// on 0.25 vCPU once Linux CFS throttling kicks in. The script binds 8080 to
// avoid privileged-port issues, sets allow_reuse_address so a redeploy does
// not stall on TIME_WAIT, and is the ONLY experimental variable — the
// container image, command, and args are byte-identical across the
// cpu=0.25 baseline run and the cpu=1.0 post-fix run.
var pythonScript = '''
import http.server, hashlib, socketserver
class H(http.server.BaseHTTPRequestHandler):
  def do_GET(s):
    b = b'x' * 204800
    for _ in range(80):
      hashlib.sha256(b).hexdigest()
    s.send_response(200)
    s.send_header('Content-Type', 'text/plain')
    s.end_headers()
    s.wfile.write(b'OK')
  def log_message(s, *a):
    pass
class T(socketserver.ThreadingMixIn, http.server.HTTPServer):
  daemon_threads = True
  allow_reuse_address = True
T(('', 8080), H).serve_forever()
'''

var suffix = take(uniqueString(resourceGroup().id, baseName), 6)
var logAnalyticsName = 'log-${baseName}-${suffix}'
var environmentName = 'cae-${baseName}-${suffix}'
var appName = 'ca-${baseName}-${suffix}'

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

resource environment 'Microsoft.App/managedEnvironments@2023-05-01' = {
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
  }
}

resource app 'Microsoft.App/containerApps@2023-05-01' = {
  name: appName
  location: location
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
    }
    template: {
      containers: [
        {
          name: 'app'
          image: baseImage
          command: [
            'python'
            '-c'
          ]
          args: [
            pythonScript
          ]
          resources: {
            cpu: json(initialCpu)
            memory: initialMemory
          }
        }
      ]
      scale: {
        // Pin minReplicas == maxReplicas == 1 so a scale-out cannot mask
        // per-replica CPU pressure. The hypothesis under test is specifically
        // about CPU throttling at the replica level, not about scale-out
        // policy. A separate lab (replica-load-imbalance) covers scale-out.
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

output logAnalyticsWorkspaceName string = logAnalytics.name
output logAnalyticsWorkspaceId string = logAnalytics.id
output environmentName string = environment.name
output containerAppName string = app.name
output containerAppFqdn string = app.properties.configuration.ingress.fqdn
