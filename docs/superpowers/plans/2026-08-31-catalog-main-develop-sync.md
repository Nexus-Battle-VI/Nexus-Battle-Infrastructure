# Catalog Main/Develop Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Catalog `develop` point to the exact validated `main` SHA that already contains HU-33.2 through HU-33.4.

**Architecture:** No code integration is required because `develop` is an ancestor of `main`. Confirm the main CI/publication evidence, preserve the old `develop`, update it during a guarded ruleset suspension, and verify exact equality.

**Tech Stack:** Git, GitHub CLI, GitHub Actions, PowerShell

---

### Task 1: Verify the existing `main`

**Files:**
- Modify: none

- [ ] **Step 1: Revalidate ancestry and CI**

```powershell
git fetch origin --prune
$mainSha = git rev-parse origin/main
$developSha = git rev-parse origin/develop
if ($mainSha -ne 'be0d70f04c604adf304b6dd6f07fd1898b972332') { throw 'main changed; re-audit required' }
if ($developSha -ne 'c20c2ef214c6aa775df07eccd858b88b2cdd6e54') { throw 'develop changed; re-audit required' }
if ((git merge-base origin/main origin/develop) -ne $developSha) { throw 'develop is not an ancestor of main' }
$run = gh run list -R Nexus-Battle-VI/Nexus-Battle-Catalog --commit $mainSha --workflow CI --limit 1 --json status,conclusion | ConvertFrom-Json
if ($run.Count -ne 1 -or $run[0].status -ne 'completed' -or $run[0].conclusion -ne 'success') { throw 'main CI is not successful' }
```

Expected: exit 0; HU-33 main CI is successful.

### Task 2: Archive and mirror `develop`

**Files:**
- Modify: none

- [ ] **Step 1: Run the guarded mirror operation**

```powershell
$repo = 'Nexus-Battle-VI/Nexus-Battle-Catalog'
$rulesetId = 21879157
$archive = 'archive/develop-before-sync-2026-08-31'
$mainSha = git rev-parse origin/main
$developSha = git rev-parse origin/develop
if (git ls-remote origin "refs/heads/$archive") { throw 'archive branch already exists' }
git push origin "${developSha}:refs/heads/${archive}"
$archiveSha = (git ls-remote origin "refs/heads/$archive") -split '\s+' | Select-Object -First 1
if ($archiveSha -ne $developSha) { throw 'archive verification failed' }
$ruleset = (gh api "repos/$repo/rulesets/$rulesetId") | ConvertFrom-Json
if ($ruleset.enforcement -ne 'active') { throw 'develop ruleset is not active' }
$disabled = [ordered]@{ name=$ruleset.name; target=$ruleset.target; enforcement='disabled'; bypass_actors=@($ruleset.bypass_actors); conditions=$ruleset.conditions; rules=@($ruleset.rules) } | ConvertTo-Json -Depth 20 -Compress
$active = [ordered]@{ name=$ruleset.name; target=$ruleset.target; enforcement='active'; bypass_actors=@($ruleset.bypass_actors); conditions=$ruleset.conditions; rules=@($ruleset.rules) } | ConvertTo-Json -Depth 20 -Compress
try {
  $disabled | gh api --method PUT "repos/$repo/rulesets/$rulesetId" --input - | Out-Null
  git push --force-with-lease="refs/heads/develop:$developSha" origin "${mainSha}:refs/heads/develop"
} finally {
  $active | gh api --method PUT "repos/$repo/rulesets/$rulesetId" --input - | Out-Null
}
git fetch origin --prune
if ((git rev-parse origin/main) -ne (git rev-parse origin/develop)) { throw 'main and develop SHAs differ' }
if ((git rev-parse 'origin/main^{tree}') -ne (git rev-parse 'origin/develop^{tree}')) { throw 'main and develop trees differ' }
if ((gh api "repos/$repo/rulesets/$rulesetId" --jq '.enforcement') -ne 'active') { throw 'ruleset was not restored' }
```

Expected: exact equality, verified archive, and active ruleset.
