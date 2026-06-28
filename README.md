<p align="center">
  <img src="Shift/Assets.xcassets/AppIcon.appiconset/Shift-dark.png" alt="Shift App Icon" width="120" height="120" style="border-radius: 22px;">
</p>

<h1 align="center">Shift</h1>

<p align="center">
  <strong>A modern iOS workout tracker built with SwiftUI</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS_17+-blue" alt="iOS 17+">
  <img src="https://img.shields.io/badge/platform-watchOS_10+-green" alt="watchOS 10+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/SwiftUI-black" alt="SwiftUI">
  <img src="https://img.shields.io/badge/status-Work_in_Progress-yellow" alt="WIP">
</p>

---

> **Note:** This project is actively under development and not yet released on the App Store. Features, UI, and architecture are subject to change.

## About

Shift is a full-featured workout tracking app for iPhone, iPad, and Apple Watch. It combines a rich exercise library, flexible plan building, live workout logging, and health integrations into a clean, offline-first experience. An optional Pro subscription unlocks advanced features like AI-powered plan generation, progress photos, body measurements, and the full Watch companion app.

<p align="center">
  <img src="screenshots/today-empty.png" alt="Today" width="200">
  &nbsp;&nbsp;
  <img src="screenshots/active-workout.png" alt="Workout" width="200">
  &nbsp;&nbsp;
  <img src="screenshots/plans-list.png" alt="Plans" width="200">
  &nbsp;&nbsp;
  <img src="screenshots/exercise-library.png" alt="Exercises" width="200">
</p>

## Features

### Workout Tracking
- Log sets with weight, reps, and RPE (Rate of Perceived Exertion)
- Support for normal sets, warm-up sets, and drop sets
- Superset grouping for paired exercises
- Rest timer with Live Activity countdown on the lock screen
- Add exercises mid-workout from the full exercise library
- Workout notes and per-set notes
- Shareable workout summary cards
- Estimated workout duration

<p align="center">
  <img src="screenshots/active-workout.png" alt="Active workout with sets logged" width="280">
  &nbsp;&nbsp;&nbsp;
  <img src="screenshots/exercise-log.png" alt="Exercise logging with rest timer" width="280">
</p>

### Workout Plans
- Create and customize workout plans with drag-to-reorder exercises
- Set target sets, rep ranges, weights, and rest periods per exercise
- Browse pre-made explore plans for inspiration
- Superset support within plans
- Free tier includes up to 3 plans

<p align="center">
  <img src="screenshots/plans-list.png" alt="Plans list" width="280">
  &nbsp;&nbsp;&nbsp;
  <img src="screenshots/plan-editor.png" alt="Plan editor" width="280">
  &nbsp;&nbsp;&nbsp;
  <img src="screenshots/exercise-config.png" alt="Exercise configuration" width="280">
</p>

### AI Plan Generation (Pro)
- On-device AI-powered plan creation using Apple's Foundation Models (iOS 26+)
- 6-step guided wizard: personal stats, goals, schedule, preferences, generation, review
- Voice input for describing training preferences, injuries, and equipment
- 8 goal types: Build Muscle, Increase Strength, Tone & Define, General Fitness, Improve Endurance, Athletic Performance, Rehab, Body Recomposition
- Quick single-session generation or full multi-day program creation
- All processing happens on-device for privacy

### Exercise Library
- Extensive built-in exercise database with detailed instructions
- Filter by muscle group, equipment, and difficulty level
- Step-by-step exercise instructions with images
- Muscle target information (primary and secondary)
- Create custom exercises
- Track personal bests and full exercise history
- Set exercise-specific goals

<p align="center">
  <img src="screenshots/exercise-library.png" alt="Exercise library with filters" width="280">
</p>

### Progress Tracking
- **Weight**: Log entries, visualize trends, set target weight with deadline
- **Measurements** (Pro): Track chest, waist, arms, thighs, calves, and neck
- **Photos** (Pro): Progress photo capture and before/after comparison, protected with Face ID

<p align="center">
  <img src="screenshots/progress-weight.png" alt="Weight tracking with graph" width="280">
</p>

### Today Dashboard
- Week calendar showing completed and in-progress sessions
- Daily workout overview with quick access to start new workouts
- Streak tracking for consecutive workout days
- HealthKit activity card with move, exercise, stand, and step data
- Navigate to any past date to review history

<p align="center">
  <img src="screenshots/today-empty.png" alt="Today — start a workout" width="280">
  &nbsp;&nbsp;&nbsp;
  <img src="screenshots/today-completed.png" alt="Today — workout completed with streak" width="280">
</p>

### Explore Plans
- Browse popular training programs organized by split type
- Beginner and intermediate options for 3-day, 4-day, and 5-day splits
- Full Body Strength, Hypertrophy, Upper/Lower, Push/Pull/Legs, and more
- One-tap add to your plan library

