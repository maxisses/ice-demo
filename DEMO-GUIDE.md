# Five minutes on security

A short version of the part 1 demo for the times you don't have fifteen
minutes. Same cluster, same app, different argument: not "look how smooth the
lifecycle is" but "look how little of this you had to build yourself".

The line to land: every control in these five minutes is the platform's, not
the application's. Nobody wrote a policy engine, stood up a build server, or
bolted a scanner onto a pipeline. It came with OpenShift.

## Before you walk up

Two checks, thirty seconds:

```bash
oc get applications.argoproj.io localnews -n openshift-gitops   # Synced / Healthy
oc get devworkspace -A | grep ice-demo                          # Running
```

If the workspace is stopped, start it now. A cold start pulls a 1.5 GB image
and you do not want to narrate that. It is one workspace and it does
everything - editing, tests, the scan and the coding agent.

Have four tabs open: the workspace, the OpenShift console on Pipelines, Argo
CD, and a terminal.

## The five minutes

| | Beat | Roughly |
|---|---|---|
| 0:00 | Push a change, let the pipeline run in the background | 20s |
| 0:20 | A model on this cluster reads your dependencies | 70s |
| 1:30 | The pipeline is a gate, and it signs what it builds | 60s |
| 2:30 | Git is the only door into the cluster | 50s |
| 3:20 | Ask the cluster with Lightspeed | 80s |
| 4:40 | It was containers all along | 20s |

### 0:00 — Start the clock

In the workspace, change the greeting in
`components/location-extractor/src/server.py`, then:

```bash
git commit -am "Say hello from Berlin" && git push
```

The `pre-push` hook fires the Tekton EventListener. Say "that's three and a
half minutes of pipeline, let's not watch it" and switch tabs. You'll come back
at 1:30 and it will be done.

### 0:20 — The CVE finds you

Back in the workspace terminal:

```bash
python3.11 ai/dependency-review.py ai/demo-requirements.txt
```

`pip-audit` queries the PyPI advisory database and comes back with real
advisories against urllib3 2.0.4 and Jinja2 3.1.2. Then the findings go to a
model and it answers: which pins to move, to which versions, and whether the
bumps will break a Flask 3 app.

Two things worth saying out loud while it thinks.

The model is `deepseek-r1-distill-qwen-14b`, served through OpenShift AI on
this cluster. The scan ran here, the reasoning ran here, and your dependency
list never left the building. That is the whole argument for running inference
where your data already is.

And it's a 14B model with a 16,384 token context, so the script sends it the
twelve worst findings instead of all thirty. Point at that limitation on
purpose. It's the cleanest bridge into part three: same platform, bigger model,
better answer.

Then scroll back up. The script prints the model's own reasoning before its
answer, and the reasoning is the interesting part - it works out that one bump
to urllib3 2.7.0 covers five separate advisories.

### 1:30 — The pipeline is a gate

Console, Pipelines, the run that started at 0:00. It's green by now.

Point at the task order first. `unit-test` runs before `build-image`, and
`build-image` only starts because the tests passed. Tests that merely report
are a dashboard. Tests that block the build are a control.

Then two commands that land harder than the graph does:

```bash
TR=$(oc get taskrun -n md-ice-demo-part1 -l tekton.dev/pipelineTask=build-image \
  --sort-by=.metadata.creationTimestamp --no-headers | tail -1 | awk '{print $1}')

oc get pod ${TR}-pod -n md-ice-demo-part1 \
  -o jsonpath='{.metadata.annotations.openshift\.io/scc}{"\n"}'
# pipelines-scc

oc get taskrun $TR -n md-ice-demo-part1 \
  -o jsonpath='{.metadata.annotations.chains\.tekton\.dev/signed}{"\n"}'
# true
```

The first says the container image was built by buildah in an ordinary pod
under a restricted SCC. No privileged container, no Docker socket mounted from
the host, no long-lived build server sitting in a corner accumulating secrets.

The second is Tekton Chains. It watched the TaskRun finish, generated an
in-toto attestation of what was built from which commit, signed it, and pushed
it into the registry beside the image. Nobody configured that. It's on by
default in OpenShift Pipelines.

### 2:30 — Git is the only door

Argo CD has picked the new tag up by now. Then break it on purpose:

