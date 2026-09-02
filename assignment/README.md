<!--
Original technical-test assignment, as received (content unmodified).
This is an unofficial English translation of the Spanish original; the wording
in the original private repo (JuanCruz-Ojeda/entrega-prueba-tecnica) is authoritative.
The solution is at the root of the repository. See the "Project origin" section
of the main README.
-->

# Technical test — DevOps / Cloud Engineer

## Context

We are handing you a mini-service (`app/`) with a `docker-compose.yml` that
**does not come up correctly as-is**. The idea is not for you to write an app
from scratch, but to work the way you would day to day: you receive something
with problems and you have to leave it running, done well, and documented.

## What we ask of you

1. **Make everything come up** with a single command (`docker compose up --build`
   or the one you define — see the "Deliverable" section). Explore why it does
   not work right now.
2. **Review the `Dockerfile`** in `app/` and improve whatever you consider does
   not follow best practices for a production environment.
3. **Complete the CI pipeline** in `.github/workflows/ci.yml` (it has TODOs).
   You do not have to push to a real registry if you do not have one handy —
   leave it documented.
4. **Infrastructure**: the detail is in `infra/README.md`. In short, tell us
   (in code or in a runbook) how you would deploy this on AWS.
5. **A `README.md`** at the root (you may replace this file or add a new one)
   that explains: how to bring everything up with a single command, what you
   changed and why, and what you would do differently with more time.

## What is left to your judgment (on purpose)

We do not tell you which IaC tool to use, nor which logging/monitoring to add,
nor whether horizontal scaling is needed. Make those decisions yourself and
explain the why.

## Optional tracks

Beyond the above, `OPTIONAL_TRACKS.md` has two extra challenges
(Kubernetes/Helm and DevSecOps/scanning) — **completely optional**. Do the ones
that match your real experience; we will not penalize you for skipping them if
the rest is solid.

## Time

Plan for no more than 2-3 hours (up to 4 if you take on an optional track). It
does not need to be "perfect" — we would rather see clear priorities (what you
solved first and why) than an attempt to cover everything halfway.

## Deliverable

A repository (link to GitHub/GitLab, public or with access for us) or a `.zip`
with the whole project, including your final `README.md`. Important: **whoever
reviews it has to be able to bring up your solution with a single command**, so
make sure that is very clear and tested (for example from a clean folder,
cloning again).

## Defense

You will have ~20-30 minutes to show us your solution running and explain your
decisions. You may use any tool (documentation, AI, whatever you normally use in
your work) — what matters to us is that you can explain and, if needed, modify
live any part of what you delivered.
