# Workload

This lab does not ship a custom Dockerfile. `infra/main.bicep` deploys the
Container App with the Microsoft-published Container Apps hello-world image:

```text
mcr.microsoft.com/azuredocs/containerapps-helloworld:latest
```

The image listens on port `80`, returns `200 OK` on `/`, and is used across
Microsoft Learn Container Apps quickstarts. Using this image keeps the lab
focused on the network path (Application Gateway → Private DNS Zone → ILB
edge proxy → container app subnet NSG) rather than on image build, ACR
provisioning, or workload identity — none of which affect the NSG-Destination
failure mode this lab reproduces.

If the operator needs a custom application (for example to prove that a
different response body arrives after the fix), replace the `placeholderImage`
parameter of `infra/main.bicep` at deployment time and rebuild the image into
their own registry. The container ingress `targetPort` must be updated to
match the new image's listen port.
