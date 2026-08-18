# Ocean Cast API

PHP 8.2+ / MySQL 8+ REST API for the Ocean Cast iOS app. No framework, no
Composer dependencies — plain PHP, PDO and prepared statements.

The app stays **offline-first**: local records work without a network, and the
API reconciles them. Sync never invents data and never silently drops a change.

---

## 1. Install

```bash
cd server
cp .env.example .env
php -r "echo bin2hex(random_bytes(32)), PHP_EOL;"   # paste into APP_KEY
mysql -u root -e "CREATE DATABASE oceancast CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;"
php tools/migrate.php
```

Point the web server's document root at `server/public/`. Everything else —
`src/`, `.env`, `migrations/`, `storage/` — must stay **outside** the document
root.

**Shared hosting (Hostinger, cPanel) — one document root for everything.**
Upload the *contents* of `server/` into `public_html`. The `.htaccess` in this
folder routes every request to `public/index.php`, forwards the `Authorization`
header (CGI strips it otherwise, which answers 401 on every call), forces HTTPS
and denies `src/`, `migrations/`, `database/`, `tools/`, `storage/` and `.env`.
Import `database/oceancast_full.sql` through phpMyAdmin instead of running the
migration tool. Step-by-step: **[DEPLOY-HOSTINGER.md](DEPLOY-HOSTINGER.md)**.

`public/.htaccess` covers a classic Apache vhost; for nginx:

```nginx
root /var/www/oceancast/server/public;
location / { try_files $uri /index.php$is_args$args; }
location ~ \.php$ {
    include fastcgi_params;
    fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    fastcgi_param SCRIPT_FILENAME $document_root/index.php;
}
```

Run hourly from cron:

```bash
php /var/www/oceancast/server/tools/cleanup.php
```

Verify a deployment end to end (creates and deletes throwaway accounts):

```bash
php tools/smoke_test.php https://api.example.com
```

```bash
./tools/contract-test/run.sh https://api.example.com
```

Both suites were also run through a real Apache with PHP over CGI, against the
`.htaccess` in this folder and the layout shared hosting produces — that is what
proves the bearer token survives the rewrite.

The first covers the API and its security behaviour (67 checks). The second
compiles the **iOS app's own models and coders** and drives the live API with
them (44 checks), so the Swift ↔ PHP wire format is proven rather than assumed.

Local development:

```bash
php -S 127.0.0.1:8791 -t public     # set FORCE_HTTPS=false in .env first
```

---

## 2. Security model

**Transport.** `FORCE_HTTPS=true` refuses plain HTTP outright; HSTS is sent on
every response. The app's ATS settings forbid cleartext on the client side too.

**Passwords.** Argon2id (64 MiB / t=4 / p=2 by default), never logged, never
returned. Cost is configurable and hashes are upgraded on the next successful
login when the cost changes. A login against an unknown address still burns a
verification so timing does not reveal which addresses exist.

**Tokens.** Opaque, 256 bits from the CSPRNG, prefixed `sb_at_` / `sb_rt_`.
Only SHA-256 hashes are stored — a database dump cannot be replayed. Access
tokens live 1 hour, refresh tokens 30 days and **rotate on every use**.
Presenting an already-rotated refresh token is treated as theft: the whole token
family is revoked immediately and the event is written to the audit log.

**Every request** to anything outside `/v1/health` and the three public auth
endpoints requires `Authorization: Bearer <access token>`. There are no session
cookies, so CSRF does not apply; CORS is closed unless an origin is explicitly
allow-listed.

**Isolation.** Every household-scoped query carries `household_id = :household`,
derived from the token — never from the request. One account cannot read or
write another's rows, and claiming somebody else's household UUID returns 403.

**Injection.** `PDO::ATTR_EMULATE_PREPARES = false`, so statements are prepared
by MySQL and user input is never parsed as SQL. Table and column names come from
the schema definition in `src/Domain/Schema.php`, never from a request.

