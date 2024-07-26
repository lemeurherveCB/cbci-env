# For local development

You must have `kubectl`, `docker` (including BuildX), and `helm` (3.0.2+) installed.

## Setup

You must have https://github.com/cloudbees/cloud-platform-v2 checked out in a sibling directory to `unified-release`.

## Docker Desktop

If you have Docker Desktop installed, with Kubernetes enabled, set your Kubernetes context to `docker-desktop` then:

```sh
make docker-desktop
```

Docker Desktop's default StorageClass uses `hostpath` volumes, which can be found using `docker volume ls`.
When you are done testing, use `docker system prune --volumes` to delete unused volumes (jenkins_home directories).

## Kubernetes in Docker (kind)

This approach works with _any_ Docker engine, including Docker Desktop without Kubernetes enabled. For more details, refer to the kind website: https://kind.sigs.k8s.io/. The `kind` CLI is required and you can install it using the instructions on the website. For OSX/Brew users, it's `brew install kind`.

To run CI locally using `kind`, run:
```bash
make kind
```

Run `docker ps` to confirm that it's running as expected. Run `docker image prune` periodically to delete untagged images and free up disk space.

## Microk8s

If you have Microk8s installed

```sh
sudo snap install --classic microk8s
microk8s.enable registry dns storage ingress rbac
microk8s.config > /tmp/kubeconfig
export KUBECONFIG=/tmp/kubeconfig
```

you can test the new images inside a live CloudBees CI installation:

```sh
make microk8s
```

## General variants

If you want to test particular versions of Jenkins components:

```sh
make microk8s
```

Remember that you can also test unreleased versions of Jenkins plugins.

```sh
mvn -f …/whatever-plugin -DskipTests clean install
```

and edit `../../../../pom.xml`:

```diff
diff --git a/pom.xml b/pom.xml
index …
--- a/pom.xml
+++ b/pom.xml
@@ … @@
             <dependency>
                 <groupId>org.jenkins-ci.plugins</groupId>
                 <artifactId>whatever</artifactId>
-                <version>1.23</version>
+                <version>1.24-SNAPSHOT</version>
                 <type>hpi</type>
                 <scope>provided</scope>
             </dependency>
```

and then run again.

## Clean the build

You can remove the files downloaded and generated during that execution with:

```sh
make clean
```

## EKS

The `eks` target works similarly but creates a new EKS cluster.
You must have `eksctl` and valid AWS credentials.

Here is how to quickly obtain AWS credentials if you have opscore
```bash
export AWS_PROFILE=cloudbees-cloud-platform-dev
opscore iam refresh --role infra-admin --account $AWS_PROFILE
```

You can check your AWS credentials are valid
```bash
aws sts get-caller-identity
```

2 availability zones will be picked up by eksctl randomly. Depending on current availability, you can encounter the following error

```
[✖]  AWS::EKS::Cluster/ControlPlane: CREATE_FAILED – "Cannot create cluster 'cbci-test-vincent-19751' because us-east-1c, the targeted availability zone, does not currently have sufficient capacity to support the cluster. Retry and choose from these availability zones: us-east-1a, us-east-1b, us-east-1d, us-east-1e, us-east-1f (Service: AmazonEKS; Status Code: 400; Error Code: UnsupportedAvailabilityZoneException; Request ID: dfc2548b-ab8c-4746-91c2-c76f9cd79111)"
```

It may need a few retries to end up on availability zones with enough capacity.

## GKE

The `gke` target works similarly but creates a new GKE cluster.
You must have `gcloud` (and `gsutil`) installed and be logged into GCP with a project defined, so that these commands work:

```bash
gcloud config get-value core/project
gcloud container clusters list
```

If they don't, then set a default project:

```bash
gcloud config set project my-project
```

Select a default region and zone, e.g.:

```bash
gcloud config set compute/region us-east1
gcloud config set compute/zone us-east1-b
```

Your `~/.docker/config.json` may also need to include, for example:

```json
"credHelpers": {
    "us-east1-docker.pkg.dev": "gcloud"
}
```

This setup can also install Velero so you can back up and restore the CloudBees CI namespaces via persistent disk snapshots.
To enable, add: `VELERO=true`

## Other Kubernetes

The `kubernetes` target installs CloudBees CI into an existing cluster.
The cluster must already have `nginx-ingress` installed,
and your `$KUBECONFIG` must point to it.
You will need to specify a domain suffix (wildcard to which a generated name will be prepended for ingress),
and the prefix of a registry to which you have push permission and from which the cluster can pull.
If on AWS, try:

