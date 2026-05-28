**# Usage:
#   ./scripts/install.sh [--dry-run] <overlay-yaml> [storageClass] [namespace]
#
# Examples:
#   ./scripts/install.sh values-multicluster.yaml
#   ./scripts/install.sh --dry-run values-multicluster.yaml
#   ./scripts/install.sh values-multicluster.yaml gp3**

helm install k10 kasten/k10 \
  -f base-values.yaml \ 
  --namespace kasten-io \ 
  --create-namespace

helm upgrade --install k10 kasten/k10 \
  -f base-values.yaml \
  -f overlays/<scenario>.yaml \
  -n kasten-io \
  --create-namespace

#SCENARIO: OPENSHIFT + TOKEN
-f base-values.yaml \
-f overlays/values-auth-token.yaml

#SCENARIO: OpenShift + Self-Signed (POC)
-f base-values.yaml \
-f overlays/values-selfsigned-insecure.yaml

#SCENARIO: RKE2 + Ingress + Token
-f base-values.yaml \
-f overlays/values-auth-token.yaml \ 
-f overlays/values-ingress.yaml

#SCENARIO: Bare Metal + NodePort + Basic Auth
-f base-values.yaml \
-f overlays/values-auth-basic.yaml \ 
-f overlays/values-nodeport.yaml 

#SCENARIO: Multi-Cluster (Recommended)
-f base-values.yaml \
-f overlays/values-auth-token.yaml \
-f overlays/values-multicluster.yaml

⚠️ Important Notes
Do NOT mix insecureCA: true and cacertconfigmap
insecureCA: true
cacertconfigmap

PVC sizes cannot be modified via Helm after creation
Always use /k10/ path for ingress/route
/k10/

Use stable DNS for multi-cluster setups

✅ Best Practices
Keep base-values.yaml stable
base-values.yaml

Use overlays for environment-specific configs
Avoid heavy use of --set
--set

Version control all YAML files
Re-bootstrap secondaries after cert/DNS changes


## 📁 REPOSITORY STRUCTURE

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

📌 Summary
This structure enables:
- Consistent deployments
- Faster troubleshooting
- Clean multi-cluster setups
- Easy migration between environments


🤝 Contributing
Add new overlays for additional environments
Keep configs minimal and composable
Validate all YAML with Helm before committing


📄 License
Internal / customer-facing use. Customize as needed.

=======
# kasten-helm-templates
