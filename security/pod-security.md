# Pod Security

The CloudKitchen workloads run under the **restricted** Pod Security Standard
(PSS), enforced at the namespace level by the built-in Pod Security Admission
controller.

## Namespace labels

The `cloudkitchen` namespace is labeled to enforce, audit, and warn at the
`restricted` level. The namespace itself is auto-created (by ArgoCD or
`helm --create-namespace`); apply the PSS labels with `kubectl label namespace`
(see `security/README.md`):

```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

To apply/patch on an existing namespace:

```sh
kubectl label namespace cloudkitchen \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted --overwrite
```

> The `monitoring`, `logging`, `ingress`, and `argocd` namespaces run platform
> components (node-exporter, Promtail DaemonSet, etc.) that need elevated
> access, so they are labeled `privileged` / `baseline` rather than restricted.

## Compliant securityContext (example)

Every CloudKitchen Deployment must set both a pod-level and container-level
`securityContext` that satisfies the restricted profile:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order
  namespace: cloudkitchen
spec:
  template:
    spec:
      securityContext:                 # pod-level
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: order
          image: <ECR_REGISTRY>/cloudkitchen/order:latest
          ports:
            - name: http
              containerPort: 8080
          securityContext:             # container-level
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            privileged: false
            capabilities:
              drop: ["ALL"]
          # restricted profile + readOnlyRootFilesystem -> mount writable tmp
          volumeMounts:
            - name: tmp
              mountPath: /tmp
          livenessProbe:
            httpGet: { path: /healthz, port: http }
          readinessProbe:
            httpGet: { path: /readyz, port: http }
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits:   { memory: 256Mi }
      volumes:
        - name: tmp
          emptyDir: {}
```

### Restricted profile checklist
- [x] `runAsNonRoot: true` and a non-zero `runAsUser`
- [x] `allowPrivilegeEscalation: false`
- [x] `capabilities.drop: ["ALL"]`
- [x] `seccompProfile.type: RuntimeDefault`
- [x] no host namespaces, host ports, or hostPath volumes
- [x] `readOnlyRootFilesystem: true` (defense in depth; not strictly required by PSS)

The Go service Dockerfiles build minimal images (distroless / scratch) and run
as an unprivileged UID so these constraints are satisfied at runtime.
