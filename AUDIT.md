# Shift App - Comprehensive Audit Report

**Date:** 2026-04-14
**Scope:** Full-stack audit of iOS app (SwiftUI + GRDB + Supabase)
**Auditor:** Automated senior-level code review

---

## Fix Summary

The following issues have been **fixed** in this session:

| # | Issue | Fix Applied |
|---|-------|-------------|
| 1.1 | Silent data loss on malformed mutations | Added `os.log` logging before deleting malformed mutations |
| 1.2 | Mutation queue blocks forever on failure | Changed `break` to `continue` so failed mutations don't block the entire queue |
| 1.4 | Orphaned session_sets on delete | SessionRepository.delete() now cascade-deletes session_sets |
| 1.5 | Orphaned plan_exercises on delete | PlanRepository.delete() now cascade-deletes plan_exercises |
| 1.8 | Date parsing silent fallback | Added warning logs when ISO8601 parsing falls back to Date() |
| 1.9 | Reference data silent decode failures | Replaced `try? ?? []` with proper do/catch + logging in pullReferenceData and pullUserData |
| 1.11 | Missing database indexes | Added migration with 5 new indexes: sessions(user_id, started_at), sets(exercise_id), plan_exercises(exercise_id, plan_id), goals(user_id, is_completed) |
| 2.1 | Live Activity race condition | Made stopCurrent async, await activity end before clearing ID |
| 2.2 | Timer wrong after background | Timer now uses wall-clock endTime + foreground recalculation instead of decrementing |
| 2.3 | No notification permission check | All scheduling methods now check isAuthorized() before calling center.add() |
| 2.6 | GoalNotification race condition | Added NSLock + mark-before-schedule to prevent duplicate notifications |
| 2.8 | No Live Activity error logging | Added os.log error logging for Activity.request failures |
| 3.1 | finishSession background work not awaited | Removed detached Task{}, goal checking and HealthKit sync now awaited inline |
| 3.2 | HealthKit errors silently swallowed | Replaced try? with do/catch + logger.error for HealthKit saves |
| 3.4 | Personal bests from filtered range | Now computed from allHistory, not filtered dataset |
| 3.5 | resumeSession no error handling | Added do/catch with logging around enqueue call |
| 3.7 | Profile settings encoding silently fails | Replaced try? with do/catch + logger.error |
| 3.8 | Weight entry no validation | Added guard for positive weight < 1000 and non-future date |
| 3.9 | Module-level authManager not thread-safe | Added NSLock protection for _authManager reads/writes |
| 3.11 | No logging in service layer | Added os.log Logger to SyncService, WorkoutService, ProfileService, NotificationManager, LiveActivityManager |
| 4.1 | ProfileView goal progress always zero | Now fetches actual currentMax per exercise instead of using baselineWeight |
| 4.5 | Hardcoded weight conversion | Replaced `* 2.20462` with `convertWeight()` from Format.swift |
| 4.6 | No reps validation in ExerciseLogView | Added `guard Int(reps) > 0` before logging sets |
| 4.9 | Settings no input validation | Added name trimming and age range validation (1-120) |
| 4.11 | Duplicate duration formatting | WorkoutView now delegates to WorkoutDurationEstimator.formatDuration() |
| - | Profile save error swallowed | SettingsView now shows error message if profile save fails |

---

## Table of Contents

