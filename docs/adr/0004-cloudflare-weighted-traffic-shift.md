# 4. Shift traffic with Cloudflare load balancer weights and session affinity

Status: accepted

## Context

Traffic has to move from EKS to the data centre gradually, with an immediate
way back. DNS-weighted records are cached by resolvers for longer than their
TTL, so rollback is not immediate. Cloudflare is already the edge for both sites.

## Decision

A Cloudflare load balancer with one pool per site and `random` steering with
pool weights (`terraform/traffic-shift`). Each step is a one-line change to
`dc1_traffic_percent` in a pull request. Cookie session affinity keeps a user
on one site for 30 minutes, and health checks on `/ready` move a failed pool's
share to the other site.

Each cluster's external-dns only manages its own origin subdomain
(`*.dc1.example.com`); the public hostnames belong to Terraform. Two
external-dns instances writing the same records would fight.

## Consequences

- Rollback takes effect for new sessions within seconds of the apply.
- Session affinity hides replication lag from users during the dual-site
  phase: a user who writes on one site reads on the same site.
- The load balancer is a paid Cloudflare feature, budgeted in the TCO model.

## Alternatives considered

- **Route 53 weighted records.** DNS caching makes steps and rollbacks slow and
  uneven.
- **Proxying from the ALB to the data centre.** Adds a hop through AWS for
  on-prem traffic, and keeps paying for data transfer out.
