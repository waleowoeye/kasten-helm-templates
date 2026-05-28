# kasten-helm-templates

Reusable Helm deployment templates for Veeam Kasten K10 across OpenShift, RKE2, EKS, AKS, and other Kubernetes distributions.

---

## 🚀 Usage

```bash
./scripts/install.sh [--dry-run] <overlay-yaml> [storageClass] [namespace]
```

### Examples

```bash
./scripts/install.sh values-multicluster.yaml
./scripts/install.sh --dry-run values-multicluster.yaml
./scripts/install.sh values-multicluster.yaml gp3
```

---

## 🔧 Helm Deployment Pattern

```bash
helm upgrade --install k10 kasten/k10 \
  -f base-values.yaml \
  -f overlays/<scenario>.yaml \
  -n kasten-io \
  --create-namespace
```

---

## 🎯 Deployment Scenarios

### ✅ OpenShift + Token
```bash
-f base-values.yaml \
-f overlays/values-auth-token.yaml
```

### ✅ OpenShift + Self-Signed (POC)
```bash
-f base-values.yaml \
-f overlays/values-selfsigned-insecure.yaml
```

### ✅ RKE2 + Ingress + Token
```bash
-f base-values.yaml \
-f overlays/values-auth-token.yaml \
-f overlays/values-ingress.yaml
```

### ✅ Bare Metal + NodePort + Basic Auth
```bash
-f base-values.yaml \
-f overlays/values-auth-basic.yaml \
-f overlays/values-nodeport.yaml
```

### ✅ Multi-Cluster (Recommended)
```bash
-f base-values.yaml \
-f overlays/values-auth-token.yaml \
-f overlays/values-multicluster.yaml
```

---

## 🔍 Preflight + Troubleshooting Workflow

Preflight runs automatically during install (`k10_primer.sh`).

On failure, artifacts are collected:

```bash
artifacts/
  install-<timestamp>/
    primer.log
    cluster_snapshot.txt
    events_failed.txt
    next-steps.txt
  support-<timestamp>.tar.gz (optional)
```

Key troubleshooting command:

```bash
oc get events -n kasten-io --sort-by='.metadata.creationTimestamp' | grep -i failed
```

---

## 📁 Repository Structure

```bash
.
├── README.md
├── base-values.yaml
├── overlays
│   ├── values-auth-basic.yaml
│   ├── values-auth-token.yaml
│   ├── values-cert-verified.yaml
│   ├── values-ingress.yaml
│   ├── values-multicluster.yaml
│   ├── values-nodeport.yaml
│   ├── values-prometheus-generic.yaml
│   ├── values-prometheus-openshift.yaml
│   └── values-selfsigned-insecure.yaml
└── scripts
    ├── collect-support.sh
    ├── install.sh
    ├── preflight.sh
    └── upgrade.sh
```

---

## ⚠️ Important Notes

- Do NOT mix `insecureCA: true` and `cacertconfigmap`
- PVC sizes cannot be modified via Helm after creation
- Always use `/k10/` path for ingress/route
- Use stable DNS for multi-cluster setups

---

## ✅ Best Practices

- Keep `base-values.yaml` stable
- Use overlays for environment-specific configs
- Avoid heavy use of `--set`
- Version control all YAML files
- Re-bootstrap secondaries after cert/DNS changes

---

## 📌 Summary

This structure enables:

- Consistent deployments  
- Faster troubleshooting  
- Clean multi-cluster setups  
- Easy environment portability  

---

## 🤝 Contributing

- Add overlays for new environments  
- Keep configs minimal and composable  
- Validate YAML with Helm before committing  

---

## 📄 License

Internal / customer-facing use. Customize as needed.
