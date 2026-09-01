# Web Main/Develop Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply only Web HU-05.4 on top of the current HU-04 `main`, validate the combined application, publish its GHCR image, and mirror `develop` to the final `main` SHA.

**Architecture:** The historical branch merge reports 19 artificial conflicts because Git cannot recognize prior squash-equivalent trees. Create an integration branch from `main` and cherry-pick the single unique HU-05.4 commit; an exact three-way simulation using its real parent completed without conflicts and preserves HU-04.

**Tech Stack:** React, TypeScript, Vite, Node.js 24.14.0, npm, Vitest, Docker, Git, GitHub Actions, PowerShell

---

### Task 1: Prove the reduced integration model

**Files:**
- Source commit: `338f6c16c6cbe9043abd6cd96ce802e8c4cbb56b`
- Source parent: `0082cff8c2ca08a88a531ab126088f8a42a568ae`
- Base `main`: `16e12998f9c5a4c633b89ff362e2e75fec4cb0cb`
- Modify through cherry-pick: the 59 paths reported by `git diff-tree -r 338f6c1`

- [ ] **Step 1: Revalidate tree equivalence and branch SHAs**

```powershell
git fetch origin --prune
if ((git rev-parse origin/main) -ne '16e12998f9c5a4c633b89ff362e2e75fec4cb0cb') { throw 'main changed; re-audit required' }
if ((git rev-parse origin/develop) -ne '338f6c16c6cbe9043abd6cd96ce802e8c4cbb56b') { throw 'develop changed; re-audit required' }
if ((git show -s --format=%T 3a67f097df68874af1211a7304a101604f9388c9) -ne (git show -s --format=%T efd08b2cc50c32034721b52795bc975f8dfcd21c)) { throw 'pre-HU03 trees differ' }
if ((git show -s --format=%T 0082cff8c2ca08a88a531ab126088f8a42a568ae) -ne (git show -s --format=%T 860a1d42023a59ebf1f5892962e1ce5e3128462d)) { throw 'HU03 trees differ' }
```

Expected: exit 0.

- [ ] **Step 2: Re-run the exact merge simulation**

```powershell
$simulation = git merge-tree --write-tree --merge-base=0082cff8c2ca08a88a531ab126088f8a42a568ae --name-only --messages 16e12998f9c5a4c633b89ff362e2e75fec4cb0cb 338f6c16c6cbe9043abd6cd96ce802e8c4cbb56b
if ($LASTEXITCODE -ne 0) { throw 'HU-05.4 no longer applies cleanly to main' }
if ($simulation -match 'CONFLICT') { throw 'unexpected semantic conflict' }
```

Expected: exit 0 and no `CONFLICT` line.

### Task 2: Build the integration branch

**Files:**
- Modify: `src/app/**`
- Modify: `src/components/ui/**`
- Modify: `src/features/account/**`
- Modify: `src/features/auth/login/**`
- Modify: `src/features/landing/LandingPage.tsx`
- Modify: `src/index.css`
- Modify: `src/lib/**`
- Modify: `src/routes/**`
- Modify: `src/shared/**`
- Tests: all `*.test.ts` and `*.test.tsx` paths contained in commit `338f6c1`

- [ ] **Step 1: Create the integration branch from the audited `main`**

```powershell
git switch -c integration/hu-05-4-a-main 16e12998f9c5a4c633b89ff362e2e75fec4cb0cb
```

Expected: new local branch at the audited `main` SHA.

- [ ] **Step 2: Apply only HU-05.4**

```powershell
git cherry-pick 338f6c16c6cbe9043abd6cd96ce802e8c4cbb56b
if (git diff --name-only --diff-filter=U) { throw 'unexpected unresolved conflicts' }
```

Expected: one new commit and no unmerged paths. If this conflicts after a changed preflight, abort the cherry-pick and re-audit instead of choosing `ours` or `theirs`.

- [ ] **Step 3: Verify both HU-04 and HU-05.4 behavior**

```powershell
fnm env --shell powershell | Out-String | Invoke-Expression
fnm use 24.14.0
npm ci
npm run format:check
npm run lint
npm run typecheck
npm run build
npm test
docker build --tag nexus-battle-web:hu05-main-validation .
```

Expected: all commands exit 0. The full suite covers the four-step password-recovery route from HU-04 and Mi Cuenta routes, profile, preferences, security, theme and responsive navigation from HU-05.4.

- [ ] **Step 4: Push the integration branch**

```powershell
git push -u origin integration/hu-05-4-a-main
```

Expected: remote integration branch created.

### Task 3: Merge through protected `main` and verify publication

**Files:**
- Modify: none beyond the integration commit

- [ ] **Step 1: Create the PR**

```powershell
gh pr create -R Nexus-Battle-VI/Nexus-Battle-Web --base main --head integration/hu-05-4-a-main --title "feat(web): integrar HU-05.4 en main sin perder HU-04" --body "## Resumen`n- Aplica únicamente HU-05.4 sobre el main que ya contiene HU-04.`n- Evita los 19 conflictos históricos demostrando equivalencia de los árboles previos.`n- Conserva recuperación de contraseña y añade Mi Cuenta responsive.`n`n## Validación`n- formato, lint, tipos, build y suite completa`n- construcción Docker local`n`nDespués del merge, develop se reflejará al SHA final de main."
```

Expected: a PR URL targeting `main`.

- [ ] **Step 2: Wait for checks and human review**

```powershell
$pr = gh pr list -R Nexus-Battle-VI/Nexus-Battle-Web --base main --head integration/hu-05-4-a-main --state open --json number --jq '.[0].number'
gh pr checks -R Nexus-Battle-VI/Nexus-Battle-Web $pr --watch
gh pr view -R Nexus-Battle-VI/Nexus-Battle-Web $pr --json reviewDecision,mergeStateStatus,statusCheckRollup
```

Expected: all required checks successful and `reviewDecision=APPROVED` before merge.

- [ ] **Step 3: Squash-merge and verify GHCR publication**

```powershell
gh pr merge -R Nexus-Battle-VI/Nexus-Battle-Web $pr --squash --delete-branch=false
git fetch origin --prune
$mainSha = git rev-parse origin/main
$runId = gh run list -R Nexus-Battle-VI/Nexus-Battle-Web --commit $mainSha --workflow CI --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch -R Nexus-Battle-VI/Nexus-Battle-Web $runId --exit-status
$publish = gh run view -R Nexus-Battle-VI/Nexus-Battle-Web $runId --json jobs --jq '.jobs[] | select(.name == "Publicar imagen en GHCR") | .conclusion'
if ($publish -ne 'success') { throw 'GHCR publication did not succeed' }
```

Expected: merged PR and successful publication job.

### Task 4: Archive and mirror `develop`

**Files:**
- Modify: none

- [ ] **Step 1: Run the guarded mirror operation**

```powershell
$repo = 'Nexus-Battle-VI/Nexus-Battle-Web'
$rulesetId = 21819325
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
