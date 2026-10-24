"""Reports the app sent to the developer: flags, general feedback and crash
reports in Firestore (``users/{uid}/feedback/`` and ``users/{uid}/crashes/``;
see docs/feedback.md, "Reports to the developer", and firebase/firestore.rules).

Only their sender can read or delete them through the security rules, and
nobody can change them. The owner reads all of them (collection-group
queries) with admin credentials, which bypass the rules, either of:

* an OAuth access token of a Google account with access to the project, e.g.
  ``gcloud auth print-access-token`` (``--access-token`` or
  ``$TOSK_GCP_ACCESS_TOKEN``), or
* a service-account key file (``--service-account PATH``,
  ``$TOSK_FIREBASE_SERVICE_ACCOUNT`` or ``$GOOGLE_APPLICATION_CREDENTIALS``).
  Keep it outside the repository; it is never committed.

::

    python -m pipeline feedback pull [--out DIR] [--all] [--mark-seen]
    python -m pipeline feedback seen <id> users/<uid>/crashes/<id> ...
    python -m pipeline feedback delete --uid <uid>      # every report of one user
    python -m pipeline flags summarize DIR/flags.jsonl

``pull`` merges into ``flags.jsonl`` (``tosk-flag/1``, what ``flags
summarize`` reads), ``feedback.jsonl`` and ``crashes.jsonl`` in the output
folder (default ``~/tosk-feedback``), keyed by id, so pulling again adds only
what is new. By default only reports not marked seen are fetched;
``--mark-seen`` marks the pulled ones (a ``seen`` timestamp on the document).

Network: ``requests`` only. The service-account JWT (RS256) is signed in pure
Python, so no crypto package is needed.
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

COLLECTIONS = ("feedback", "crashes")
SCOPE = "https://www.googleapis.com/auth/datastore"
FIRESTORE = "https://firestore.googleapis.com/v1"
DEFAULT_OUT = Path.home() / "tosk-feedback"


class FeedbackError(RuntimeError):
    pass


# ---------------------------------------------------------------- RS256 JWT

def _der(data: bytes, i: int) -> tuple[int, bytes, int]:
    """One DER element at ``i``: (tag, value, next index)."""
    tag = data[i]
    length = data[i + 1]
    i += 2
    if length & 0x80:
        n = length & 0x7F
        length = int.from_bytes(data[i:i + n], "big")
        i += n
    return tag, data[i:i + length], i + length


def _sequence(data: bytes) -> list[tuple[int, bytes]]:
    tag, body, _ = _der(data, 0)
    if tag != 0x30:
        raise FeedbackError("not a DER sequence")
    out, i = [], 0
    while i < len(body):
        t, v, i = _der(body, i)
        out.append((t, v))
    return out


def rsa_key_from_pem(pem: str) -> tuple[int, int]:
    """(n, d) of a PKCS#8 (``BEGIN PRIVATE KEY``, as in service-account files)
    or PKCS#1 (``BEGIN RSA PRIVATE KEY``) RSA key."""
    lines = [l.strip() for l in pem.strip().splitlines() if l.strip() and not l.startswith("-----")]
    der = base64.b64decode("".join(lines))
    items = _sequence(der)
    if len(items) >= 3 and items[1][0] == 0x30 and items[2][0] == 0x04:  # PKCS#8 wrapper
        items = _sequence(items[2][1])
    if len(items) < 4 or any(t != 0x02 for t, _ in items[:4]):
        raise FeedbackError("not an RSA private key")
    n = int.from_bytes(items[1][1], "big")
    d = int.from_bytes(items[3][1], "big")
    return n, d


_SHA256_PREFIX = bytes.fromhex("3031300d060960864801650304020105000420")


def pkcs1v15_encode(message: bytes, k: int) -> bytes:
    """EMSA-PKCS1-v1_5 with SHA-256 for a k-byte modulus."""
    t = _SHA256_PREFIX + hashlib.sha256(message).digest()
    if k < len(t) + 11:
        raise FeedbackError("RSA key too short")
    return b"\x00\x01" + b"\xff" * (k - len(t) - 3) + b"\x00" + t


def rs256_sign(message: bytes, n: int, d: int) -> bytes:
    k = (n.bit_length() + 7) // 8
    m = int.from_bytes(pkcs1v15_encode(message, k), "big")
    return pow(m, d, n).to_bytes(k, "big")


def _b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode("ascii")


