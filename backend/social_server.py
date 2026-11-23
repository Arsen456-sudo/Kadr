"""Kadr development social API, Python 3.11+, SQLite, no third party dependencies.

Set KADR_AUTH_SECRET to a random secret of at least 32 characters, then run:
  python social_server.py --create-user nickname 'Display name'
  python social_server.py --port 8080
Provisioning prints a short-lived bearer session for that user. This is an admin
development command, not a public authentication endpoint. Production must issue
sessions only after verifying Apple/Google credentials and terminate HTTPS at the
reverse proxy. RemoteSocialRepository accepts that HTTPS URL and a token provider.
The iOS app continues to use LocalSocialRepository until account sync is enabled.
"""

import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import sqlite3
import time
import uuid
import binascii
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


class APIError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


def canonical_id(value):
    try:
        return str(uuid.UUID(value))
    except (ValueError, TypeError, AttributeError):
        raise APIError(400, "Некоректний ідентифікатор.")


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


class SocialService:
    def __init__(self, database, secret):
        self.database, self.secret = str(database), secret.encode()
        with self.connect() as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS profiles (
                    id TEXT PRIMARY KEY, handle TEXT NOT NULL UNIQUE COLLATE NOCASE,
                    name TEXT NOT NULL, bio TEXT NOT NULL DEFAULT ''
                );
                CREATE TABLE IF NOT EXISTS follows (
                    follower TEXT NOT NULL REFERENCES profiles(id),
                    followed TEXT NOT NULL REFERENCES profiles(id),
                    PRIMARY KEY(follower, followed), CHECK(follower != followed)
                );
                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY,
                    sender TEXT NOT NULL REFERENCES profiles(id),
                    recipient TEXT NOT NULL REFERENCES profiles(id),
                    text TEXT NOT NULL CHECK(length(text) BETWEEN 1 AND 4000),
                    created TEXT NOT NULL, CHECK(sender != recipient)
                );
                CREATE TABLE IF NOT EXISTS sync_records (
                    owner TEXT NOT NULL REFERENCES profiles(id), resource TEXT NOT NULL,
                    entity TEXT NOT NULL, payload TEXT NOT NULL, version INTEGER NOT NULL,
                    PRIMARY KEY(owner, resource, entity)
                );
                CREATE TABLE IF NOT EXISTS sync_sequence (id INTEGER PRIMARY KEY AUTOINCREMENT);
                CREATE TABLE IF NOT EXISTS assets (name TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES profiles(id));
                CREATE INDEX IF NOT EXISTS sync_records_version ON sync_records(version);
                CREATE INDEX IF NOT EXISTS messages_pair ON messages(sender, recipient, created);
                CREATE INDEX IF NOT EXISTS messages_recipient ON messages(recipient, created);
            """)

            if "metadata" not in {row["name"] for row in db.execute("PRAGMA table_info(messages)")}:
                db.execute("ALTER TABLE messages ADD COLUMN metadata TEXT")

    def connect(self):
        db = sqlite3.connect(self.database, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        return db

    def issue_session(self, user):
        body = b64(json.dumps({"sub": user, "exp": int(time.time()) + 86400}, separators=(",", ":")).encode())
        return (body + b"." + b64(hmac.digest(self.secret, body, "sha256"))).decode()

    def authenticate(self, header):
        try:
            scheme, token = header.split(" ", 1)
            if scheme.lower() != "bearer" or len(token) > 2048:
                raise ValueError()
            body, signature = token.encode().split(b".", 1)
            if not hmac.compare_digest(signature, b64(hmac.digest(self.secret, body, "sha256"))):
                raise ValueError()
            claims = json.loads(base64.urlsafe_b64decode(body + b"=" * (-len(body) % 4)))
            if not isinstance(claims["exp"], (int, float)) or claims["exp"] <= time.time():
                raise ValueError()
            user = canonical_id(claims["sub"])
            with self.connect() as db:
                if db.execute("SELECT id FROM profiles WHERE id=?", (user,)).fetchone() is None:
                    raise ValueError()
            return user
        except (ValueError, KeyError, TypeError, APIError):
            raise APIError(401, "Увійди знову. Сесія недійсна або завершилася.")

    @staticmethod
    def message(row):
        return {"id": row["id"], "senderID": row["sender"], "recipientID": row["recipient"],
                "text": row["text"], "createdAt": row["created"], **(json.loads(row["metadata"]) if "metadata" in row.keys() and row["metadata"] else {})}

    def sync(self, user, method, query, body):
        allowed = {"profile", "appearance", "post", "draft", "comment", "reaction", "following", "message", "preferences", "messageReaction", "commentReaction", "commentPin"}
        public = {"profile", "appearance", "post", "comment", "reaction", "following", "commentReaction", "commentPin"}
        with self.connect() as db:
            if method == "POST":
                if not isinstance(body, list) or len(body) > 50:
                    raise APIError(400, "Некоректний пакет синхронізації.")
                for record in body:
                    if not isinstance(record, dict) or canonical_id(record.get("owner")) != user:
                        raise APIError(403, "Не можна змінювати чужі дані.")
                    kind, key, encoded = record.get("resource"), record.get("entityID"), record.get("payload")
                    if kind not in allowed or not isinstance(key, str) or not 1 <= len(key) <= 150 or not isinstance(encoded, str):
                        raise APIError(400, "Некоректний ресурс.")
                    try:
                        raw = base64.b64decode(encoded, validate=True)
                        if len(raw) > 1024 * 1024:
                            raise ValueError()
                        value = json.loads(raw)
                        if not isinstance(value, dict):
                            raise ValueError()
                    except (ValueError, binascii.Error):
                        raise APIError(400, "Некоректні дані ресурсу.")
                    deleted = value.get("deleted") is True
                    existing = db.execute("SELECT payload FROM sync_records WHERE owner=? AND resource=? AND entity=?", (user, kind, key)).fetchone()
                    if deleted and existing is None:
                        continue
                    if deleted and kind == "message":
                        previous = json.loads(existing["payload"])
                        value["recipientID"] = previous.get("recipientID")
                        value["senderID"] = previous.get("senderID")
                        db.execute("DELETE FROM messages WHERE id=? COLLATE NOCASE AND sender=?", (key, user))
                    if not deleted:
                        if kind == "profile" and canonical_id(value.get("id")) != user:
                            raise APIError(403, "Невірний власник профілю.")
                        if kind in ("post", "draft") and (canonical_id(value.get("authorID")) != user or value.get("id") != key):
                            raise APIError(403, "Невірний автор публікації.")
                        if kind == "comment":
                            comment = value.get("comment", {})
                            if canonical_id(comment.get("authorID")) != user or comment.get("id") != key:
                                raise APIError(403, "Невірний автор коментаря.")
                        if kind == "messageReaction":
                            message_id = value.get("messageID")
                            message = db.execute("SELECT payload FROM sync_records WHERE resource='message' AND entity=? COLLATE NOCASE", (message_id,)).fetchone()
                            parent = json.loads(message["payload"]) if message else {}
                            if user not in (str(parent.get("senderID", "")).lower(), str(parent.get("recipientID", "")).lower()) or not isinstance(value.get("emoji"), str) or len(value["emoji"]) > 32:
                                raise APIError(403, "Немає доступу до реакції.")
                        if kind == "commentPin":
                            post = db.execute("SELECT owner FROM sync_records WHERE resource='post' AND entity=?", (value.get("postID"),)).fetchone()
                            if not post or post["owner"] != user: raise APIError(403, "Закріплювати може тільки автор публікації.")
                        if kind == "message":
                            recipient = canonical_id(value.get("recipientID"))
                            text = value.get("text")
                            if not isinstance(text, str) or not 1 <= len(text.strip()) <= 4000: raise APIError(400, "Некоректний текст повідомлення.")
                            if canonical_id(value.get("senderID")) != user or value.get("id") != key or recipient == user:
                                raise APIError(403, "Невірний відправник.")
                            followed = db.execute("SELECT 1 FROM follows WHERE follower=? AND followed=?", (user, recipient)).fetchone()
                            prior = db.execute("SELECT 1 FROM messages WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?) LIMIT 1", (user, recipient, recipient, user)).fetchone()
                            settings = db.execute("SELECT payload FROM sync_records WHERE owner=? AND resource='preferences'", (recipient,)).fetchone()
                            preferences = json.loads(settings["payload"]).get("preferences", {}) if settings else {}
                            if user in [str(item).lower() for item in preferences.get("blocked", [])]:
                                raise APIError(403, "Користувач не приймає повідомлення.")
                            if not prior:
                                prior = db.execute("SELECT 1 FROM sync_records WHERE resource='message' AND ((lower(json_extract(payload,'$.senderID'))=? AND lower(json_extract(payload,'$.recipientID'))=?) OR (lower(json_extract(payload,'$.senderID'))=? AND lower(json_extract(payload,'$.recipientID'))=?)) LIMIT 1", (user, recipient, recipient, user)).fetchone()
                            if preferences.get("messagePermission") == "nobody" and not prior:
                                raise APIError(403, "Користувач не приймає нові повідомлення.")
                            if not followed and not prior and preferences.get("messagePermission") != "everyone":
                                raise APIError(403, "Підпишись на користувача, щоб почати чат.")
                        if kind == "following":
                            ids = value.get("ids", [])
                            if not isinstance(ids, list): raise APIError(400, "Некоректні підписки.")
                            normalized = [canonical_id(item) for item in ids]
                            db.execute("DELETE FROM follows WHERE follower=?", (user,))
                            for peer in normalized:
                                if peer != user and db.execute("SELECT 1 FROM profiles WHERE id=?", (peer,)).fetchone():
                                    db.execute("INSERT OR IGNORE INTO follows VALUES (?,?)", (user, peer))
                        if kind == "profile":
                            handle = value.get("handle", "").lower()
                            if not re.fullmatch(r"[a-z0-9_]{3,24}", handle) or not isinstance(value.get("name"), str):
                                raise APIError(400, "Некоректний профіль.")
                            taken = db.execute("SELECT id FROM profiles WHERE handle=? COLLATE NOCASE AND id!=?", (handle, user)).fetchone()
                            if taken: raise APIError(409, "Нікнейм уже зайнято.")
                            db.execute("UPDATE profiles SET handle=?,name=?,bio=? WHERE id=?", (handle, value["name"][:200], str(value.get("bio", ""))[:4000], user))
                    if kind == "message" and not deleted:
                        moment = value.get("createdAt", 0)
                        created = (datetime(2001, 1, 1, tzinfo=timezone.utc) + timedelta(seconds=moment)).strftime("%Y-%m-%dT%H:%M:%SZ") if isinstance(moment, (int, float)) else str(moment)
                        metadata = {key: value[key] for key in ("replyTo", "reactions", "edited", "attachmentFile", "attachmentKind", "postID") if key in value}
                        db.execute("INSERT INTO messages(id,sender,recipient,text,created,metadata) VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET text=excluded.text,metadata=excluded.metadata WHERE messages.sender=excluded.sender", (canonical_id(value["id"]), user, canonical_id(value["recipientID"]), str(value.get("text", ""))[:4000], created, json.dumps(metadata)))
                    canonical = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
                    if existing and existing["payload"] == canonical:
                        continue
                    version = db.execute("INSERT INTO sync_sequence DEFAULT VALUES").lastrowid
                    db.execute("INSERT INTO sync_records VALUES (?,?,?,?,?) ON CONFLICT(owner,resource,entity) DO UPDATE SET payload=excluded.payload,version=excluded.version", (user, kind, key, canonical, version))
                return {"ok": True}
            if method == "GET":
                try: after = max(0, int(query.get("after", ["0"])[0]))
                except ValueError: raise APIError(400, "Некоректний курсор.")
                records = db.execute("SELECT * FROM sync_records WHERE version>? ORDER BY version LIMIT 200", (after,)).fetchall()
                result, cursor = [], after
                for row in records:
                    cursor = row["version"]
                    value = json.loads(row["payload"])
                    kind = row["resource"]
                    permitted = row["owner"] == user or kind in public
                    if kind == "messageReaction":
                        message = db.execute("SELECT payload FROM sync_records WHERE resource='message' AND entity=? COLLATE NOCASE", (value.get("messageID"),)).fetchone()
                        parent = json.loads(message["payload"]) if message else {}
                        permitted = user in (str(parent.get("senderID", "")).lower(), str(parent.get("recipientID", "")).lower())
                    if kind == "message":
                        permitted = row["owner"] == user or (value.get("recipientID", "").lower() == user)
                    if kind == "post" and value.get("options", {}).get("onlyMe") is True and row["owner"] != user:
                        permitted = False
                    if not permitted: continue
                    if kind in ("comment", "reaction", "commentReaction", "commentPin") and row["owner"] != user:
                        post_id = value.get("postID")
                        post = db.execute("SELECT owner,payload FROM sync_records WHERE resource='post' AND entity=?", (post_id,)).fetchone()
                        if post and post["owner"] != user and json.loads(post["payload"]).get("options", {}).get("onlyMe") is True:
                            continue
                    if kind == "reaction" and row["owner"] != user:
                        value["bookmarked"] = False
                    payload = base64.b64encode(json.dumps(value, ensure_ascii=False).encode()).decode()
                    result.append({"owner": row["owner"], "resource": kind, "entityID": row["entity"], "payload": payload})
                return {"records": result, "cursor": cursor}
            raise APIError(405, "Метод не підтримується.")

    def asset_allowed(self, user, name):
        with self.connect() as db:
            row = db.execute("SELECT owner FROM assets WHERE name=?", (name,)).fetchone()
            if not row: raise APIError(404, "Файл не знайдено.")
            if row["owner"] == user: return
            for record in db.execute("SELECT resource,payload FROM sync_records WHERE resource IN ('post','profile','message')"):
                value = json.loads(record["payload"])
                if record["resource"] == "post" and value.get("options", {}).get("onlyMe") is not True and any(item.get("file") == name for item in value.get("media", [])):
                    return
                if record["resource"] == "profile" and value.get("bannerFile") == name: return
                if record["resource"] == "message" and value.get("recipientID", "").lower() == user and value.get("attachmentFile") == name: return
            raise APIError(403, "Немає доступу до файлу.")

    def route(self, user, method, path, query, body):
        parts = path.strip("/").split("/")
        with self.connect() as db:
            if parts == ["users"] and method == "GET":
                term = query.get("handle", [""])[0].strip().lower().lstrip("@")
                if len(term) > 24:
                    raise APIError(400, "Нікнейм надто довгий.")
                # Prefix search treats underscores literally, not as LIKE wildcards.
                escaped = term.replace("\\", "\\\\").replace("_", "\\_").replace("%", "\\%")
                return [dict(row) for row in db.execute(
                    "SELECT id, handle, name, bio FROM profiles WHERE handle LIKE ? ESCAPE '\\' ORDER BY handle LIMIT 100",
                    (escaped + "%",))]
            if len(parts) == 3 and parts[0] == "users" and parts[2] == "follow" and method in ("PUT", "DELETE"):
                peer = canonical_id(parts[1])
                if peer == user:
                    raise APIError(400, "Не можна підписатися на себе.")
                if db.execute("SELECT id FROM profiles WHERE id=?", (peer,)).fetchone() is None:
                    raise APIError(404, "Профіль не знайдено.")
                if method == "PUT":
                    db.execute("INSERT OR IGNORE INTO follows VALUES (?,?)", (user, peer))
                else:
                    db.execute("DELETE FROM follows WHERE follower=? AND followed=?", (user, peer))
                return {"following": method == "PUT"}
            if parts == ["conversations"] and method == "GET":
                rows = db.execute("""
                    SELECT * FROM (
                        SELECT messages.*, ROW_NUMBER() OVER (
                            PARTITION BY CASE WHEN sender=? THEN recipient ELSE sender END
                            ORDER BY created DESC, id DESC) AS rank
                        FROM messages WHERE sender=? OR recipient=?
                    ) WHERE rank=1 ORDER BY created DESC LIMIT 100
                """, (user, user, user)).fetchall()
                result = []
                for row in rows:
                    peer = row["recipient"] if row["sender"] == user else row["sender"]
                    profile = db.execute("SELECT id, handle, name, bio FROM profiles WHERE id=?", (peer,)).fetchone()
                    result.append({"profile": dict(profile), "lastMessage": self.message(row)})
                return result
            if len(parts) == 3 and parts[0] == "conversations" and parts[2] == "messages":
                peer = canonical_id(parts[1])
                if peer == user or db.execute("SELECT id FROM profiles WHERE id=?", (peer,)).fetchone() is None:
                    raise APIError(404, "Профіль не знайдено.")
                pair = (user, peer, peer, user)
                condition = "((sender=? AND recipient=?) OR (sender=? AND recipient=?))"
                if method == "GET":
                    rows = db.execute(f"SELECT * FROM messages WHERE {condition} ORDER BY created DESC, id DESC LIMIT 500", pair).fetchall()
                    return [self.message(row) for row in reversed(rows)]
                if method == "POST":
                    message_id = canonical_id(body.get("id"))
                    text = body.get("text")
                    if not isinstance(text, str) or not 1 <= len(text.strip()) <= 4000:
                        raise APIError(400, "Повідомлення має містити від 1 до 4000 символів.")
                    text = text.strip()
                    # Serialize permission checks and insertion, including simultaneous retries.
                    db.execute("BEGIN IMMEDIATE")
                    existing = db.execute("SELECT * FROM messages WHERE id=?", (message_id,)).fetchone()
                    if existing:
                        if existing["sender"] != user or existing["recipient"] != peer or existing["text"] != text:
                            raise APIError(409, "Ідентифікатор повідомлення вже використано.")
                        return self.message(existing)
                    followed = db.execute("SELECT 1 FROM follows WHERE follower=? AND followed=?", (user, peer)).fetchone()
                    conversation = db.execute(f"SELECT 1 FROM messages WHERE {condition} LIMIT 1", pair).fetchone()
                    if not followed and not conversation:
                        raise APIError(403, "Підпишись на користувача, щоб почати чат.")
                    created = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                    db.execute("INSERT INTO messages(id,sender,recipient,text,created) VALUES (?,?,?,?,?)", (message_id, user, peer, text, created))
                    return {"id": message_id, "senderID": user, "recipientID": peer, "text": text, "createdAt": created}
            raise APIError(404, "Шлях не знайдено.")


class Handler(BaseHTTPRequestHandler):
    def respond(self, status, data):
        payload = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        self.handle_api()

    do_POST = do_PUT = do_DELETE = do_HEAD = do_GET

    def asset(self, user, name):
        if not re.fullmatch(r"[A-Za-z0-9_-]{3,150}\.[A-Za-z0-9]{1,10}", name):
            raise APIError(400, "Некоректна назва файлу.")
        directory = Path(self.server.social.database).resolve().parent / "assets"
        directory.mkdir(exist_ok=True)
        path = directory / name
        if self.command == "PUT":
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 2 * 1024 * 1024 * 1024: raise APIError(413, "Некоректний розмір файлу.")
            with self.server.social.connect() as db:
                row = db.execute("SELECT owner FROM assets WHERE name=?", (name,)).fetchone()
                if row and row["owner"] != user: raise APIError(403, "Не можна перезаписати чужий файл.")
                temporary = directory / (name + "." + uuid.uuid4().hex + ".tmp")
                try:
                    with temporary.open("wb") as output:
                        remaining = length
                        while remaining:
                            chunk = self.rfile.read(min(1024 * 1024, remaining))
                            if not chunk: raise APIError(400, "Завантаження обірвалося.")
                            output.write(chunk); remaining -= len(chunk)
                    temporary.replace(path)
                    db.execute("INSERT OR IGNORE INTO assets VALUES (?,?)", (name, user))
                finally: temporary.unlink(missing_ok=True)
            self.respond(200, {"ok": True}); return
        if self.command in ("GET", "HEAD"):
            self.server.social.asset_allowed(user, name)
            if not path.is_file(): raise APIError(404, "Файл не знайдено.")
            self.send_response(200); self.send_header("Content-Type", "application/octet-stream"); self.send_header("Content-Length", str(path.stat().st_size)); self.send_header("Cache-Control", "private, no-store"); self.send_header("X-Content-Type-Options", "nosniff"); self.end_headers()
            if self.command == "HEAD": return
            with path.open("rb") as source:
                while chunk := source.read(1024 * 1024): self.wfile.write(chunk)
            return
        raise APIError(405, "Метод не підтримується.")

    def handle_api(self):
        try:
            user = self.server.social.authenticate(self.headers.get("Authorization", ""))
            url = urlparse(self.path)
            if url.path.startswith("/assets/"):
                self.asset(user, url.path.removeprefix("/assets/")); return
            if len(self.path) > 2048:
                raise APIError(400, "Запит надто довгий.")
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 <= length <= (16 * 1024 * 1024 if url.path == "/sync" else 32768):
                raise APIError(413, "Запит надто великий.")
            body = json.loads(self.rfile.read(length)) if length else {}
            if url.path == "/sync":
                self.respond(200, self.server.social.sync(user, self.command, parse_qs(url.query), body)); return
            if not isinstance(body, dict):
                raise APIError(400, "Очікується JSON-об’єкт.")
            self.respond(200, self.server.social.route(user, self.command, url.path, parse_qs(url.query), body))
        except APIError as error:
            self.respond(error.status, {"error": error.message})
        except (ValueError, UnicodeDecodeError):
            self.respond(400, {"error": "Некоректний запит."})
        except sqlite3.Error:
            self.respond(503, {"error": "Сховище тимчасово недоступне."})

    def log_message(self, *_):
        pass  # Do not log private handles, tokens, or message text.


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--database", default=str(Path(__file__).with_name("social.sqlite3")))
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--create-user", nargs=2, metavar=("HANDLE", "NAME"))
    args = parser.parse_args()
    secret = os.environ.get("KADR_AUTH_SECRET", "")
    if len(secret) < 32:
        parser.error("Set KADR_AUTH_SECRET to a random secret of at least 32 characters.")
    service = SocialService(args.database, secret)
    if args.create_user:
        handle, name = args.create_user
        handle = handle.lower().lstrip("@")
        if not re.fullmatch(r"[a-z0-9_]{3,24}", handle) or not name.strip():
            parser.error("Use a valid handle (3–24 a-z, 0-9, _) and a nonempty name.")
        user = str(uuid.uuid4())
        with service.connect() as db:
            db.execute("INSERT INTO profiles(id,handle,name) VALUES (?,?,?)", (user, handle, name.strip()))
        print(json.dumps({"id": user, "handle": handle, "token": service.issue_session(user)}))
        return
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.social = service
    server.serve_forever()


if __name__ == "__main__":
    main()