**Input.** Whitelist validation per field (type, length, range, pattern, enum).
Unknown keys are dropped, so there is no mass assignment. Bodies are capped at
4 MB and JSON depth at 32.

**Brute force.** Fixed-window limits per IP, per account and per token, plus a
15-minute account lock after 8 failed logins. Limits are configurable in `.env`.

**Auditing.** `security_events` records registrations, logins, failures, token
refreshes, reuse detection, password changes, exports and deletions — with
HMAC-hashed IPs, never raw addresses, tokens or passwords.

**Errors.** Production returns a generic message plus a stable `error.code`;
stack traces go to the log only.

**Deletion.** `DELETE /v1/profile` requires the password **and** `confirm:
"DELETE"`, revokes every session and hard-deletes the account. Foreign keys
cascade, so households, batches, meals, shopping, prices, activity and recall
decisions all go with it. The response reports what was removed.

---

## 3. Endpoints

All paths are prefixed `/v1`. Request and response bodies are JSON.

### Public

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | liveness probe |
| POST | `/auth/register` | create an account → user + tokens |
| POST | `/auth/login` | sign in → user + tokens |
| POST | `/auth/refresh` | rotate a refresh token → new pair |

### Authenticated (`Authorization: Bearer …`)

| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/logout` | revoke the current session |
| POST | `/auth/logout-all` | revoke every session |
| GET | `/auth/sessions` | list active sessions (device, platform, last use) |
| DELETE | `/auth/sessions/{id}` | revoke one session |
| GET | `/profile` | account, household summary, record counts |
| PATCH | `/profile` | change display name; email change requires the password |
| POST | `/profile/password` | change password (revokes other sessions) |
| GET | `/profile/export` | full JSON export of everything stored |
| DELETE | `/profile` | delete the account (password + `confirm: "DELETE"`) |
| GET / PUT / DELETE | `/household` | the household singleton |
| GET / PUT | `/settings` | per-user app settings blob |
| POST | `/sync` | bulk push + delta pull |

### Resources

`zones`, `members`, `batches`, `meals`, `reservations`, `shopping-items`,
`prices`, `activity`, `recall-alerts`, `recall-matches`, `archived-alerts`,
`thresholds` — each with the same six operations:

```
GET    /v1/{resource}              ?since=&limit=&offset=&includeDeleted=
POST   /v1/{resource}              create (409 if the id already exists)
GET    /v1/{resource}/{id}
PUT    /v1/{resource}/{id}         create or replace (idempotent)
PATCH  /v1/{resource}/{id}         partial update
DELETE /v1/{resource}/{id}         soft delete → tombstone for other devices
```

Identity is the UUID the app already generated, so a record created offline
keeps the same id on the server. `recall-alerts` and `archived-alerts` are keyed
by the official notice id; `thresholds` by product key.

### Headers

| Header | Meaning |
|---|---|
| `Authorization: Bearer …` | required on every authenticated route |
| `Idempotency-Key: <8–64 chars>` | POST retries return the first response instead of duplicating |
| `X-Device-Name`, `X-Platform` | shown in the session list |

### Errors

```json
{ "error": { "code": "validation_failed",
             "message": "Some fields need attention.",
             "fields": { "quantity": "Must be between 0 and 1000000." } } }
