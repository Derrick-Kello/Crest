# DiskPilot — addups.md Integration Plan

**Last validated:** May 28, 2026 (live `du` on your Mac)

## Executive summary

Disk space pressure on your Mac is **not only from Xcode/npm**. The largest user-writable consumers are:

1. **Application Support** (~13 GB) — app databases and local data  
2. **Developer folder** (~8 GB) — Xcode + CoreSimulator  
3. **Library/Caches** (~6 GB) — Yarn, browsers, VS Code ShipIt, Spotify, Homebrew  

Caches **regrow after cleanup** when you use those apps. DiskPilot now surfaces ranked findings with risk levels and safe cleanup paths.

---

## Live audit (your machine today)

| Rank | Path | Size | Risk | Safe action |
|------|------|------|------|-------------|
| 1 | `~/Library/Application Support` | **13 GB** | Caution | Per-app review only |
| 2 | `~/Library/Developer` | **8 GB** | Caution | Simulator + DerivedData |
| 3 | `~/Library/Caches` | **6 GB** | Safe–Caution | Per-cache cleanup |
| 3a | └ Yarn | 1.8 GB | Safe | Delete / yarn cache clean |
| 3b | └ VS Code ShipIt | 997 MB | Safe | Delete updater cache |
| 3c | └ Brave | 936 MB | Safe | Browser cache |
| 3d | └ Spotify | 499 MB | Safe | App cache |
| 3e | └ Homebrew | 340 MB | Safe | `brew cleanup -s` |
| 4 | `~/Downloads` | 574 MB | Caution | Manual review |
| 5 | `~/.npm` | 423 MB | Safe | npm cache clean |
| 6 | `~/Library/Logs` | 82 MB | Safe | Delete old logs |

**Volume:** ~18 GB free on `/` (improved from earlier ~728 MB snapshot in prior audit).

---

## What was implemented (Phase 1 — done)

| Component | Status |
|-----------|--------|
| `StorageFinding` + `DeepScanResult` models | ✅ |
| `PathSafetyClassifier` — OS vs user data | ✅ |
| `DeepScanService` — 25+ paths + dynamic cache/app discovery | ✅ |
| Expanded cleanup targets (Simulator, Yarn, SPM, Logs, ShipIt, Homebrew, Trash) | ✅ |
| **Storage Findings** sidebar + ranked UI | ✅ |
| Low-disk banner on Overview (< 5% free) | ✅ |
| Reclaimable estimate for safe targets | ✅ |

### New sidebar: **Storage Findings**

- Ranked list with size, risk badge, growth reason, suggested action  
- Filter by category and risk  
- Jump to Developer Cleanup for automatable safe targets  
- Deep Scan runs on bootstrap and after quick scan  

---

## MCP servers (Cursor)

Configured MCP plugins (Cloudflare, Prisma, Stripe, Box, Granola, Resend) **do not provide macOS disk tools**. Storage truth comes from:

- DiskPilot app (`du`, `simctl`, `docker`, `brew`)  
- Local shell validation (used for this plan)

**Future:** optional `diskpilot-mcp` local server wrapping `DeepScanService` for Cursor agents.

---

## Path safety rules (non-OS deletion)

**Never auto-delete:**

- `/System`, `/usr`, `/bin`, Keychains, user Documents/Desktop/Photos/iCloud  
- `.git` repositories (Dangerous — review only)  
- Application Support children without explicit target  

**Safe automated cleanup:**

- DerivedData, npm/Yarn/SPM/pip caches, Xcode caches, Logs, ShipIt updaters, Homebrew cache  
- Simulator unavailable devices (`simctl delete unavailable`)  

**Caution (confirm in UI):**

- CoreSimulator total, Downloads, Trash, Docker, per-app caches discovered dynamically  

---

## Phase 2 — Next sprint

- [ ] Per-finding “Clean now” on Storage Findings row  
- [ ] Cursor ShipIt cache glob (`com.todesktop.*.ShipIt`)  
- [ ] `node_modules` discovery under `~/Developer`, `~/Projects` (depth 6)  
- [ ] Large `.git` detection (`git count-objects`)  
- [ ] Docker `system df -v` in UI  

## Phase 3 — Monitoring

- [ ] SQLite scan history + “growing again” badge  
- [ ] Menu bar top offender when free < 10%  
- [ ] `tmutil listlocalsnapshots` (explain only, Dangerous)  

---

## Preventative schedule (addups.md)

| Frequency | Action |
|-----------|--------|
| Weekly | Safe caches: Yarn, npm, SPM, DerivedData, Logs |
| Monthly | Simulator unavailable + Docker prune + Homebrew cleanup |
| Quarterly | Application Support top apps + Downloads review |
| Always | Keep **15+ GB** free for macOS updates |

---

## How to validate in the app

1. **⌘R** run DiskPilot  
2. Open **Storage Findings** → **Deep Scan**  
3. Compare top 5 sizes to terminal:  
   `du -sh ~/Library/Caches/Yarn ~/Library/Developer/CoreSimulator ~/.npm`  
4. Confirm risk badges: Yarn = Safe, Application Support = Caution  
5. Use **Developer Cleanup** for Yarn / npm / Logs / ShipIt  

---

## Manual quick wins (today)

```bash
du -sh ~/Library/Application\ Support/* | sort -hr | head -10
rm -rf ~/Library/Caches/Yarn/*
rm -rf ~/Library/Caches/com.microsoft.VSCode.ShipIt/*
xcrun simctl delete unavailable
brew cleanup -s
```
