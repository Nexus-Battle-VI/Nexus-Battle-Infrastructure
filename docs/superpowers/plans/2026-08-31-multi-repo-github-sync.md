# Multi-Repository GitHub Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Orchestrate the five repository-specific plans so all unique `develop` work reaches `main`, required artifacts publish, and every `develop` ends at the exact final `main` SHA.

**Architecture:** Integration PRs are prepared and validated before any branch rewrite. Repository mirrors run only after their own integration and publication gates pass, and each repository is independently recoverable through an archive branch.

**Tech Stack:** Git, GitHub CLI, GitHub Actions, Node.js 24.14.0, npm, Docker, PostgreSQL/Testcontainers, PowerShell

---

### Task 0: Integrate the audited design and plans into Infrastructure

**Files:**
- Create: `docs/superpowers/specs/2026-08-31-multi-repo-main-develop-sync-design.md`
- Create: `docs/superpowers/plans/2026-08-31-infrastructure-main-develop-sync.md`
- Create: `docs/superpowers/plans/2026-08-31-notifications-main-develop-sync.md`
- Create: `docs/superpowers/plans/2026-08-31-web-main-develop-sync.md`
- Create: `docs/superpowers/plans/2026-08-31-commerce-main-develop-sync.md`
- Create: `docs/superpowers/plans/2026-08-31-catalog-main-develop-sync.md`
- Create: `docs/superpowers/plans/2026-08-31-multi-repo-github-sync.md`

- [ ] **Step 1: Push the documentation branch and create its PR**

```powershell
git push -u origin docs/multi-repo-main-develop-sync
gh pr create -R Nexus-Battle-VI/Nexus-Battle-Infrastructure --base main --head docs/multi-repo-main-develop-sync --title "docs(infrastructure): documentar sincronización multirrepositorio" --body "## Resumen`n- Documenta la integración segura de develop hacia main en cinco repositorios.`n- Separa planes ejecutables y restauración de rulesets.`n- Mantiene Terraform, SSM y producción fuera de esta fase.`n`n## Validación`n- auto-revisión de cobertura, ambigüedades y placeholders`n- comandos con leases, respaldos y comprobaciones finales"
```

Expected: remote branch and PR URL targeting Infrastructure `main`.

- [ ] **Step 2: Wait for CI and required review, then merge**

```powershell
$docsPr = gh pr list -R Nexus-Battle-VI/Nexus-Battle-Infrastructure --base main --head docs/multi-repo-main-develop-sync --state open --json number --jq '.[0].number'
gh pr checks -R Nexus-Battle-VI/Nexus-Battle-Infrastructure $docsPr --watch
gh pr view -R Nexus-Battle-VI/Nexus-Battle-Infrastructure $docsPr --json reviewDecision,mergeStateStatus,statusCheckRollup
```

Expected before merge: successful checks and `reviewDecision=APPROVED`. After approval:

```powershell
gh pr merge -R Nexus-Battle-VI/Nexus-Battle-Infrastructure $docsPr --squash --delete-branch=false
git fetch origin --prune
```

Expected: documentation present in the protected Infrastructure `main`.

### Task 1: Prepare and validate all integration PRs

**Files:**
- Execute: `docs/superpowers/plans/2026-08-31-notifications-main-develop-sync.md`
- Execute: `docs/superpowers/plans/2026-08-31-commerce-main-develop-sync.md`
- Execute: `docs/superpowers/plans/2026-08-31-web-main-develop-sync.md`

- [ ] **Step 1: Complete Notifications Tasks 1 and 2 through the review gate**

Expected: local validation passes, the PR exists, and required CI is green. Do not merge without the required human approval.

- [ ] **Step 2: Complete Commerce Tasks 1 and 2 through the review gate**

Expected: application and disposable PostgreSQL tests pass, the PR exists, and required CI is green. Do not merge without approval.

- [ ] **Step 3: Complete Web Tasks 1 through 3 through the review gate**

Expected: exact tree checks pass, HU-05.4 applies cleanly over HU-04, local gates pass, and the PR CI is green. Do not merge without approval.

### Task 2: Merge and publish the three changed services

**Files:**
- Execute: Notifications Task 2 Step 3
- Execute: Commerce Task 2 Step 3
- Execute: Web Task 3 Step 3

- [ ] **Step 1: Merge Notifications and verify its GHCR job**

Expected: protected squash merge and successful `Publicar imagen en GHCR` job for the new main SHA.

- [ ] **Step 2: Merge Commerce and verify its GHCR job**

Expected: protected squash merge and successful publication job.

- [ ] **Step 3: Merge Web and verify its GHCR job**

Expected: protected squash merge and successful publication job.

### Task 3: Mirror all five `develop` branches

**Files:**
- Execute: `docs/superpowers/plans/2026-08-31-infrastructure-main-develop-sync.md`
- Execute: Notifications Task 3
- Execute: Web Task 4
- Execute: Commerce Task 3
- Execute: `docs/superpowers/plans/2026-08-31-catalog-main-develop-sync.md`

- [ ] **Step 1: Mirror Infrastructure and Catalog**

Expected: exact SHA/tree equality, archives verified, rulesets active.

- [ ] **Step 2: Mirror Notifications, Commerce and Web**

Expected: exact SHA/tree equality after their integration PRs, archives verified, rulesets active.

- [ ] **Step 3: Run the final cross-repository audit**

```powershell
$repos = @('Nexus-Battle-Infrastructure','Nexus-Battle-Notifications','Nexus-Battle-Web','Nexus-Battle-Commerce','Nexus-Battle-Catalog')
foreach ($name in $repos) {
  $path = "D:\Desarrollo\Proyectos\UPB\Nexus-Battle\$name"
  git -C $path fetch origin --prune
  $main = git -C $path rev-parse origin/main
  $develop = git -C $path rev-parse origin/develop
  $mainTree = git -C $path rev-parse 'origin/main^{tree}'
  $developTree = git -C $path rev-parse 'origin/develop^{tree}'
  if ($main -ne $develop -or $mainTree -ne $developTree) { throw "$name is not mirrored" }
  "$name $main OK"
}
```

Expected: five `OK` lines and exit 0. No Terraform, SSM or production database command has run.