def service_account_jwt(sa: dict[str, Any], now: int | None = None) -> str:
    """The signed assertion Google's token endpoint exchanges for an access token."""
    now = int(time.time()) if now is None else now
    header = {"alg": "RS256", "typ": "JWT", "kid": sa.get("private_key_id", "")}
    claims = {
        "iss": sa["client_email"],
        "scope": SCOPE,
        "aud": sa.get("token_uri", "https://oauth2.googleapis.com/token"),
        "iat": now,
        "exp": now + 3600,
    }
    signing_input = f"{_b64url(json.dumps(header, separators=(',', ':')).encode())}." \
                    f"{_b64url(json.dumps(claims, separators=(',', ':')).encode())}"
    n, d = rsa_key_from_pem(sa["private_key"])
    return f"{signing_input}.{_b64url(rs256_sign(signing_input.encode('ascii'), n, d))}"


# ---------------------------------------------------------------- credentials

def _session():
    import requests
    return requests.Session()


def resolve_credentials(access_token: str | None, service_account: str | None, project: str | None,
                        session=None, env: dict[str, str] | None = None) -> tuple[str, str, bool]:
    """(access token, project id, is a user token). User tokens get the
    ``x-goog-user-project`` header (quota project)."""
    env = os.environ if env is None else env
    access_token = access_token or env.get("TOSK_GCP_ACCESS_TOKEN")
    service_account = service_account or env.get("TOSK_FIREBASE_SERVICE_ACCOUNT") or env.get(
        "GOOGLE_APPLICATION_CREDENTIALS")
    project = project or env.get("TOSK_FIREBASE_PROJECT_ID")
    if access_token:
        if not project:
            project = _project_from_app_config()
        if not project:
            raise FeedbackError("no project id: pass --project or set TOSK_FIREBASE_PROJECT_ID")
        return access_token.strip(), project, True
    if not service_account:
        raise FeedbackError(
            "no credentials: pass --access-token (e.g. from `gcloud auth print-access-token`) or "
            "--service-account PATH (see docs/firebase-setup.md, 'Reading feedback')")
    path = Path(service_account).expanduser()
    try:
        sa = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise FeedbackError(f"can't read the service-account file {path}: {e}") from e
    if sa.get("type") != "service_account" or "private_key" not in sa:
        raise FeedbackError(f"{path} is not a service-account key file")
    project = project or sa.get("project_id")
    s = session or _session()
    r = s.post(sa.get("token_uri", "https://oauth2.googleapis.com/token"), data={
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": service_account_jwt(sa),
    }, timeout=30)
    if r.status_code != 200:
        raise FeedbackError(f"token exchange failed (HTTP {r.status_code}): {r.text[:300]}")
    return r.json()["access_token"], project, False


def _project_from_app_config() -> str | None:
    cfg = Path(__file__).resolve().parents[2] / "app" / "firebase-config.json"
    try:
        return json.loads(cfg.read_text(encoding="utf-8")).get("TOSK_FIREBASE_PROJECT_ID") or None
    except (OSError, ValueError):
        return None


# ---------------------------------------------------------------- Firestore

def decode_value(v: dict[str, Any]) -> Any:
    if "stringValue" in v:
        return v["stringValue"]
    if "integerValue" in v:
        return int(v["integerValue"])
    if "doubleValue" in v:
        return v["doubleValue"]
    if "booleanValue" in v:
        return v["booleanValue"]
    if "timestampValue" in v:
        return v["timestampValue"]
    if "nullValue" in v:
        return None
    if "mapValue" in v:
        return {k: decode_value(x) for k, x in (v["mapValue"].get("fields") or {}).items()}
    if "arrayValue" in v:
        return [decode_value(x) for x in (v["arrayValue"].get("values") or [])]
    return None


