# CloudKit Schema — phone-auth redesign

Container: `iCloud.com.otishlau.screenmates`  
Target environment: **Development** (deploy to Production only after full validation)

---

## Changes overview

| Record type | Action |
|---|---|
| `UserProfile` | Modify — add phone/auth fields, deprecate `group_id` |
| `Friendship` | Create new |
| `SocialGroup` | No changes — stop writing, leave readable |
| `Users` | Unused — can delete when convenient |
| `ScreenEvent` | No changes |

---

## `UserProfile` — modified

Add the following fields:

```
phone_hash             STRING QUERYABLE SEARCHABLE SORTABLE
auth_provider_user_id  STRING QUERYABLE
phone_verified_at      TIMESTAMP QUERYABLE SORTABLE
personal_goal_minutes  INT64
```

Deprecate (stop writing new values, leave existing records readable):

```
group_id
minutes_used
```

Full target DDL:

```
RECORD TYPE UserProfile (
    "___createTime"        TIMESTAMP,
    "___createdBy"         REFERENCE,
    "___etag"              STRING,
    "___modTime"           TIMESTAMP,
    "___modifiedBy"        REFERENCE,
    "___recordID"          REFERENCE,
    auth_provider_user_id  STRING QUERYABLE,
    blocks_used            INT64 SORTABLE,
    display_name           STRING,
    group_id               STRING QUERYABLE,
    last_active_date       TIMESTAMP,
    last_updated           TIMESTAMP,
    minutes_used           INT64 QUERYABLE,
    personal_goal_minutes  INT64,
    phone_hash             STRING QUERYABLE SEARCHABLE SORTABLE,
    phone_verified_at      TIMESTAMP QUERYABLE SORTABLE,
    post_midnight_blocks   INT64 QUERYABLE SORTABLE,
    streak                 INT64,
    user_id                STRING QUERYABLE,
    GRANT WRITE TO "_creator",
    GRANT READ, CREATE, WRITE TO "_icloud",
    GRANT READ TO "_world"
);
```

---

## `Friendship` — new record type

```
RECORD TYPE Friendship (
    "___createTime"      TIMESTAMP,
    "___createdBy"       REFERENCE,
    "___etag"            STRING,
    "___modTime"         TIMESTAMP,
    "___modifiedBy"      REFERENCE,
    "___recordID"        REFERENCE,
    requester_user_id    STRING QUERYABLE SORTABLE,
    recipient_user_id    STRING QUERYABLE SORTABLE,
    status               STRING QUERYABLE SORTABLE,
    created_at           TIMESTAMP SORTABLE,
    updated_at           TIMESTAMP SORTABLE,
    requester_phone_hash STRING QUERYABLE,
    recipient_phone_hash STRING QUERYABLE,
    GRANT WRITE TO "_creator",
    GRANT READ, CREATE, WRITE TO "_icloud",
    GRANT READ TO "_world"
);
```

Allowed `status` values: `pending`, `accepted`, `rejected`, `removed`

---

## Required indexes

### `UserProfile`
- `user_id` — QUERYABLE (already exists)
- `phone_hash` — QUERYABLE, SEARCHABLE, SORTABLE (new)
- `auth_provider_user_id` — QUERYABLE (new)
- `phone_verified_at` — QUERYABLE, SORTABLE (new)

### `Friendship`
- `requester_user_id` — QUERYABLE, SORTABLE
- `recipient_user_id` — QUERYABLE, SORTABLE
- `status` — QUERYABLE, SORTABLE
- `created_at` — SORTABLE
- `updated_at` — SORTABLE

---

## Subscription changes

Replace group-based subscriptions with:

1. **Incoming friend requests** — `Friendship` where `recipient_user_id == currentUser` AND `status == pending`
2. **Accepted friendships** — `Friendship` where `requester_user_id == currentUser` OR `recipient_user_id == currentUser` AND `status == accepted`
3. **Friend profile updates** — `UserProfile` where `user_id IN [acceptedFriendIDs]`

Avoid subscription loops: do not trigger a subscription on writes the current user initiated.

---

## Migration plan

1. Apply schema changes to **Development** in CloudKit Dashboard.
2. Validate record creation, queries, indexes, and subscriptions in Development.
3. Stop writing `SocialGroup` records in app code (Task 1 owns routing change).
4. Stop requiring `group_id` before dashboard is shown (Task 1 owns routing change).
5. Leave existing `SocialGroup` and `group_id` data untouched.
6. Deploy schema to **Production** only after the app build no longer depends on the old group model.

---

## Handoff notes

- **Task 1**: identity fields are `auth_provider_user_id` (Twilio Verify SID), `phone_hash` (SHA-256 of E.164 number), `phone_verified_at` (timestamp of successful OTP), `user_id` (CKRecord name)
- **Task 3**: friends leaderboard queries `UserProfile` by `user_id IN [acceptedFriendIDs]` — get accepted friend IDs from `Friendship` where status == accepted and current user is requester or recipient
- **Task 4**: user-visible terms — "phone verification", "friends", "friend request", "connected"
