# Infrastructure Main/Develop Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Infrastructure `develop` point to the exact validated SHA of `main` without losing the prior `develop` reference.

**Architecture:** `develop` is an ancestor of `main` and has no unique content. Validate the protected `main`, archive the old `develop`, suspend only the `develop` ruleset inside a guarded block, update the reference with an explicit lease, and restore the ruleset.

**Tech Stack:** Git, GitHub CLI, GitHub Actions, PowerShell

---

### Task 1: Revalidate the protected branches

**Files:**
- Reference: `docs/superpowers/specs/2026-08-31-multi-repo-main-develop-sync-design.md`
- Modify: none

- [ ] **Step 1: Refresh and assert the audited relationship**

Run from `D:\Desarrollo\Proyectos\UPB\Nexus-Battle\Nexus-Battle-Infrastructure`:

```powershell
git fetch origin --prune
$mainSha = git rev-parse origin/main
$developSha = git rev-parse origin/develop
$mergeBase = git merge-base origin/main origin/develop
if ($developSha -ne '61a0e315265c423848b44b4d45c0184b7b5bd96c') { throw 'develop changed; re-audit required' }
if ($mergeBase -ne $developSha) { throw 'develop is no longer an ancestor of main' }
```

Expected: exit 0. The current `main` SHA may advance only through the documentation PR created by this operation; `develop` must remain at the audited SHA until synchronization.

- [ ] **Step 2: Verify the latest `main` CI**

```powershell
$mainSha = git rev-parse origin/main
$run = gh run list -R Nexus-Battle-VI/Nexus-Battle-Infrastructure --commit $mainSha --workflow CI --limit 1 --json databaseId,status,conclusion | ConvertFrom-Json
if ($run.Count -ne 1 -or $run[0].status -ne 'completed' -or $run[0].conclusion -ne 'success') { throw 'main CI is not successful' }
```

Expected: exit 0 with one completed successful CI run.

### Task 2: Archive and mirror `develop`

**Files:**
- Modify: none

- [ ] **Step 1: Execute the guarded reference update**

```powershell
$repo = 'Nexus-Battle-VI/Nexus-Battle-Infrastructure'
$rulesetId = 21879173
$archive = 'archive/develop-before-sync-2026-08-31'
$mainSha = git rev-parse origin/main
$developSha = git rev-parse origin/develop
if (git ls-remote origin "refs/heads/$archive") { throw 'archive branch already exists' }
git push origin "${developSha}:refs/heads/${archive}"
$archiveSha = (git ls-remote origin "refs/heads/$archive") -split '\s+' | Select-Object -First 1
if ($archiveSha -ne $developSha) { throw 'archive verification failed' }
$ruleset = (gh api "repos/$repo/rulesets/$rulesetId") | ConvertFrom-Json
if ($ruleset.enforcement -ne 'active') { throw 'develop ruleset is not active before the operation' }
$disabled = [ordered]@{ name=$ruleset.name; target=$ruleset.target; enforcement='disabled'; bypass_actors=@($ruleset.bypass_actors); conditions=$ruleset.conditions; rules=@($ruleset.rules) } | ConvertTo-Json -Depth 20 -Compress
$active = [ordered]@{ name=$ruleset.name; target=$ruleset.target; enforcement='active'; bypass_actors=@($ruleset.bypass_actors); conditions=$ruleset.conditions; rules=@($ruleset.rules) } | ConvertTo-Json -Depth 20 -Compress
try {
  $disabled | gh api --method PUT "repos/$repo/rulesets/$rulesetId" --input - | Out-Null
  git push --force-with-lease="refs/heads/develop:$developSha" origin "${mainSha}:refs/heads/develop"
} finally {
  $active | gh api --method PUT "repos/$repo/rulesets/$rulesetId" --input - | Out-Null
}
```

Expected: archive created, `develop` updated, and the ruleset restored even if the push fails.

- [ ] **Step 2: Verify exact equality and protection**

```powershell
git fetch origin --prune
$mainSha = git rev-parse origin/main
$developSha = git rev-parse origin/develop
$mainTree = git rev-parse 'origin/main^{tree}'
$developTree = git rev-parse 'origin/develop^{tree}'
$enforcement = gh api "repos/Nexus-Battle-VI/Nexus-Battle-Infrastructure/rulesets/21879173" --jq '.enforcement'
if ($mainSha -ne $developSha -or $mainTree -ne $developTree -or $enforcement -ne 'active') { throw 'final verification failed' }
```

Expected: exit 0; SHA and tree are identical and the ruleset is active.
