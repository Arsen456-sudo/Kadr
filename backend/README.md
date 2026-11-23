# Kadr social API and feature synchronization

The app runs offline by default. The server is a development backend and is not
deployed by the iOS build. No network URL or credentials are embedded in the IPA.

## Integration point

`LocalStore.services` is the shared `AppServices` instance used by social screens.
After verifying an Apple/Google account and establishing its server UUID, call
`store.services.configure(serverURL:token:)` with an HTTPS base URL and an async,
refreshable bearer-token provider. The selected local profile UUID must match the
authenticated server identity. Existing local developer accounts require an
explicit identity-preserving migration; changing a username is not authentication.

`FeatureSyncEngine` transfers profiles, public profile appearance, posts, private
drafts, comments, comment interactions, post reactions, follows, messages, message
interactions, and private account preferences/history/collections. Original media
is uploaded as a file, without transcoding. Downloads are cached locally for
AVFoundation and the photo viewer. Public data and participant-only chat data are
filtered independently. Resource upserts are idempotent and deletion uses tombstones.
The UI continues to read `LocalStore`; it does not need a second set of screens.

## Local server

Python 3.11+ and its standard library are sufficient. Set `KADR_AUTH_SECRET` to a
random secret containing at least 32 characters. It must never be committed.

```
python social_server.py --create-user nickname "Display name"
python social_server.py --host 127.0.0.1 --port 8080
```

The administrative create-user command prints the UUID and a one-day development
session. `--user-id UUID` preserves an existing developer account's UUID. There is
no public endpoint that issues arbitrary user sessions. Replace development session
provisioning with verified identity-provider sessions before enabling online accounts.
Use an HTTPS reverse proxy when connecting an iPhone; the client rejects plain HTTP.

SQLite state and uploaded assets are excluded from Git. Back up the database and
assets together. The iPhone's export/restore feature is independent of this database.

## API

All endpoints require an authenticated session.

| Method | Path | Purpose |
|---|---|---|
| GET | `/users?handle=prefix` | Username-prefix search |
| PUT / DELETE | `/users/{id}/follow` | Follow / unfollow |
| GET | `/conversations` | Authenticated user's conversations |
| GET / POST | `/conversations/{id}/messages` | Participant messages / idempotent send |
| POST | `/sync` | Batches of up to 50 typed resource upserts |
| GET | `/sync?after=cursor` | Authorized resource changes |
| PUT | `/assets/{filename}` | Original media upload |
| HEAD / GET | `/assets/{filename}` | Authorized existence check / download |

The two client adapters have separate roles. `RemoteSocialRepository` represents
direct social REST calls. `AppServices` uses the snapshot/resource synchronization
adapter so the existing local UI, drafts, and extended metadata remain available.

## Verification status

The backend has a syntax compilation check. It has not been deployed, load-tested,
or exercised with a real Apple/Google session. The 70-item implementation register
is [here](../ios/ROADMAP-0.5.0.md). A successful IPA build is a compilation result,
not a claim that every interaction was exercised on an iPhone.
