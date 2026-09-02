<!--
Original content of infra/README.md as received (content unmodified).
This is an unofficial English translation of the Spanish original.
The solution is in infra/README.md at the root of the repository.
-->

# Infrastructure

This folder is empty on purpose.

Your task: describe and/or code how you would deploy this app on AWS in a
minimal but reasonable way for a production environment (it does not need to be
highly available or multi-region).

We do not tell you which tool to use. Pick the one you know best and justify the
choice in your main README:

- Terraform / CloudFormation / Pulumi with real code, or
- A detailed runbook (step by step, with AWS CLI commands) if you do not have
  experience with an IaC tool — we care more about seeing that you understand
  which resources are needed and why than about the exact syntax of a
  particular tool.

At a minimum we expect you to think about: how the container runs (EC2,
ECS/Fargate, or whatever you prefer), how traffic comes in (load balancer), how
environment variables / secrets are handled, and what would happen if the
container went down.
