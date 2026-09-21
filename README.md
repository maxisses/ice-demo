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

The workspace comes up on the Red Hat Universal Developer Image, which carries python 3.9 and
3.11 plus `oc`, `tkn` and `git`. (No helm - the devfile commands pin `python3.11`, because the
image we ship runs 3.12 and the UDI's default `python` is 3.9.) Point out that this IDE is a
pod: `oc get pods -n <your>-devspaces`.

The workspace arms itself on start: a `postStart` event installs the `pre-push` hook, copies
the mounted deploy key into `~/.ssh` and switches the git remote to SSH. If you ever need to
redo that by hand, run command **4. Re-arm the git hook**.

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

The push starts `localnews-ci`. Switch to the OpenShift console, Pipelines, and watch the five
tasks: fetch the source, work out the short SHA, run pytest, build the image with buildah, and
push the new tag back into Git. The whole run takes three and a half minutes, most of it the
two pulls of the 650 MB base image.

### 4. GitOps

Open Argo CD. Argo polls the repo every three minutes, so either wait or hit **Refresh**.
Use **Hard Refresh** if it still shows the old revision - the repo-server caches the commit.
Then it syncs itself and rolls the new pod out. Prove it landed:

```bash
curl -s https://location-extractor-md-ice-demo-part1.apps.ocp4.stormshift.coe.muc.redhat.com/ | jq
```

If you want the map to move too, the same service answers with coordinates:

```bash
curl -s "https://location-extractor-md-ice-demo-part1.apps.ocp4.stormshift.coe.muc.redhat.com/get_loc?text=The+game+was+played+in+Berlin+and+Denver" | jq
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

## Why the geocoding is offline

The version of this service in the book asks Nominatim, the public
OpenStreetMap geocoder. That works on a laptop and falls apart on stage.
Nominatim allows one request per second per IP, every pod in this cluster
leaves through the same NAT address, and the feed scraper analyses a headline
every few seconds. We were rate limited within minutes, and every marker landed
in the Pacific fallback.

So `src/geocode.py` looks places up in a local dataset instead: `geonamescache`
ships 26,463 cities with coordinates and 252 countries, which we point at their
capitals. Names collide - there are 28 places called Berlin - so the index is
built in ascending population order and the biggest one wins. No network call,
no rate limit, and the same answer every time you run the demo.

Set `LOC_EXT_ONLINE_FALLBACK=true` if you want Nominatim consulted for the names
the dataset does not know. It is off by default.

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
3. **The Argo CD application controller was OOMKilled** in a loop. 2 GiB is not enough to hold
   the resource cache of a cluster with 141 projects, so GitOps was broken for everyone, not
   just for us. It now has 6 GiB.

OLM bundled the first two into one InstallPlan together with dns-operator 1.4.1, Service Mesh
3.4.2 and devworkspace-operator 0.43.0, so those went along for the ride.

Two things that bite on a first start and are worth knowing before you go live:

- The per-user workspace PVC is deleted with the last workspace in a namespace, and the NetApp
  storage class binds immediately rather than waiting for a consumer. So the very first start
  after a clean-up can lose a race and fail with *"0/6 nodes are available: pod has unbound
  immediate PersistentVolumeClaims"*. Starting it a second time works. `startTimeoutSeconds` is
  up from 300 to 900 to give the pull of the 1.5 GB UDI image room as well.
- Keep a stopped workspace around rather than deleting it, and the PVC stays bound.

## Secrets in the namespace

| Secret | What for |
|---|---|
| `quay-push-secret` | buildah pushes to quay.io |
| `git-push-ssh` | the pipeline writes the image tag back to this repo |
| `webhook-secret` | shared HMAC secret between the git hook and the EventListener |

And two in your own Dev Spaces namespace, which Dev Spaces mounts into every
workspace because they carry `controller.devfile.io/mount-to-devworkspace=true`:

| Secret | What for | Created by |
|---|---|---|
| `ice-demo-webhook` | `ICE_DEMO_WEBHOOK_URL` and `ICE_DEMO_WEBHOOK_SECRET` for the git hook | `hack/create-webhook-secret.sh` |
| `ice-demo-git-ssh` | the deploy key, so you can push from the browser IDE | `hack/create-git-ssh-secret.sh <keyfile>` |

Both scripts take the workspace namespace as their last argument and default to
your current project.

The SSH key is a deploy key scoped to this repository with write access. Rotate it by
generating a new pair, replacing the GitHub deploy key, and updating the secret.
