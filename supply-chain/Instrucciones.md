#### Supply chain local (opcional)

```
SBOM:
  syft packages ${IMAGE} -o spdx-json > artifacts/${SERVICE}-sbom.json
SCA:
  grype ${IMAGE} --add-cpes-if-none -o sarif > artifacts/${SERVICE}-grype.sarif
Firma:
  COSIGN_YES=true cosign sign ${IMAGE}
```
