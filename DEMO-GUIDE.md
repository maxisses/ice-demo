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
oc get devworkspace -A | grep ice-demo                          # both Running
```

If a workspace is stopped, start it now. A cold start pulls a 1.5 GB image and
you do not want to narrate that.

Have four tabs open: the AI workspace, the OpenShift console on Pipelines, Argo
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

In the `ice-demo` workspace, change the greeting in
`components/location-extractor/src/server.py`, then:

```bash
git commit -am "Say hello from Berlin" && git push
```

The `pre-push` hook fires the Tekton EventListener. Say "that's three and a
half minutes of pipeline, let's not watch it" and switch tabs. You'll come back
at 1:30 and it will be done.

### 0:20 — The CVE finds you

Switch to the `ice-demo-ai` workspace:

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

Chat icon, top right of the console. OpenShift Lightspeed, wired to the same
model the dependency review used.

Ask it something you just showed:

> What does the restricted-v2 SecurityContextConstraint prevent a pod from
> doing? Three short bullets.

It answers correctly - privilege escalation, raw device access, host mounts.
That's the honest use for it: the thing that explains the platform to someone
who has to operate it at two in the morning, with Red Hat's own documentation
behind it rather than a search engine's best guess.

Be straight about the limit, because someone will ask. Lightspeed has cluster
introspection switched on and an MCP server running, but this particular model
is a 14B distill and does not reliably call those tools. Ask it to list your
pods and it hands you a `kubectl` command instead of an answer. Put a bigger
tool-calling model behind the same configuration and that changes - the
configuration is one URL and one model name, and you saw it in
`cluster/20-lightspeed-olsconfig.yaml`. Again: part three.

Keep the questions short. Long prompts eat the context window.

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
session. Ask your first question while walking over to the console.