```bash
export AWS_PROFILE=…
opscore iam refresh --account=$AWS_PROFILE --role=infra-admin
eval $(aws ecr get-login --no-include-email)
for r in core-{oc,mm} agent; do aws ecr describe-repositories --repository-name=cloudbees/$r || aws ecr create-repository --repository-name=cloudbees/$r; done
kubectl config use-context …
make kubernetes DOMAIN_SUFFIX=… REGISTRY=$(aws sts get-caller-identity | jq -r .Account).dkr.ecr.$(aws configure get region).amazonaws.com/cloudbees
```

On OCP 4.x, assuming the registry is configured

```bash
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
docker login -u $(oc whoami) -p $(oc whoami -t) $(oc get route default-route -n openshift-image-registry --template='{{.spec.host}}')
```

then try

```bash
NS=cbci-test-$USER-$RANDOM
kubectl create ns $NS
make kubernetes \
    NS=$NS \
    DOMAIN_SUFFIX=$(oc get -n openshift-ingress-operator ingresscontroller/default --template='{{.status.domain}}') \
    HELM_OPTS='--set OperationsCenter.Route.tls.Enable=true --api-versions route.openshift.io/v1' \
    REGISTRY_INTERNAL=image-registry.openshift-image-registry.svc:5000/$NS \
    REGISTRY_EXTERNAL=$(oc get route default-route -n openshift-image-registry --template='{{.spec.host}}')/$NS
```

Depending on the target cluster, and your local platform, you may need to first

```bash
export PLATFORM=linux/amd64
```

## Docker only

You can also run images in isolation, if you do not need a cluster; for example:

```sh
make run-oc
make run-mm
```

Mac OS X users should note that some commands like `cp` are expected to be the GNU variants.
If you have not already done so, try

```sh
brew install coreutils gnu-tar
export PATH="/usr/local/opt/coreutils/libexec/gnubin:/usr/local/opt/gnu-tar/libexec/gnubin:$PATH"
```

# “Airgapped” building

The convoluted multiphase build here is necessary to support:

* CloudBees image builds, ultimately to be published as
  [`cloudbees/cloudbees-cloud-core-oc`](https://hub.docker.com/r/cloudbees/cloudbees-cloud-core-oc),
  [`cloudbees/cloudbees-core-mm`](https://hub.docker.com/r/cloudbees/cloudbees-core-mm), and
  [`cloudbees/cloudbees-core-agent`](https://hub.docker.com/r/cloudbees/cloudbees-core-agent).
* Customers who wish to build their own images with some modifications.
  The image build need not connect to the Internet;
  it is assumed that a compatible version of RedHat Universal Base Image is available in a local registry,
  and that it is configured to permit installing packages from the standard UBI package repositories.
* The US Department of Defense, to be published [here](https://dccscr.dsop.io/groups/dsop/cloudbees/core/-/merge_requests)
  according to [these constraints](https://dccscr.dsop.io/dsop/dccscr/tree/master/contributor-onboarding).
  A hardened version of UBI with JDK packages is the assumed base image,
  and other than installing standard UBI packages,
  all files must have been downloaded from S3.

The `offline/` directory covers the first two cases.
Its folder structure consists of three top-level subdirectories, one for each image:

* `core-oc/` for Operations Center
* `core-mm/` for a managed controller
* `agent/` for Kubernetes (“inbound”) build agents

plus a `base/` subdirectory which allows the hardened UBI to be built,
a `build` script to drive image creation and (optionally) publishing,
and a `helm/` subdirectory with the chart.

Each image subdirectory consists of:

* `Dockerfile`
  * `FROM` a parameterized base image
  * various package installation commands
    (in the case of `core-oc` and `core-mm`,
    there will be some copied portions,
    but Docker layer caching should apply)
  * `COPY` + `RUN` commands to unpack bundled files
* `files.tar`, all additional files to be included in the image, relative to the filesystem root

The `dsop/` directory, if built, covers the third case.
It lacks the `base/` subdirectory or `build` script.
Each image subdirectory consists of:

* `Dockerfile` almost exactly as before but with different `BASE_*` defaults
* no `files.tar`; instead a `hardening_manifest.yaml`

Also `helm/` is moved inside `core-oc/` in this case.
