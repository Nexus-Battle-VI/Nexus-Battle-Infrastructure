# Notifications Main/Develop Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate Notifications HU-04 from `develop` into `main`, publish the validated GHCR image, and mirror `develop` to the final `main` SHA.

**Architecture:** Validate the existing `develop` commit in isolation, open a protected PR to `main`, wait for review and required checks, and verify the main-branch publication job. Then archive and mirror `develop` with a guarded ruleset suspension.

**Tech Stack:** Node.js 24.14.0, npm, Jest, Docker, Git, GitHub Actions, PowerShell

---

### Task 1: Validate HU-04 locally

**Files:**
- Existing change: `.env.example`
- Existing change: `package.json`
- Existing change: `src/adapters/templates/default-templates.ts`
- Existing change: `src/infrastructure/bootstrap/composition-root.ts`
- Existing change: `src/infrastructure/config/env.ts`
- Existing change: `src/infrastructure/http/health-server.ts`
- Existing change: `src/worker.ts`
- Existing tests: `tests/integration/health-server.test.ts`
- Existing tests: `tests/unit/adapters/adapters.test.ts`
- Existing tests: `tests/unit/infrastructure/infrastructure.test.ts`

- [ ] **Step 1: Revalidate the branch relation**

```powershell
git fetch origin --prune
$mainSha = git rev-parse origin/main
$developSha = git rev-parse origin/develop
if ($mainSha -ne '5f0ec86241d9af83a7689a8b8f51d35f0c4be7ea') { throw 'main changed; re-audit required' }
if ($developSha -ne 'da4419f3020734dbfb508113dd8e0e931259cce3') { throw 'develop changed; re-audit required' }
if ((git merge-base origin/main origin/develop) -ne $mainSha) { throw 'develop is not a fast-forward of main' }
```

Expected: exit 0.

- [ ] **Step 2: Run the complete local quality gate in the isolated `develop` worktree**

```powershell
fnm env --shell powershell | Out-String | Invoke-Expression
fnm use 24.14.0
npm ci
npm run format:check
npm run lint
npm run typecheck
npm run build
npm test -- --runInBand
docker build --tag nexus-battle-notifications:sync-validation .
```

Expected: every command exits 0 and Docker produces the local validation image.

### Task 2: Integrate through the protected `main`

**Files:**
- Modify: none; PR uses `develop` as its head

- [ ] **Step 1: Create the integration PR**

```powershell
gh pr create -R Nexus-Battle-VI/Nexus-Battle-Notifications --base main --head develop --title "feat(notifications): integrar HU-04 en main" --body "## Resumen`n- Integra las plantillas de recuperación y SMTP con autenticación de HU-04.`n- Amplía el health check y conserva las pruebas existentes.`n`n## Validación`n- npm ci, formato, lint, tipos, build y Jest`n- construcción Docker local`n`nDespués del merge, develop se reflejará al SHA final de main."
```

Expected: a new PR URL targeting `main`.

- [ ] **Step 2: Wait for required checks and review**

```powershell
$pr = gh pr list -R Nexus-Battle-VI/Nexus-Battle-Notifications --base main --head develop --state open --json number --jq '.[0].number'
gh pr checks -R Nexus-Battle-VI/Nexus-Battle-Notifications $pr --watch
gh pr view -R Nexus-Battle-VI/Nexus-Battle-Notifications $pr --json reviewDecision,mergeStateStatus,statusCheckRollup
```

Expected before merge: all checks successful, `reviewDecision` is `APPROVED`, and `mergeStateStatus` permits merge. Pause for the required human review if approval is absent.

- [ ] **Step 3: Squash-merge and verify GHCR publication**

```powershell
gh pr merge -R Nexus-Battle-VI/Nexus-Battle-Notifications $pr --squash --delete-branch=false
git fetch origin --prune
$mainSha = git rev-parse origin/main
$runId = gh run list -R Nexus-Battle-VI/Nexus-Battle-Notifications --commit $mainSha --workflow CI --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch -R Nexus-Battle-VI/Nexus-Battle-Notifications $runId --exit-status
$publish = gh run view -R Nexus-Battle-VI/Nexus-Battle-Notifications $runId --json jobs --jq '.jobs[] | select(.name == "Publicar imagen en GHCR") | .conclusion'
if ($publish -ne 'success') { throw 'GHCR publication did not succeed' }
```

Expected: merged PR, successful CI, and successful GHCR publication job.

### Task 3: Archive and mirror `develop`

**Files:**
- Modify: none

- [ ] **Step 1: Run the guarded mirror operation**

```powershell
$repo = 'Nexus-Battle-VI/Nexus-Battle-Notifications'
$rulesetId = 21879181
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

Expected: exact SHA/tree equality, verified archive, and active ruleset.
