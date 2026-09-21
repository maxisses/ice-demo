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

There is a shorter, security-focused version of this demo in
[DEMO-GUIDE.md](DEMO-GUIDE.md) - five minutes, built around supply chain,
drift and Lightspeed.

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
devfile-ai.yaml                  the AI workspace (scanner + coding agent)
ai/                              dependency review script and agent config
cluster/                         namespace, operator patches, Lightspeed, workspaces
hack/bootstrap.sh                rebuilds all of it on a fresh cluster
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

## The second workspace: a model that reads your dependencies

`devfile-ai.yaml` starts a second workspace, `ice-demo-ai`, on the same repo.
It is the bridge into part three of the talk: the same application lifecycle,
but with a model helping, and the model runs on OpenShift AI rather than
somewhere in California.

Factory URL:

```
https://devspaces.apps.ocp4.stormshift.coe.muc.redhat.com/#https://github.com/maxisses/ice-demo?df=devfile-ai.yaml
```

Four commands, in order:

1. **Install the scanner and the coding agent** - `pip-audit` and `opencode`.
2. **Scan the dependencies.** This is not a canned result. As of today
   `pip-audit` finds two real advisories against the Flask version we pin,
   PYSEC-2026-1377 and PYSEC-2026-2151.
3. **Ask the model what to do about them.** `ai/dependency-review.py` hands
   the findings and the requirements file to `deepseek-r1-distill-qwen-14b`
   and prints two things: the answer, and the model's own reasoning on the way
   there. Worth showing - it works out that 3.1.3 covers both advisories so
   you only need one bump, and it says so.
4. **Open the coding agent.** `opencode` in the terminal, wired to the same
   endpoint, with the repo as its working directory. Ask it to explain
   `src/geocode.py` and it reads the file first.

Two details worth knowing. The model is DeepSeek-R1, which thinks out loud: the
answer arrives in `content` and the thinking in `reasoning_content`, and if you
give it too few tokens you get the thinking and an empty answer. And opencode
asks for 32,000 output tokens by default while this model serves 16,384 in
total, so `ai/agent.sh` pins the limits - without that every request is
rejected before it reaches a GPU.

The editor also picks up `.vscode/extensions.json`, which asks for Red Hat
Dependency Analytics. That flags vulnerable dependencies inline while you type,
so you can show the same finding twice: once as a squiggle in the editor, once
as a scan in the terminal.

Credentials come from an `ice-demo-ai` secret in your Dev Spaces namespace,
mounted as `OPENAI_BASE_URL`, `OPENAI_API_KEY` and `AI_MODEL`. Nothing is baked
into the devfile.

## The feeds, and why /news looks empty

`/news` takes a bounding box and returns nothing without one. That is not a
bug - the frontend passes whatever the map is currently showing. To check the
data from a terminal, ask for the whole world:

```bash
curl -s "https://news-backend-md-ice-demo-part1.apps.ocp4.stormshift.coe.muc.redhat.com/news?sw.lat=-85&sw.lng=-180&ne.lat=85&ne.lng=180" | jq length
```

The feed list in `values.yaml` is not the one from the book. Three of those
feeds are dead or moved: the BBC one only answers over https now, CNBC's is
gone, and the NYT url has a second `https://` nested inside its path. One more
had to go for a subtler reason - Times of India article links run to 292
characters, and the backend stores `link` in a `varchar(256)`, so every insert
failed with *"value too long for type character varying(256)"* and the map
stayed empty. BBC, Al Jazeera, the Guardian, DW and France24 all fit.

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

## Rebuilding this from scratch

Everything the cluster needs is in `cluster/` and `hack/`, except the four
secrets, which are yours to supply:

```bash
export QUAY_USER='mdargatz+admin' QUAY_TOKEN='...'
export GIT_DEPLOY_KEY=~/path/to/ice-demo-deploy-key
export MAAS_BASE_URL='https://maas-rhdp.apps.maas.redhatworkshops.io/v1'
export MAAS_API_KEY='...'
./hack/bootstrap.sh
```

It creates the namespace, the secrets, the Tekton resources, the Argo CD
project and application, the editor template, the two workspaces and their
mounted secrets. It does not install operators, and it does not build the base
image - it prints the `tkn` command for that at the end, because the first
build has to finish before the first CI run can start.

The three files ending in `.patch.yaml` are not applied by the bootstrap. They
change resources that belong to the cluster rather than to this demo - the
CheCluster, the ArgoCD CR, and the localnews operator's Subscription - so they
are there to be read and applied deliberately:

```bash
oc patch argocd openshift-gitops -n openshift-gitops \
  --type=merge --patch-file cluster/11-argocd-controller-resources.patch.yaml
```

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


## When something goes wrong on stage

**The workspace fails with "0/6 nodes are available: pod has unbound immediate
PersistentVolumeClaims".** The per-user PVC is still being provisioned. Start
the workspace again; the second attempt works.

**The second workspace will not schedule.** Both workspaces share one per-user
PVC and the storage class is ReadWriteOnce, so they have to land on the same
node. They did here, but if one refuses to start, stop the other one first.

**A workspace fails with "plugin for component editor not found".** The two
workspaces in this namespace were created with `oc`, so they point at a
`DevWorkspaceTemplate` called `che-code` that has to exist alongside them.
Workspaces you open through the Dev Spaces dashboard resolve their own editor
and do not need it. To recreate it:

```bash
oc get cm editors-definitions -n openshift-devspaces \
  -o jsonpath='{.data.che-code\.yaml}' > /tmp/che-code.yaml
```

then wrap its `components`, `commands` and `events` into a
`DevWorkspaceTemplate` named `che-code` in your Dev Spaces namespace.

**The pipeline does not start after a push.** The hook only fires on `main`,
and it needs `ICE_DEMO_WEBHOOK_URL` and `ICE_DEMO_WEBHOOK_SECRET` in the
workspace. Run command **4. Re-arm the git hook** and read what it prints. You
can always start a run by hand from the console or with `tkn`.

**The push is rejected as non-fast-forward.** The pipeline pushed its tag
commit while you were editing. Run command **5. Pull the tag commit** and push
again.

**Argo CD still shows the old revision.** Its repo-server caches the commit.
Use **Hard Refresh**, not plain Refresh.

**The map is empty.** Check `oc logs deploy/news-backend -n md-ice-demo-part1`
for *"value too long for type character varying(256)"* - a feed has started
serving links longer than 256 characters and needs to come out of
`values.yaml`. The database is ephemeral, so restarting `postgis` throws the
articles away and the scraper refills within a minute or two.
