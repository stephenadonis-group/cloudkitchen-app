# Image & Vulnerability Scanning (Trivy)

CloudKitchen scans container images for OS/library CVEs and misconfigurations
with [Trivy](https://aquasecurity.github.io/trivy/) in **two places**:

1. **CI gate** — every image is scanned before it can be pushed to ECR.
2. **Runtime (optional)** — `trivy-operator` continuously rescans running
   workloads inside the cluster.

## 1. CI gate (GitHub Actions)

Scanning happens in the matrix build for each of the 8 services. The pipeline
fails (blocks the ECR push) on `HIGH`/`CRITICAL` findings with an available fix.

```yaml
# .github/workflows/ci.yaml (excerpt — runs per service in the matrix)
      - name: Build image
        run: docker build -t ck/${{ matrix.service }}:${{ github.sha }} ./${{ matrix.service }}

      - name: Trivy scan (gate)
        uses: aquasecurity/trivy-action@0.24.0
        with:
          image-ref: ck/${{ matrix.service }}:${{ github.sha }}
          format: table
          exit-code: "1"            # fail the job on findings
          severity: HIGH,CRITICAL
          ignore-unfixed: true      # only block on CVEs that have a fix
          vuln-type: os,library

      # Only reached if the scan passed:
      - name: Push to ECR
        run: |
          docker tag  ck/${{ matrix.service }}:${{ github.sha }} $ECR/cloudkitchen/${{ matrix.service }}:${{ github.sha }}
          docker push $ECR/cloudkitchen/${{ matrix.service }}:${{ github.sha }}
```

Optionally upload SARIF to GitHub code scanning:

```yaml
      - name: Trivy SARIF
        uses: aquasecurity/trivy-action@0.24.0
        with:
          image-ref: ck/${{ matrix.service }}:${{ github.sha }}
          format: sarif
          output: trivy.sarif
      - uses: github/codeql-action/upload-sarif@v3
        with: { sarif_file: trivy.sarif }
```

## 2. trivy-operator (optional, in-cluster)

Continuously generates `VulnerabilityReport` / `ConfigAuditReport` CRDs for
running workloads, surfacing CVEs that appear *after* an image was deployed.

```sh
helm repo add aqua https://aquasecurity.github.io/helm-charts
helm repo update

helm upgrade --install trivy-operator aqua/trivy-operator \
  -n trivy-system --create-namespace \
  --set trivy.severity=HIGH,CRITICAL \
  --set operator.scanJobsConcurrentLimit=3
```

Inspect findings:

```sh
kubectl get vulnerabilityreports -n cloudkitchen
kubectl get configauditreports   -n cloudkitchen
```

## Policy summary

| Stage   | Tool            | Severity gate     | Action on fail |
|---------|-----------------|-------------------|----------------|
| CI      | trivy-action    | HIGH, CRITICAL    | block ECR push |
| Runtime | trivy-operator  | HIGH, CRITICAL    | report (alert) |

`ignore-unfixed: true` keeps the gate actionable — we only block on CVEs that
have an available patch.