```

Codes: `validation_failed`, `unauthorized`, `missing_token`, `invalid_token`,
`token_expired`, `token_revoked`, `token_reuse_detected`, `refresh_expired`,
`invalid_credentials`, `account_inactive`, `forbidden`, `not_found`,
`already_exists`, `email_unavailable`, `household_required`, `rate_limited`,
`payload_too_large`, `server_error`.

---

## 4. Sync protocol

```jsonc
POST /v1/sync
{
  "since": "2026-08-12T14:56:51.036035Z",   // cursor from the previous response
  "household": { "id": "…", "name": "…", "currencyCode": "USD" },   // optional
  "settings":  { … },                                               // optional
  "changes": { "batches": [ { …record… } ], "meals": [ … ] }
}
```

```jsonc
{
  "serverTime": "2026-08-12T15:02:11.884120Z",  // store as the next cursor
  "household": { … },
  "settings":  { … },
  "applied":   { "batches": 3 },
  "rejected":  [ { "resource": "batches", "id": "…", "reason": "…", "fields": {…} } ],
  "changes":   { "batches": [ … ], "meals": [ … ] },   // everything after `since`
  "hasMore":   false
}
```

* Push first, pull second, in one round trip.
* A record sent with `deletedAt` becomes a tombstone, so deletes propagate.
* **Conflicts:** if a pushed record changed on the server *after* the client's
  cursor, another device edited it first. The server keeps its version, lists the
  record under `conflicts`, and returns the server copy in the same `changes`
  block. A stale client can never silently overwrite a newer edit.
* Otherwise the incoming record wins. The server stamps `updatedAt` itself with
  microsecond precision, and the cursor is opaque — echo it back unchanged.
* Rejected records are reported per record with the reason. The rest still
  applies; a single bad row never fails the whole sync.
* Limits: 500 records per resource per push, 500 per resource per pull
  (`hasMore` tells the client to sync again).

---

## 4a. iOS client

> The product is **Ocean Cast** — that is the name on the home screen, in every
> screen of the app and in this API. The Xcode project, its target and the source
> folder are still called `SugarBloom`; those are internal identifiers, so the
> paths below keep the old spelling until the project itself is renamed.

| Piece | Where |
|---|---|
| Networking, refresh-on-401, error mapping | `SugarBloom/Services/API/APIClient.swift` |
| Wire types and coders | `SugarBloom/Services/API/APIModels.swift` |
| Token storage (Keychain) | `SugarBloom/Services/API/KeychainStore.swift` |
| Session state | `SugarBloom/Services/API/AuthStore.swift` |
| Push/pull/merge | `SugarBloom/Services/API/SyncService.swift` |
| Sign in / register | `SugarBloom/Features/Auth/AuthView.swift` |
| Profile, devices, deletion | `SugarBloom/Features/Profile/ProfileView.swift` |

The server address is set in the app under **Settings → Account & Sync** (or on
the sign-in screen) and defaults to `http://127.0.0.1:8791` for local work.
A Simulator reaches a loopback address without any ATS exception; any other host
must be HTTPS, and the client reports a refused cleartext connection instead of
failing silently.

Client-side behaviour worth knowing:

* Tokens live in the Keychain with `ThisDeviceOnly` — never in `UserDefaults`,
  never in a backup. The first launch after a reinstall purges them, so a
  reinstalled app cannot resume somebody else's session.
* One access-token refresh is performed transparently and serialised, so ten
  parallel calls trigger one refresh, not ten.
* Local deletes are recorded as tombstones and replayed on the next sync.
* Sync runs at launch and when the app returns to the foreground. Being offline
  is a status, not an error: local records keep working and sync later.

---

## 5. Layout

```
server/
├── public/index.php        front controller (routing, auth, idempotency)
├── src/
│   ├── bootstrap.php       autoloader, error handling, hardening
│   ├── Core/               Config, Database, Request, Response, Router, Validator, Uuid
│   ├── Security/           Passwords, TokenService, RateLimiter, AuditLog
│   ├── Domain/             Schema (field definitions), ResourceRepository
│   └── Http/               Auth context + controllers
├── migrations/001_init.sql  applied by tools/migrate.php
├── database/               oceancast_full.sql — one-file import for phpMyAdmin
├── tools/                  migrate.php, cleanup.php, smoke_test.php,
│                           build_full_sql.php, contract-test/
├── .htaccess               document-root routing + lockdown (shared hosting)
└── .env                    never commit this
```
