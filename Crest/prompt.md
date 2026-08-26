# Crest — macOS Storage Intelligence App

## Overview
Build a native macOS application using Swift + SwiftUI that runs as BOTH:
1. Menu Bar utility (status bar app)
2. Full desktop dashboard application

The app helps developers analyze disk usage, identify large directories, and safely clean unnecessary system and development files.

---

## Core Objective
Create a “Storage Intelligence System” for macOS that:
- Visualizes disk usage in real time
- Detects developer-related storage bloat
- Suggests safe cleanup actions
- Executes cleanup only with explicit user approval
- Provides a modern macOS-native UI experience

---

## App Architecture

### 1. Menu Bar Mode (NSStatusBar)
- Shows current free disk space (e.g. “32GB Free”)
- Color indicator:
  - Green → healthy
  - Yellow → moderate usage
  - Red → low storage

#### Dropdown Menu:
- Open Dashboard
- Run Quick Scan
- Clean Developer Cache
- Clean Docker
- View Storage Report
- Quit App

---

### 2. Desktop App Mode (Main Window)
A full SwiftUI dashboard window with sidebar navigation.

#### Sidebar Sections:
- Overview
- Storage Map
- Developer Cleanup
- Docker Manager
- System Insights
- Settings

---

## UI DESIGN SYSTEM

### Visual Style
- macOS-native design (like Settings app)
- Material blur + vibrancy effects
- SF Symbols for icons
- Dark mode first-class support
- Smooth SwiftUI animations

---

## DASHBOARD UI LAYOUT

### 1. Overview Screen
- Large disk usage summary card
- Pie chart (storage breakdown)
- “Free Space” indicator
- Quick action buttons

### 2. Storage Map Screen
- Bar chart of top 10 largest folders
- Drill-down expandable folders
- Color-coded categories:
  - System
  - Developer
  - Apps
  - Media
  - Cache

### 3. Developer Cleanup Screen
- Dedicated dev tools panel:
  - Xcode DerivedData
  - npm cache
  - gradle cache
  - Android emulator storage
  - Python cache
- Each item shows:
  - Size
  - Risk level (safe / moderate)
  - Clean button

### 4. Docker Manager Screen
- Show:
  - Images size
  - Containers usage
  - Volumes
- Actions:
  - docker system df
  - docker system prune
  - volume cleanup

---

## CLEANUP ENGINE (CRITICAL SAFETY RULES)

### Allowed cleanup actions ONLY:
- Xcode DerivedData
- npm cache (npm cache clean --force)
- Gradle cache
- Android emulator cache
- Docker prune commands
- Safe ~/Library/Caches subfolders

### NEVER TOUCH:
- Documents
- Desktop
- Photos
- iCloud Drive
- System root files

### Safety Requirements:
- Always show preview before deletion
- Require user confirmation modal
- Show estimated space reclaimed
- Log all actions

---

## DISK SCANNING ENGINE

Scan and classify:
- ~/Library/Application Support
- ~/Library/Containers
- ~/Library/Group Containers
- ~/Developer
- ~/.npm
- ~/.android
- ~/.docker
- ~/Downloads

Sort all results by size descending.

---

## MENU BAR FEATURES

- Live disk usage indicator
- Quick actions dropdown
- Open full dashboard button
- Auto-refresh every 10–30 seconds

---

## BACKGROUND FEATURES

- Periodic storage scan
- Notification alerts:
  - "Cache exceeded 10GB"
  - "Docker reclaimable: 3GB"
- Optional auto-clean suggestions (not automatic deletion)

---

## DATA VISUALIZATION

Use Swift Charts:
- Pie chart → storage categories
- Bar chart → folder sizes
- Progress bars → disk usage trends

---

## SETTINGS SCREEN

- Enable/disable menu bar mode
- Auto scan interval
- Cleanup safety level
- Docker integration toggle

---

## OUTPUT REQUIREMENTS

Generate:
- Full SwiftUI macOS project structure
- Menu bar integration (NSStatusBar)
- Desktop dashboard UI
- Disk scanning service
- Cleanup engine with safety system
- Charts-based visualization UI
- Clean modular architecture

---

## FINAL GOAL
A production-ready macOS utility that feels like a native Apple system tool but designed for developers who need deep disk visibility and safe cleanup automation.