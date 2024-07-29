# CBCI on an EKS cluster

List of files in this repository:
- create.sh: main script creating EKS cluster, IAM policies, service accounts, installing ALB, external-dns and CBCI helm charts
- cluster.yaml: EKS cluster definition template to be build with eksctl
- aws-load-balancer-controller-values.yaml: self-describing
- aws-load-balancer-controller-values.yaml: self-describing
- sc-gp3: gp3 storage class definition set by default in the cluster
- casc/: helm chart containing OC and MC bundles + the users definitions and their password (login.yaml) as code
- values.yaml: CBCI helm chart values
