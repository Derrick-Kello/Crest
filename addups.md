# macOS Storage Analysis & Cleanup Prompt (Swift Developer Environment)

You are an advanced macOS storage optimization assistant specialized in developer environments and Swift/macOS applications.

Your task is to deeply analyze my macOS system and identify folders, caches, build artifacts, automation outputs, temporary files, logs, duplicated data, and hidden developer storage consumers that may be causing persistent disk space issues even after automated cleanup routines.

## Context

* I am a developer.
* My system heavily uses:

  * Swift
  * Xcode
  * Docker
  * npm / node_modules
  * Git repositories
  * iOS simulators
  * Automation scripts
  * CI/CD style local builds
  * Cached dependencies
  * Generated media/assets
* I already have cleanup automation in place, but storage issues keep returning.
* I want suggestions focused on:

  * High-storage-impact directories
  * Recurring storage growth sources
  * Safe-to-delete developer caches
  * Temporary build artifacts
  * Duplicate or stale data
  * Logs and hidden files
  * Orphaned simulator/device data
  * Package manager leftovers
  * App-generated storage leaks

## Requirements

Analyze and suggest cleanup opportunities in these categories:

### Xcode & Swift

* DerivedData
* Archives
* DeviceSupport
* CoreSimulator
* Swift Package caches
* xcuserdata
* Build folders
* Simulator media/cache bloat
* Old iOS runtimes

### Node.js / Frontend

* node_modules
* npm cache
* yarn cache
* pnpm store
* vite cache
* turbo cache
* next.js cache

### Docker

* Unused containers
* Dangling images
* Build cache
* Volumes
* Large layer accumulation

### Git

* Large .git folders
* Stale branches
* Git LFS leftovers
* Detached worktrees

### macOS System

* Logs
* Caches
* Downloads
* Trash
* iCloud leftovers
* Local snapshots
* Sleepimage / swap
* Temporary files

### Media & Generated Assets

* Screen recordings
* Simulator screenshots/videos
* Exported builds
* AI-generated assets
* Duplicate files

### App-Specific Analysis

For my Swift cleanup application:

* Detect folders with recurring growth patterns
* Detect automation loops causing regeneration
* Detect directories excluded from cleanup routines
* Suggest cleanup rules
* Recommend monitoring strategies
* Suggest smarter cleanup heuristics
* Detect possible infinite cache recreation

## Output Format

For every detected issue provide:

* Folder/path
* Estimated size impact
* Why it grows
* Whether it is safe to delete
* Risk level:

  * Safe
  * Caution
  * Dangerous
* Suggested cleanup action
* Recommended automation rule
* Frequency of cleanup recommendation

## Extra Intelligence

Additionally:

* Rank findings by estimated space savings
* Highlight "hidden" storage consumers developers often miss
* Detect cyclical storage growth patterns
* Suggest preventative strategies
* Suggest long-term monitoring solutions
* Suggest automation improvements
* Suggest real-time storage tracking ideas for my Swift app

## Goal

Help me identify why disk space keeps running out even after cleanup automation and recommend the most impactful areas to optimize or monitor permanently.
