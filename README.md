# ice-demo — part 1: OpenShift as a container platform

This repo carries the live demo for the first part of the talk *"It is a Container Platform,
isn't it?"*. The slide before it says **Demo Time! Containers everywhere on OpenShift**, and
the speaker note asks for one thing: walk the application lifecycle. Dev Spaces, Builds,
Pipelines, CD with GitOps, Workloads, Pods, Operators, Helm.

So that's what happens here. You open a browser-based IDE, change three words in a Python
file, press push, and then watch a pipeline build a container, write the new tag back into
this repo, and let Argo CD roll it into the cluster. No local tooling, no kubectl apply by
hand. Everything you see on the screen runs on the same worker nodes.

The application is **LocalNews**, the sample app from *Kubernetes Native Development*
(Schmeling & Dargatz, Apress 2022): a scraper pulls RSS feeds, a Quarkus backend stores them
in PostGIS, a Python service pulls place names out of the headlines with spaCy, and an
Angular frontend paints them on a map. We only build one of those five components in the
pipeline — the Python one — because that keeps the loop short enough to watch on stage.

## Where everything lives

| Thing | Where |
|---|---|
| Cluster | `https://api.ocp4.stormshift.coe.muc.redhat.com:6443` |
| Namespace | `md-ice-demo-part1` |
| Dev Spaces | https://devspaces.apps.ocp4.stormshift.coe.muc.redhat.com |
| Argo CD | https://openshift-gitops-server-openshift-gitops.apps.ocp4.stormshift.coe.muc.redhat.com |
| Argo project / app | `icedemo` / `localnews` |
| Image registry | `quay.io/mdargatz/icedemo` |
| The app itself | https://news-frontend-md-ice-demo-part1.apps.ocp4.stormshift.coe.muc.redhat.com |

## What is in here

```
components/location-extractor/   the Python service we build on stage
  src/server.py                  <- the file you edit during the demo
  test/                          unit tests, they run in the pipeline
  Containerfile                  what the pipeline builds (seconds)
  Containerfile.base             spaCy + language model (minutes, built once)
devfile.yaml                     the Dev Spaces workspace
hack/                            the git hook that fires the pipeline
tekton/                          tasks, both pipelines, the webhook receiver
gitops/helm/                     the Helm chart Argo CD deploys
gitops/argocd/                   AppProject and Application
```

## Running the demo

### 0. Before you go on stage

Check that the app is green and the workspace starts. Takes two minutes:

```bash
oc get pods -n md-ice-demo-part1
oc get application localnews -n openshift-gitops
```

### 1. Dev Spaces

Open the workspace from the Dev Spaces dashboard, or go straight to the factory URL:

```
https://devspaces.apps.ocp4.stormshift.coe.muc.redhat.com/#https://github.com/maxisses/ice-demo
```

The workspace comes up on the Red Hat Universal Developer Image, which already carries
python, `oc`, `tkn` and `helm`. Point out that this IDE is a pod: `oc get pods -n <your>-devspaces`.

When it has started, run command **4. Arm the git hook** once. It reads the webhook route and
the shared secret out of the cluster and installs a `pre-push` hook.

### 2. Change something

Open `components/location-extractor/src/server.py`. Near the top there is one line marked as
the thing we change live:

```python
GREETING = "Hello from the ICE demo - built on OpenShift"
```

Change it. Then run command **2. Run the unit tests** so the audience sees the tests pass
before anything is built, and commit:

```bash
git commit -am "Say hello to Berlin"
git push
```

### 3. Pipelines

The push starts `localnews-ci`. Switch to the OpenShift console, Pipelines, and watch the four
tasks: fetch the source, run pytest, build the image with buildah, push the new tag back into
Git. It takes about 90 seconds.

### 4. GitOps