class Firestore:
    def __init__(self, token: str, project: str, user_token: bool = False, session=None):
        self.project = project
        self.session = session or _session()
        self.headers = {"Authorization": f"Bearer {token}"}
        if user_token:
            self.headers["x-goog-user-project"] = project

    @property
    def docs(self) -> str:
        return f"projects/{self.project}/databases/(default)/documents"

    def _check(self, r):
        if r.status_code in (401, 403):
            raise FeedbackError(f"Firestore refused access (HTTP {r.status_code}). Does this account or service "
                                f"account have access to project {self.project}? {r.text[:300]}")
        if r.status_code >= 300:
            raise FeedbackError(f"Firestore error (HTTP {r.status_code}): {r.text[:300]}")
        return r.json() if r.text else {}

    def list(self, collection: str, page_size: int = 300) -> list[dict[str, Any]]:
        """Every document of the collection group ``collection`` (all users'
        ``users/{uid}/<collection>``) as {"id", "uid", "name", **fields}, paged
        by document name."""
        out: list[dict[str, Any]] = []
        last = None
        while True:
            q: dict[str, Any] = {
                "from": [{"collectionId": collection, "allDescendants": True}],
                "orderBy": [{"field": {"fieldPath": "__name__"}, "direction": "ASCENDING"}],
                "limit": page_size,
            }
            if last:
                q["startAt"] = {"values": [{"referenceValue": last}], "before": False}
            rows = self._check(self.session.post(f"{FIRESTORE}/{self.docs}:runQuery", json={"structuredQuery": q},
                                                 headers=self.headers, timeout=60))
            docs = [r["document"] for r in rows or [] if isinstance(r, dict) and "document" in r]
            for d in docs:
                fields = {k: decode_value(v) for k, v in (d.get("fields") or {}).items()}
                parts = d["name"].split("/documents/", 1)[-1].split("/")
                uid = parts[1] if len(parts) == 4 and parts[0] == "users" else fields.get("uid")
                out.append({**fields, "id": parts[-1], "uid": uid, "name": d["name"], "collection": collection,
                            "received_at": d.get("createTime")})
            if len(docs) < page_size:
                return out
            last = docs[-1]["name"]

    def get(self, path: str) -> dict[str, Any] | None:
        r = self.session.get(f"{FIRESTORE}/{self.docs}/{path}", headers=self.headers, timeout=60)
        if r.status_code == 404:
            return None
        return self._check(r)

    def commit(self, writes: list[dict[str, Any]]) -> None:
        for i in range(0, len(writes), 400):
            self._check(self.session.post(f"{FIRESTORE}/{self.docs}:commit", json={"writes": writes[i:i + 400]},
                                          headers=self.headers, timeout=60))

    def mark_seen(self, names: Iterable[str], when: str | None = None) -> int:
        when = when or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        writes = [{
            "update": {"name": n, "fields": {"seen": {"timestampValue": when}}},
            "updateMask": {"fieldPaths": ["seen"]},
            "currentDocument": {"exists": True},
        } for n in names]
        self.commit(writes)
        return len(writes)

    def delete(self, names: Iterable[str]) -> int:
        writes = [{"delete": n} for n in names]
        self.commit(writes)
        return len(writes)


# ---------------------------------------------------------------- local files

def _iso(ms: Any) -> str | None:
    if not isinstance(ms, int):
        return None
    return datetime.fromtimestamp(ms / 1000, timezone.utc).isoformat().replace("+00:00", "Z")