```bash
oc scale deploy/location-extractor -n md-ice-demo-part1 --replicas=3
watch oc get deploy location-extractor -n md-ice-demo-part1
```

Roughly twenty seconds later it's back to one replica. Nobody undid it - Argo
CD compares the cluster to the repository and the repository wins. You just
demonstrated that a cluster-admin with a shell cannot make a lasting change to
this application. The only way in is a commit.

If you have ten seconds spare, one more:

```bash
oc get pod -n md-ice-demo-part1 -l app=location-extractor \
  -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc} uid={.items[0].spec.containers[0].securityContext.runAsUser} caps={.items[0].spec.containers[0].securityContext.capabilities}{"\n"}'
# restricted-v2 uid=1001300000 caps={"drop":["ALL"]}
```

Our Containerfile asks to run as user 1001. OpenShift ignored that and handed
the container an arbitrary UID from the namespace's range, dropped every Linux
capability, and refused it the right to escalate. We didn't ask for any of it
and we can't switch it off from inside the image.

### 3:20 — Ask the cluster

Chat icon, top right of the console. OpenShift Lightspeed, with
`deepseek-v4-pro` behind it through OpenRouter.

Ask it about the thing you just broke:

> Check the Argo CD Application named localnews in namespace
> openshift-gitops. Does it have self-healing enabled, and what would that do
> if someone scaled a deployment by hand?

It does not answer from documentation. It calls `resources_get` against the
OpenShift MCP server, reads the actual Application, finds
`syncPolicy.automated.selfHeal: true`, and then explains what you watched
happen ninety seconds ago. Three tested questions, in rising order of how much
they impress:

| Ask | What it does |
|---|---|
| What does the restricted-v2 SCC prevent a pod from doing? | Answers from Red Hat's own docs, no cluster access needed |
| What image tag is the location-extractor deployment in md-ice-demo-part1 running right now? | One tool call, reads the live Deployment, gives you the tag |
| Check the Argo CD Application localnews - is self-healing on, and what would it do if I scaled a deployment by hand? | Reads the Application, connects it to the drift you just caused |

Now the part worth saying out loud. This is the same Lightspeed that was
installed an hour ago answering "run `oc get pods` to find out" when you asked
it what was running. Nothing about the assistant changed. We pointed it at a
model that calls tools, and it went from a documentation search to something
that reads your cluster. That is one URL and one model name in
`cluster/20-lightspeed-olsconfig.yaml`, and both providers are still in there
side by side.

If you want the strongest version of the line: the platform decides what the
assistant can reach, and you decide how clever it is. Those are separate knobs,
and neither one is your application's problem.

Keep the questions specific. Name the resource and the namespace. Vague
questions send the model round the tool loop five times and it can come back
empty.

### 4:40 — It was containers all along

Console, Workloads, Pods, across the namespaces you touched. The IDE you typed
in. The pod that ran the tests. The pod that built the image. The scanner. The
app. Lightspeed itself.

Back to the arena: whatever is on top tonight, the ice is underneath.

## If you are running long

Cut in this order. The Chains signature goes first - it's the most interesting
but the least visual. Then the SCC command in beat 2:30, since the self-heal
already made the point. Never cut the self-heal or Lightspeed; they're the two
moments people repeat afterwards.

## If something misbehaves

**Argo still shows the old revision.** Hard Refresh, not Refresh. The
repo-server caches the commit for three minutes.

**The push didn't start a pipeline.** The hook only fires on `main` and needs
the mounted webhook secret. Run workspace command 4, or start the run from the
console - nobody in the audience knows it was supposed to be automatic.

**The dependency review times out.** The MaaS gateway is shared. Run
`pip-audit` on its own and read the findings yourself; the point survives
without the model.

**Lightspeed answers slowly.** It always does on the first question of a
session, and a question that needs several tool calls takes half a minute. Ask
your first one while walking over to the console.

**Lightspeed comes back with an empty answer.** It ran out of tool rounds -
five is the limit. Ask again, naming the resource and the namespace.

**Lightspeed says it cannot reach the model.** The OpenRouter credit is gone,
or the key expired. Switch the two fields at the bottom of
`cluster/20-lightspeed-olsconfig.yaml` to the `maas` provider, apply, and wait
about a minute. You lose the cluster lookups and keep the explanations, which
is enough to get through the demo.