Open Argo CD. The `localnews` application goes out of sync within three minutes (or hit
**Refresh** if you don't want to wait), then syncs itself and rolls the new pod out. Prove it
landed:

```bash
curl -s https://location-extractor-md-ice-demo-part1.apps.ocp4.stormshift.coe.muc.redhat.com/ | jq
```

The greeting you typed in the browser IDE two minutes ago comes back from a container that was
built, tested and deployed without anyone touching a cluster.

### 5. The rest of the platform

From here the console does the talking: Workloads and Pods for the five running components,
Helm for the release Argo CD created, and Operators → OperatorHub for the Local News operator
sitting in the catalog.

Afterwards, pull the commit the pipeline made, or your next push will be rejected:

```bash
git pull --rebase origin main
```

## How the trigger works

GitHub cannot reach this cluster — stormshift is a lab behind Red Hat's network, and no
webhook from github.com will ever arrive. So the push notification comes from the workspace
instead. `hack/pre-push` builds the same JSON body GitHub sends for a push event, signs it with
the same HMAC-SHA256 secret, and posts it to the EventListener route. The EventListener runs
the stock `github` interceptor and checks that signature, so it genuinely cannot tell the
difference.

If this cluster ever gets a public ingress, delete the hook, point a real GitHub webhook at
`https://ice-demo-webhook-md-ice-demo-part1.apps.ocp4.stormshift.coe.muc.redhat.com` with the
secret from `webhook-secret`, and nothing in `tekton/` has to change.

## Why there are two container builds

spaCy plus the English language model is 34 MB of download and about four minutes of `pip
install`. Doing that on every commit would make the demo unwatchable. So dependencies live in
`Containerfile.base`, which we build once and push as `quay.io/mdargatz/icedemo:base`. The
per-commit `Containerfile` starts from that image and copies four Python files on top, which
is why step 3 finishes in about 90 seconds.

Rebuild the base image whenever `requirements.txt` changes:

```bash
tkn pipeline start build-base-image -n md-ice-demo-part1 \
  --workspace name=shared-workspace,claimName=ice-demo-workspace \
  --workspace name=dockerconfig,secret=quay-push-secret \
  --serviceaccount pipeline --showlog
```

## Images

Everything we build ourselves sits on Red Hat base images: `ubi9/python-312` for the
location-extractor, and the Dev Spaces Universal Developer Image for the workspace. The three
components we don't build in this demo still run the images from the book
(`quay.io/k8snativedev/*`).

The one exception is PostGIS. No Red Hat image ships the PostGIS extension, and the Quarkus
backend stores coordinates as geometry, so `postgis/postgis:15-3.4` stays. If you want that
gone too, Crunchy Data's `crunchy-postgres-gis` is a Red Hat certified partner image and
would need a `registry.connect.redhat.com` pull secret.

## Cluster setup, for the record

Three things had to be fixed on ocp4 before this worked:

1. **The Dev Spaces operator was gone.** No CSV, no operator pod. Without it nothing reconciles
   a `DevWorkspaceRouting` with `routingClass: che`, so every workspace hung at *"Preparing
   networking"* until the 300 second timeout killed it. Reinstalling the subscription brought
   Dev Spaces back and moved it from 3.21.0 to 3.30.1.
2. **The Pipelines operator pod was stuck** in `CreateContainerConfigError`, missing a configmap
   called `tekton-config-defaults` from an interrupted upgrade. Tekton itself kept running, but
   the operator never created the `pipeline` service account in new namespaces. The 1.22.5
   upgrade fixed it.
3. OLM bundled both into one InstallPlan together with dns-operator 1.4.1, Service Mesh 3.4.2
   and devworkspace-operator 0.43.0, so those went along for the ride.

## Secrets in the namespace

| Secret | What for |
|---|---|
| `quay-push-secret` | buildah pushes to quay.io |
| `git-push-ssh` | the pipeline writes the image tag back to this repo |
| `webhook-secret` | shared HMAC secret between the git hook and the EventListener |

The SSH key is a deploy key scoped to this repository with write access. Rotate it by
generating a new pair, replacing the GitHub deploy key, and updating the secret.