def to_records(docs: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    """Firestore documents → the local records: flags (``tosk-flag/1`` lines
    plus ``uid``/``received_at``/``report_id``), general feedback, crash reports."""
    out: dict[str, list[dict[str, Any]]] = {"flags": [], "feedback": [], "crashes": []}
    for d in docs:
        common = {"uid": d.get("uid"), "received_at": d.get("received_at") or d.get("up"), "seen": d.get("seen")}
        if d["collection"] == "crashes":
            out["crashes"].append({"id": d["id"], **common, "app": d.get("app"), "platform": d.get("platform"),
                                   "device": d.get("device"), "at": _iso(d.get("at")), "report": d.get("report")})
        elif d.get("kind") == "flag":
            try:
                flag = json.loads(d.get("flag") or "{}")
            except ValueError:
                flag = {}
            if not isinstance(flag, dict) or "id" not in flag:
                flag = {"format": "tosk-flag/1", "id": d["id"], "comment": d.get("text", ""),
                        "course_id": d.get("course"), "exercise": {}}
            flag.update({"report_id": d["id"], **common, "platform": d.get("platform")})
            out["flags"].append(flag)
        else:
            out["feedback"].append({"id": d["id"], **common, "app": d.get("app"), "platform": d.get("platform"),
                                    "at": _iso(d.get("at")), "course": d.get("course"), "text": d.get("text"),
                                    "email": d.get("email")})
    return out


def merge_jsonl(path: Path, records: list[dict[str, Any]], key: str = "id") -> int:
    """Adds ``records`` to the JSONL file at ``path`` by ``key`` (newer
    copies replace older ones), sorted by ``received_at``. Returns how many
    were new."""
    existing: dict[str, dict[str, Any]] = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                existing[r.get(key)] = r
    new = sum(1 for r in records if r.get(key) not in existing)
    for r in records:
        existing[r.get(key)] = r
    rows = sorted(existing.values(), key=lambda r: (r.get("received_at") or "", str(r.get(key))))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    return new


# ---------------------------------------------------------------- commands

def pull(fs: Firestore, out: Path, include_seen: bool = False, mark_seen: bool = False) -> dict[str, int]:
    docs = [d for c in COLLECTIONS for d in fs.list(c)]
    if not include_seen:
        docs = [d for d in docs if not d.get("seen")]
    recs = to_records(docs)
    counts = {
        "flags": merge_jsonl(out / "flags.jsonl", recs["flags"]),
        "feedback": merge_jsonl(out / "feedback.jsonl", recs["feedback"]),
        "crashes": merge_jsonl(out / "crashes.jsonl", recs["crashes"]),
        "pulled": len(docs),
        "marked": 0,
    }
    if mark_seen:
        counts["marked"] = fs.mark_seen([d["name"] for d in docs if not d.get("seen")])
    _print_pull(recs, counts, out)
    return counts


def _print_pull(recs: dict[str, list[dict[str, Any]]], counts: dict[str, int], out: Path) -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    print(f"Pulled {counts['pulled']} report(s): {len(recs['flags'])} flag(s), {len(recs['feedback'])} feedback, "
          f"{len(recs['crashes'])} crash report(s); new locally: {counts['flags']} / {counts['feedback']} / "
          f"{counts['crashes']}. Files in {out}")
    for f in recs["feedback"]:
        reply = f"  (reply to {f['email']})" if f.get("email") else ""
        print(f"\n[feedback {f['id'][:8]} · {f.get('app')} · {f.get('platform')} · {f.get('at')}]{reply}\n"
              f"{f.get('text')}")
    for c in recs["crashes"]:
        first = (c.get("report") or "").strip().splitlines()[:3]
        print(f"\n[crash {c['id'][:8]} · {c.get('app')} · {c.get('platform')} · {c.get('device')}]\n  "
              + "\n  ".join(first))
    if recs["flags"]:
        print(f"\nFlags: python -m pipeline flags summarize {out / 'flags.jsonl'}")
    if counts["marked"]:
        print(f"Marked {counts['marked']} report(s) as seen.")


def _names_for(fs: Firestore, refs: list[str]) -> list[str]:
    """Full document names for ``users/<uid>/<collection>/<id>`` paths or bare ids."""
    names, by_id = [], None
    for ref in refs:
        if "/" in ref:
            names.append(f"{fs.docs}/{ref}")
            continue
        if by_id is None:
            by_id = {d["id"]: d["name"] for c in COLLECTIONS for d in fs.list(c)}
        if ref not in by_id:
            raise FeedbackError(f"no report with id {ref}")
        names.append(by_id[ref])
    return names


def main(a) -> int:
    try:
        token, project, user = resolve_credentials(a.access_token, a.service_account, a.project)
        fs = Firestore(token, project, user_token=user)
        if a.feedback_cmd == "pull":
            pull(fs, Path(a.out).expanduser() if a.out else DEFAULT_OUT, include_seen=a.all, mark_seen=a.mark_seen)
        elif a.feedback_cmd == "seen":
            print(f"Marked {fs.mark_seen(_names_for(fs, a.ids))} report(s) as seen.")
        elif a.feedback_cmd == "delete":
            names = [d["name"] for c in COLLECTIONS for d in fs.list(c) if d.get("uid") == a.uid]
            if not names:
                print(f"No reports from {a.uid}.")
            elif a.yes or input(f"Delete {len(names)} report(s) from {a.uid}? [y/N] ").strip().lower() == "y":
                print(f"Deleted {fs.delete(names)} report(s).")
        return 0
    except FeedbackError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2


def add_parser(sub) -> None:
    p = sub.add_parser("feedback", help="flags, feedback and crash reports sent from the app (Firestore; owner only)")
    fsub = p.add_subparsers(dest="feedback_cmd", required=True)

    def creds(q):
        q.add_argument("--project", help="Firebase project id (default: $TOSK_FIREBASE_PROJECT_ID, the service "
                                         "account's project, or app/firebase-config.json)")
        q.add_argument("--access-token", help="OAuth token with access to the project, e.g. "
                                              "`gcloud auth print-access-token` ($TOSK_GCP_ACCESS_TOKEN)")
        q.add_argument("--service-account", help="service-account key file, kept outside the repository "
                                                 "($TOSK_FIREBASE_SERVICE_ACCOUNT or $GOOGLE_APPLICATION_CREDENTIALS)")

    q = fsub.add_parser("pull", help="download reports into flags.jsonl, feedback.jsonl and crashes.jsonl")
    creds(q)
    q.add_argument("--out", help=f"output folder (default {DEFAULT_OUT})")
    q.add_argument("--all", action="store_true", help="also reports already marked seen")
    q.add_argument("--mark-seen", action="store_true", help="mark the pulled reports as seen")
    q = fsub.add_parser("seen", help="mark reports as seen (ids, or users/<uid>/feedback/<id> paths)")
    creds(q)
    q.add_argument("ids", nargs="+")
    q = fsub.add_parser("delete", help="delete every report one user sent")
    creds(q)
    q.add_argument("--uid", required=True, help="the Firebase user id (the `uid` of their reports)")
    q.add_argument("--yes", action="store_true", help="don't ask")