1. [Data Layer & Sync](#1-data-layer--sync)
2. [Notifications & Timers](#2-notifications--timers)
3. [Workout & Service Layer](#3-workout--service-layer)
4. [UI Views & Components](#4-ui-views--components)
5. [Summary](#5-summary)

---

## 1. Data Layer & Sync

### CRITICAL

#### 1.1 Silent Data Loss on Malformed Mutations
**File:** `Shift/Services/SyncService.swift:41-44`
**Issue:** When a mutation payload can't be parsed as JSON, the row is silently deleted and counted as "flushed". No error logging, no dead-letter queue. The user's change is permanently lost without any indication.
**Fix:** Log malformed payloads before deleting. Consider a dead-letter table for unparseable mutations.

#### 1.2 Mutation Queue Blocks Indefinitely on First Failure
**File:** `Shift/Services/SyncService.swift:81-84`
**Issue:** When a mutation fails (e.g., transient network error), the loop breaks immediately. The failed mutation stays in the queue forever, blocking all subsequent mutations. No retry, no backoff, no expiry.
**Fix:** Add retry count to mutations. After N retries with exponential backoff, move to dead-letter. Allow subsequent mutations to proceed if a mutation is non-critical.

#### 1.3 Missing Foreign Key Constraints in Local SQLite
**File:** `Shift/Database/AppDatabase.swift:59-183`
**Issue:** Tables `plan_exercises`, `session_sets`, `workout_sessions`, and `exercise_goals` reference parent tables but have no `FOREIGN KEY` constraints. `PRAGMA foreign_keys = ON` is enabled (line 41) but there are no constraints to enforce.
**Impact:** Orphaned child records when parents are deleted (see 1.4, 1.5, 1.6).

#### 1.4 Orphaned Session Sets on Session Delete
**File:** `Shift/Repositories/SessionRepository.swift:121-128`
**Issue:** `delete()` only removes the session row. Associated `session_sets` remain in the database. While `WorkoutService.deleteSession()` manually deletes sets first, any direct call to `SessionRepository.delete()` (e.g., from sync) will orphan sets.
**Fix:** Add cascade delete in the repository or add FK constraints with ON DELETE CASCADE.

#### 1.5 Orphaned Plan Exercises on Plan Delete
**File:** `Shift/Repositories/PlanRepository.swift` (delete method)
**Issue:** Same as 1.4 but for plan exercises. `PlanService.deletePlan()` manually cleans up, but a direct repository delete will orphan `plan_exercises`.

#### 1.6 Exercise Goals Not Cleaned Up
**File:** `Shift/Repositories/ExerciseRepository.swift`
**Issue:** When exercises are deleted or replaced, associated `exercise_goals` are not cleaned up.

#### 1.7 Cascade Delete Mismatch: Local vs Remote
**File:** `supabase/schema.sql` vs `Shift/Database/AppDatabase.swift`
**Issue:** Supabase has `ON DELETE CASCADE` for `plan_exercises` and `session_sets`. Local SQLite does not. Offline deletes of parent records will not cascade locally, but will cascade remotely on sync, creating state divergence.

#### 1.8 Date Parsing Falls Back to `Date()` Silently
**File:** `Shift/Services/ProfileService.swift:116-121` (and similar patterns in models)
**Issue:** When ISO8601 date parsing fails, the code silently falls back to `Date()`:
```swift
let createdAt = ISO8601DateFormatter.shared.date(from: remote.createdAt)
    ?? ISO8601DateFormatter.sharedWithFractional.date(from: remote.createdAt)
    ?? Date()  // A 2023 record becomes "now"
```
**Impact:** Corrupted timestamps. A historical record gets a current date.

#### 1.9 Reference Data Sync Silently Returns Empty on Decode Failure
**File:** `Shift/Services/SyncService.swift:113, 126`
**Issue:** `(try? JSONDecoder().decode(...)) ?? []` silently returns empty arrays if decoding fails. User gets no exercises or muscle groups with no error indication.

#### 1.10 Non-Atomic Local Write + Enqueue
**File:** `Shift/Services/ProfileService.swift:49-70`
**Issue:** Local upsert happens at line 49, enqueue at line 65. If the app crashes between these, the local change is persisted but never queued for sync. On restart, the local state diverges from remote permanently.
**Fix:** Wrap both operations in a single database transaction.

### HIGH

#### 1.11 Missing Database Indexes
**File:** `Shift/Database/AppDatabase.swift`
Missing indexes that affect query performance:
- `workout_sessions (user_id, started_at)` - used by findCompleted, findInProgress, findCompletedSince
- `session_sets (exercise_id)` - used by findForExercise queries
- `plan_exercises (exercise_id)` - used for exercise lookups in plans
- `exercise_goals (user_id, is_completed)` - used for active goal queries

#### 1.12 No Mutation Deduplication
**File:** `Shift/Services/SyncService.swift` and repositories
**Issue:** Rapid edits to the same record create N separate mutations. If a user adjusts their profile name 5 times, 5 separate update mutations are queued instead of coalescing into one.

#### 1.13 Pull Does Not Delete Locally-Removed Remote Records
**File:** `Shift/Services/SyncService.swift:151-256`
**Issue:** `pullUserData()` upserts records from remote but never deletes local records that no longer exist on remote. If a record is deleted on another device, it will persist locally forever.

---

## 2. Notifications & Timers

### CRITICAL

#### 2.1 Live Activity Race Condition on Stop
**File:** `Shift/Helpers/LiveActivityManager.swift:42-49`
**Issue:** `stopCurrent()` sets `currentActivityId = nil` (line 48) BEFORE the async `Task` to end the activity completes (line 45-47). If `start()` is called immediately after `stop()`:
1. `stopCurrent()` fires the Task to end old activity
2. `currentActivityId` is set to nil immediately
3. `start()` calls `stopCurrent()` again, which returns early (id is nil)
4. New activity is created
5. Old activity's async end finally executes... or doesn't
**Impact:** Zombie Live Activities stuck on Dynamic Island.
**Fix:** Make `stopCurrent()` async and await the activity end before clearing the ID.

#### 2.2 Timer Continues Running in Background
**File:** `Shift/Helpers/RestTimerManager.swift:30-46`
**Issue:** No `scenePhase` observer. When the app goes to background:
- The `Timer` may not fire reliably (iOS throttles background timers)
- `remaining` becomes out of sync with wall-clock time
- When returning to foreground, the timer display is wrong
- Haptics fire in background where they can't be felt
**Fix:** Store the `endTime` as wall-clock Date. On foreground, recalculate `remaining` from `endTime - Date()`.

#### 2.3 No Notification Permission Check Before Scheduling
**File:** `Shift/Helpers/NotificationManager.swift:44-62, 77-100, 108-130`
**Issue:** All notification scheduling methods call `center.add(request)` without checking if the user granted notification permission. If denied, notifications silently fail.
**Fix:** Check `UNUserNotificationCenter.getNotificationSettings()` before scheduling.

### HIGH

#### 2.4 Permission Request Not Awaited at Launch
**File:** `Shift/App/ShiftApp.swift:40-41`
**Issue:** `requestPermissionIfNeeded()` fires the permission dialog but discards the completion handler. `registerCategories()` and `scheduleAllNotifications()` are called immediately after, potentially before the user responds.

#### 2.5 Timer Notification Fires After In-App Timer Completes
**File:** `Shift/Helpers/RestTimerManager.swift:36` + `NotificationManager.swift:44-62`
**Issue:** The system notification is scheduled for exactly `seconds` duration. The in-app Timer fires every 1 second and may complete slightly before or after the system notification. If the app is in foreground when the timer ends, the user gets haptics AND then the notification fires moments later.

#### 2.6 GoalNotificationService UserDefaults Race Condition
**File:** `Shift/Services/GoalNotificationService.swift` (fireOnceToday method)
**Issue:** De-duplication uses non-atomic UserDefaults check-then-set. If `checkAndNotifyGoalCompletion()` is called from both app foreground AND HealthKit background delivery simultaneously, the same notification can fire twice.

### MEDIUM

#### 2.7 Live Activity Stale Date Too Short
**File:** `Shift/Helpers/LiveActivityManager.swift:23`
**Issue:** `staleDate: endTime.addingTimeInterval(10)` - only 10 seconds after timer ends, the Live Activity dims. No "Complete" state is shown.

#### 2.8 No Error Logging for Failed Live Activity
**File:** `Shift/Helpers/LiveActivityManager.swift:33-35`
**Issue:** Activity.request errors are caught with an empty catch block and a comment. If activities consistently fail (e.g., limit exceeded), there's no way to diagnose.

---

## 3. Workout & Service Layer

### CRITICAL

#### 3.1 finishSession Background Task Not Awaited
**File:** `Shift/Services/WorkoutService.swift:80-100`
**Issue:** Goal checking and HealthKit sync run in a detached `Task {}` that is never awaited. If the app is killed immediately after `finishSession()` returns:
- Goals may never be checked for completion
- HealthKit workout may never be saved
- Notification rescheduling may never happen
**Fix:** Await the critical work or use `BGProcessingTask`.

#### 3.2 HealthKit Errors Silently Swallowed
**File:** `Shift/Services/WorkoutService.swift:90-97`
**Issue:** Every line uses `try?`:
```swift
let eIds = (try? await SessionSetRepository.findExerciseIds(...)) ?? []
let exerciseMap = (try? await ExerciseRepository.findByIds(eIds)) ?? [:]
try? await HealthKitService.saveWorkout(...)
```
If HealthKit save fails, the user has no idea. The workout is never synced to Health.

#### 3.3 HealthKit Authorization Doesn't Verify Permission Granted
**File:** `Shift/Services/HealthKitService.swift:46-49`
**Issue:** `requestAuthorization()` succeeds even if the user denies. Subsequent HealthKit calls silently fail. `isAvailable` only checks hardware capability, not permission status.
**Fix:** Check `authorizationStatus(for:)` after requesting.

#### 3.4 Personal Best Stats Only Track Filtered Range
**File:** `Shift/Services/ExerciseHistoryService.swift:121-152`
**Issue:** Variables named `allTimeMaxWeight`, `allTimeMax1RM`, `allTimeMaxVolume` only accumulate from the `filtered` dataset. If user selects "3M" filter, "all-time" bests are actually "3-month" bests. The label says "Heaviest single lift" which implies all-time.
**Fix:** Compute personal bests from `allHistory`, not `filtered`.

### HIGH

#### 3.5 resumeSession Has No Error Handling
**File:** `Shift/Services/WorkoutService.swift:103-110`
**Issue:** If `SessionRepository.setEndedAt()` fails, the enqueue still happens, and the notification is scheduled. Local state diverges from mutation queue.

#### 3.6 deleteSet Renumbering Not Atomic
**File:** `Shift/Services/WorkoutService.swift:279-285`
**Issue:** If the delete succeeds but renumbering fails partway through, set numbers have gaps. Each renumber also enqueues a mutation, so partial failure leaves the mutation queue with inconsistent state.

#### 3.7 Profile Settings Encoding Failure Silently Discarded
**File:** `Shift/Services/ProfileService.swift:52-53`
**Issue:**
```swift
let settingsData = (try? JSONEncoder().encode(profile.settings)) ?? Data()
let settingsDict = (try? JSONSerialization.jsonObject(with: settingsData)) as? [String: Any]
```
If encoding fails, `settingsData` is empty `Data()`. Then `JSONSerialization` fails silently. `settingsDict` becomes nil. Profile update proceeds without settings, silently losing them.

#### 3.8 Weight Entry Service: No Validation
**File:** `Shift/Services/WeightEntryService.swift:10-13`
**Issue:** No validation that weight is positive, not absurdly large, or that `recordedAt` is not in the future. Invalid entries propagate to database and HealthKit.

### MEDIUM

#### 3.9 Module-Level authManager Not Thread-Safe
**File:** `Shift/Services/WorkoutService.swift:410-424`
**Issue:** `_authManager` is a module-level optional variable with no synchronization. Read/write from multiple async contexts is technically a data race.

#### 3.10 authManager fatalError on Missing Setup
**File:** `Shift/Services/WorkoutService.swift:413-419`
**Issue:** If `setAuthManager()` wasn't called before any service function runs, the app crashes with `fatalError`. Edge case: background task or notification handler triggers service before app fully launches.

#### 3.11 No Logging Anywhere in Service Layer
**File:** All service files
**Issue:** Zero calls to `os_log`, `Logger`, or `print` for diagnostics. When things fail silently (and many things do - see all the `try?` calls), there is no way to diagnose production issues.

---

## 4. UI Views & Components

### HIGH

#### 4.1 Progress Calculation Bug in ProfileView
**File:** `Shift/Views/Profile/ProfileView.swift:533`
**Issue:** Goal progress ring always shows baseline weight instead of actual current max weight. The `currentMax` lookup returns `baselineWeight` regardless of actual progress. Progress rings are incorrect.

#### 4.2 Same Progress Bug in ExerciseGoalsView
**File:** `Shift/Views/Exercises/ExerciseGoalsView.swift:99-103`
**Issue:** Same flawed progress calculation as ProfileView. Goal cards show wrong progress.

#### 4.3 ActivityDetailView Silent Failure
**File:** `Shift/Views/Today/ActivityDetailView.swift:248`
**Issue:** If `HealthKitService.fetchActivity()` fails, UI silently falls back to `ActivityData()` showing all zeros. No error message, no retry option. User thinks they had no activity.

#### 4.4 WeightDetailView Silent Error Handling
**File:** `Shift/Views/Profile/WeightDetailView.swift:287`
**Issue:** Multiple `try?` calls silently swallow errors. Weight data may fail to load with no user feedback.

#### 4.5 Hardcoded Weight Conversion
**File:** `Shift/Views/Profile/WeightDetailView.swift:419`
**Issue:** `hkWeightKg * 2.20462` hardcoded instead of using centralized `convertWeight()` from Format.swift. If conversion factor changes or other units are added, this won't be updated.

### MEDIUM

#### 4.6 Missing Input Validation in ExerciseLogView
**File:** `Shift/Views/Workout/ExerciseLogView.swift:190-210`
**Issue:** `addSet()` accepts reps=0 and weight=0/nil without validation. Users can log meaningless sets.

#### 4.7 Force Unwrap in PlanSheets
**File:** `Shift/Views/Plans/PlanSheets.swift:157`
**Issue:** `Text(chip.0!)` force unwraps without safety check. Could crash if nil chip passes the filter.

#### 4.8 Missing Empty State for HealthKit Activity Card
**File:** `Shift/Views/Today/TodayView.swift:80-89`
**Issue:** Activity card is hidden when `activityData == nil` with no indication why. If HealthKit is disabled, user sees nothing and doesn't know to enable it.

#### 4.9 Settings View No Input Validation
**File:** `Shift/Views/Settings/SettingsView.swift:256-296`
**Issue:** Profile settings page accepts empty name, any string for age (fails to Int silently), and any photo without size/format validation.

### LOW

#### 4.10 Missing Accessibility Labels
**Issue:** Many icon-only buttons lack accessibility labels throughout the app (TodayView, ProfileView, SettingsView). Screen readers can't announce their purpose.

#### 4.11 Duplicate Duration Formatting
**File:** `Shift/Views/Workout/WorkoutView.swift:278` + `Shift/Views/Settings/SettingsView.swift:517`
**Issue:** Two separate implementations of duration formatting. Should use shared utility.

---

## 5. Summary

### Issue Count by Severity

| Severity | Data Layer | Notifications | Services | UI | Total |
|----------|-----------|---------------|----------|-----|-------|
| Critical | 10 | 3 | 4 | 0 | **17** |
| High | 3 | 3 | 4 | 5 | **15** |
| Medium | 0 | 2 | 3 | 4 | **9** |
| Low | 0 | 0 | 0 | 2 | **2** |
| **Total** | **13** | **8** | **11** | **11** | **43** |

### Top Priority Fixes (ordered by impact)

1. **Personal bests calculated from filtered range instead of all-time** (3.4) - users see wrong stats
2. **Live Activity race condition leaving zombie activities** (2.1) - stuck Dynamic Island
3. **Silent data loss on malformed mutations** (1.1) - permanent data loss
4. **Mutation queue blocks forever on first failure** (1.2) - all sync stops
5. **Timer doesn't handle background correctly** (2.2) - wrong countdown on resume
6. **finishSession background work not awaited** (3.1) - goals/HealthKit silently lost
7. **Missing cascade deletes** (1.4, 1.5, 1.6) - orphaned records accumulate
8. **HealthKit errors silently swallowed** (3.2) - workouts never sync to Health
9. **Goal progress rings showing wrong data** (4.1, 4.2) - UI shows incorrect progress
10. **Non-atomic local write + enqueue** (1.10) - data divergence on crash
