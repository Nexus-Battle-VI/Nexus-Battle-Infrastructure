# Commerce Main/Develop Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Commerce HU-56 from `develop` into `main`, validate its PostgreSQL migration, publish the GHCR image, and mirror `develop` to the final `main` SHA.

**Architecture:** Validate the existing wishlist implementation and migration against disposable PostgreSQL, integrate through a protected PR, and verify artifact publication. Preserve the old `develop` before a guarded exact mirror.

**Tech Stack:** Node.js 24.14.0, NestJS, PostgreSQL/Testcontainers, npm, Jest, Docker, Git, GitHub Actions, PowerShell

---

### Task 1: Validate HU-56 and its migration

**Files:**
- Existing implementation: `src/adapters/inbound/http/wishlist.controller.ts`
- Existing implementation: `src/application/use-cases/WishlistUseCases.ts`
- Existing implementation: `src/adapters/outbound/persistence/PostgresWishlistRepository.ts`
- Existing migration: `src/adapters/outbound/persistence/migrations/002-wishlist.ts`
- Existing tests: `test/unit/wishlist.spec.ts`
- Existing tests: `test/integration/wishlist-http.spec.ts`
- Existing tests: `test/db/postgres-wishlist-repository.spec.ts`

- [ ] **Step 1: Revalidate the branch relation**

```powershell
git fetch origin --prune
$mainSha = git rev-parse origin/main
$developSha = git rev-parse origin/develop
if ($mainSha -ne '497e00999778077772e5ce3240324d8ec31670e1') { throw 'main changed; re-audit required' }
if ($developSha -ne '773968bc9ed1c8fa1353dfe39334fc8c8347f054') { throw 'develop changed; re-audit required' }
if ((git merge-base origin/main origin/develop) -ne $mainSha) { throw 'develop is not a fast-forward of main' }
```

Expected: exit 0.

- [ ] **Step 2: Run the application and database gates in the isolated `develop` worktree**

```powershell
fnm env --shell powershell | Out-String | Invoke-Expression
fnm use 24.14.0
npm ci
npm run format:check
npm run lint
npm run typecheck
npm run build
npm test -- --runInBand
npm run test:db -- --runInBand
docker build --tag nexus-battle-commerce:sync-validation .
```

Expected: all application suites pass; Testcontainers applies the wishlist migration to disposable PostgreSQL; Docker build exits 0.

### Task 2: Integrate through the protected `main`

**Files:**
- Modify: none; PR uses `develop` as its head

- [ ] **Step 1: Create the integration PR**

```powershell
gh pr create -R Nexus-Battle-VI/Nexus-Battle-Commerce --base main --head develop --title "feat(commerce): integrar HU-56 en main" --body "## Resumen`n- Integra lista de deseos y marca de adquirido de HU-56.`n- Incluye persistencia PostgreSQL y migración 002-wishlist.`n`n## Validación`n- formato, lint, tipos, build y Jest`n- suite PostgreSQL/Testcontainers`n- construcción Docker local`n`nDespués del merge, develop se reflejará al SHA final de main."
```

Expected: a new PR URL targeting `main`.

- [ ] **Step 2: Wait for checks and required human review**

```powershell
$pr = gh pr list -R Nexus-Battle-VI/Nexus-Battle-Commerce --base main --head develop --state open --json number --jq '.[0].number'
gh pr checks -R Nexus-Battle-VI/Nexus-Battle-Commerce $pr --watch
gh pr view -R Nexus-Battle-VI/Nexus-Battle-Commerce $pr --json reviewDecision,mergeStateStatus,statusCheckRollup
```

Expected: successful checks and `APPROVED`. Pause if the required reviewer has not approved.

- [ ] **Step 3: Squash-merge and verify GHCR publication**

```powershell
gh pr merge -R Nexus-Battle-VI/Nexus-Battle-Commerce $pr --squash --delete-branch=false
git fetch origin --prune
$mainSha = git rev-parse origin/main
$runId = gh run list -R Nexus-Battle-VI/Nexus-Battle-Commerce --commit $mainSha --workflow CI --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch -R Nexus-Battle-VI/Nexus-Battle-Commerce $runId --exit-status
$publish = gh run view -R Nexus-Battle-VI/Nexus-Battle-Commerce $runId --json jobs --jq '.jobs[] | select(.name == "Publicar imagen en GHCR") | .conclusion'
if ($publish -ne 'success') { throw 'GHCR publication did not succeed' }
```

Expected: merged PR and successful publication job.

### Task 3: Archive and mirror `develop`

**Files:**
- Modify: none

- [ ] **Step 1: Run the guarded mirror operation**

```powershell
$repo = 'Nexus-Battle-VI/Nexus-Battle-Commerce'
$rulesetId = 21879163
$archive = 'archive/develop-before-sync-2026-08-31'
git fetch origin --prune
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
