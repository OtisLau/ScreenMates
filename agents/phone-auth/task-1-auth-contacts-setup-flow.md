# Task 1: Auth, Contacts, And Setup Flow

## Goal

Replace the current group-code setup path with a phone-first onboarding flow that establishes a verified phone identity before friend discovery.

This task owns user setup state, phone verification UX, contacts permission UX, and the first pass at friend discovery screens. It should not redesign the CloudKit schema directly; coordinate schema needs with Task 2.

## Current State

- Setup currently routes through `onboarding -> username -> group -> dashboard`.
- The app uses `CloudKitManager.myGroupID` as the gate before showing the dashboard.
- Phone auth and contacts permission do not exist yet.
- Group join/create UI exists under `screenmates/Views/Group/`.

## Required Flow

Replace setup routing with:

1. Onboarding.
2. Phone number entry.
3. OTP confirmation.
4. Display name, if not already collected.
5. Contacts permission prompt.
6. Matched contacts / friend discovery.
7. Dashboard.

## Deliverables

- Define setup state that can represent:
  - setup not started
  - phone entered
  - OTP pending
  - phone verified
  - display name set
  - contacts permission handled
  - setup complete
- Add or plan UI screens for:
  - phone number entry
  - verification code entry
  - contacts permission explanation
  - matched ScreenMates contacts
  - no matches found
  - contacts permission denied or skipped
- Use a provider-backed OTP flow. Do not treat CloudKit as the SMS verification provider.
- Store verified identity locally with fields that match Task 2:
  - `authProviderUserID`
  - `phoneNumberE164`
  - `phoneHash`
  - `phoneVerifiedAt`
  - `displayName`
  - `userID`
- Request Contacts permission only after phone verification succeeds.
- Normalize contact phone numbers to E.164 where possible before hashing.
- Hash normalized phone numbers before sending them to any discovery query.
- Allow users to continue if they deny contacts or no matches are found.
- Remove group join/create from first-run onboarding.

## Out Of Scope

- Do not implement CloudKit record types or indexes in this task.
- Do not implement leaderboard fetching or notification rules in this task.
- Do not remove every settings/debug group reference; Task 4 owns broad cleanup.

## Acceptance Criteria

- Users cannot enter friend discovery until phone verification succeeds.
- New users do not see create group or join group during setup.
- Contact matches display as local contact name plus ScreenMates display name.
- Denying contacts does not block the user from reaching the dashboard.
- Setup routing no longer depends on `myGroupID`.

## Updated Direction (from build session)

### Username vs generated code
Currently setup collects only a display name (not unique). We need a way for users to find each other outside of contact matching. Two paths:
- **Generated code**: derive a short shareable code from the existing `user_id` (e.g. first 8 chars uppercased). No extra setup step, no uniqueness check needed. User sees their code in settings and can share it.
- **Unique username**: add a username step to setup. Requires a CloudKit uniqueness check before accepting. More friction but more personal.

Decision: start with generated code — simpler, no race conditions, works day one.

### What Task 1 still needs to surface
- The user's shareable friend code (derived from `user_id`) should be visible in Settings
- After contacts discovery, if there are no matches, show an "invite a friend" option that shares the friend link

## UI Style Reference

All new onboarding screens must match the existing pattern:

- **Background**: `AppBackground()` inside a `ZStack`
- **Layout**: `VStack(spacing: 0)` with `Spacer()` elements top and bottom
- **Icon**: SF Symbol, `.font(.system(size: 44, weight: .light)).foregroundStyle(Color.primary.opacity(0.7))`
- **Title**: `.font(.largeTitle).fontWeight(.bold)`
- **Subtitle**: `.font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)`
- **Input fields**: `.glassCard(cornerRadius: AppTheme.cornerRadiusLarge)` with `.padding(.vertical, 18)`
- **Info cards**: `HStack(spacing: 14)` with 36×36 rounded icon square (cornerRadius 8, opacity 0.08) + VStack labels
- **Primary button**: `HStack(spacing: 8)` text + `arrow.right`, `.frame(maxWidth: .infinity).padding(.vertical, 16)`, `.glassProminentButtonStyle()` when active, `.glassButtonStyle()` when inactive
- **Loading state**: swap button content for `SpinnerIcon()` + modified label text
- **Secondary action**: plain `.font(.subheadline).foregroundStyle(.secondary)` button below primary
- **Bottom padding**: `.padding(.horizontal, 24).padding(.bottom, 48)` on the button stack

## Handoff Notes

- Task 2 needs the final identity fields and any provider-specific user ID format.
- Task 3 needs to know when setup is complete so dashboard refresh can begin.
- Task 4 needs the final permission copy and screen names for settings/debug cleanup.