<p align="center">
  <img src="screenshots/explore-plans.png" alt="Explore plans" width="280">
</p>

### Apple Watch Companion (Pro)
- Start and log workouts directly from your wrist
- Continue active iPhone workouts on the watch (and vice versa)
- Live step count display
- Rest timer on the watch
- Workout summary on completion
- Two-way sync with iPhone via WatchConnectivity

### Widgets & Complications
- **Today's Activity** — steps, workouts, streak at a glance
- **Streak Counter** — current workout streak with flame icon
- **Step Counter** — daily step progress
- **Weekly Progress** — workouts completed vs. goal
- **Quick Start** — one-tap workout launch
- **Watch Complications** — workout progress and step count on watch faces

### Smart Notifications
- Exercise goal reminders for unfinished daily targets
- Weekly frequency goal nudges (early, mid, and late week)
- Step goal milestone celebrations
- Progress tracking reminders (weight, measurements, photos)
- Intelligent scheduling with the notification decision engine

### HealthKit Integration
- Sync completed workouts to Apple Health
- Import step count, active energy, exercise time, stand hours
- Sync body weight entries
- Background step monitoring for real-time goal tracking
- Optional counting of workouts from other fitness apps

## Architecture

| Layer | Technology |
|---|---|
| UI | SwiftUI + `@Observable` |
| Local Database | GRDB (SQLite) |
| Backend & Auth | Supabase |
| Subscriptions | StoreKit 2 |
| Health | HealthKit |
| Watch Sync | WatchConnectivity |
| Widgets | WidgetKit + ActivityKit |
| AI | Apple Foundation Models (iOS 26+) |
| Notifications | UNUserNotificationCenter |

### Offline-First Design
Shift is built offline-first. The local GRDB database is the source of truth. A mutation queue stores changes and flushes them to Supabase when connectivity is available, with FIFO processing to maintain order. The app is fully functional without an internet connection.

### Project Structure

```
Shift/
├── App/                    # App entry point and root navigation
├── Models/                 # Data models and database records
├── Views/
│   ├── Auth/               # Sign in, sign up
│   ├── Onboarding/         # 9-step guided setup
│   ├── Today/              # Home dashboard and activity
│   ├── Workout/            # Live workout logging
│   ├── Plans/              # Plan creation, editing, AI generation
│   ├── Exercises/          # Exercise library and details
│   ├── Progress/           # Weight, measurements, photos
│   ├── Profile/            # User profile and personal bests
│   └── Settings/           # Preferences and account
├── Services/               # Business logic layer
├── Repositories/           # Database access (GRDB)
├── Database/               # Schema and migrations
├── Components/             # Reusable UI components
├── Helpers/                # Utilities and managers
├── Connectivity/           # WatchConnectivity bridge
└── Theme/                  # Color system and design tokens
ShiftWatch/                 # Apple Watch companion app
ShiftTimerWidget/           # Home screen widgets + Live Activity
ShiftWatchComplications/    # Watch face complications
Shared/                     # Shared models between targets
```

## Pro Subscription

Shift offers a free tier with core workout tracking and a Pro subscription that unlocks:

| Feature | Free | Pro |
|---|:---:|:---:|
| Workout tracking & logging | Yes | Yes |
| Exercise library & custom exercises | Yes | Yes |
| Weight tracking & graphs | Yes | Yes |
| Workout plans | Up to 3 | Unlimited |
| AI plan generation | — | Yes |
| Progress photos (Face ID locked) | — | Yes |
| Body measurements | — | Yes |
| Apple Watch app | — | Yes |
| Watch complications | — | Yes |
| Home screen widgets | — | Yes |

<p align="center">
  <img src="screenshots/pro-paywall.png" alt="Shift Pro subscription" width="280">
</p>

## Tech Stack

- **Swift 6** / **SwiftUI**
- **GRDB 7.10** — local SQLite database
- **Supabase** — authentication, cloud sync, row-level security
- **StoreKit 2** — subscription management
- **HealthKit** — health data integration
- **WidgetKit** + **ActivityKit** — widgets and Live Activities
- **WatchConnectivity** — iPhone ↔ Watch communication
- **Apple Foundation Models** — on-device AI (iOS 26+)

## Requirements

- iOS 17.0+ (AI features require iOS 26+)
- watchOS 10.0+
- Xcode 16+

## Status

This app is a **work in progress**. It is under active development and has not yet been released on the App Store. Current focus areas include:

- Final UI polish and refinements
- App Store submission preparation
- Additional explore/template plans
- Expanded exercise library content
- Performance optimization

Contributions, feedback, and ideas are welcome — feel free to open an issue.

## License

This project is proprietary. All rights reserved.
