"""`python -m pipeline feedback`: the pure-Python RS256 service-account JWT,
credentials, the Firestore REST calls (against a fake session), the local
JSONL files, and `flags summarize` on pulled flags. Offline."""
from __future__ import annotations

import base64
import hashlib
import json
import random

import pytest

from pipeline import feedback as fb
from pipeline.flags import load_flags, summarize

PROJECT = "tosk-test"
DOCS = f"projects/{PROJECT}/databases/(default)/documents"


# ------------------------------------------------------------------ a test RSA key

def _probable_prime(bits: int, rng: random.Random) -> int:
    def is_prime(n: int) -> bool:
        if n < 2:
            return False
        for p in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29):
            if n % p == 0:
                return n == p
        d, r = n - 1, 0
        while d % 2 == 0:
            d //= 2
            r += 1
        for _ in range(16):
            x = pow(rng.randrange(2, n - 1), d, n)
            if x in (1, n - 1):
                continue
            for _ in range(r - 1):
                x = pow(x, 2, n)
                if x == n - 1:
                    break
            else:
                return False
        return True

    while True:
        c = rng.getrandbits(bits) | (1 << (bits - 1)) | 1
        if is_prime(c):
            return c


def _der_int(v: int) -> bytes:
    b = v.to_bytes((v.bit_length() + 8) // 8 or 1, "big")
    return _der(0x02, b)


def _der(tag: int, body: bytes) -> bytes:
    n = len(body)
    if n < 0x80:
        length = bytes([n])
    else:
        lb = n.to_bytes((n.bit_length() + 7) // 8, "big")
        length = bytes([0x80 | len(lb)]) + lb
    return bytes([tag]) + length + body


@pytest.fixture(scope="module")
def rsa_key():
    rng = random.Random(7)
    e = 65537
    while True:
        p, q = _probable_prime(512, rng), _probable_prime(512, rng)
        phi = (p - 1) * (q - 1)
        if p != q and phi % e:
            break
    n, d = p * q, pow(e, -1, phi)
    pkcs1 = _der(0x30, b"".join(_der_int(x) for x in (0, n, e, d, p, q, d % (p - 1), d % (q - 1), pow(q, -1, p))))
    alg = _der(0x30, _der(0x06, bytes.fromhex("2a864886f70d010101")) + _der(0x05, b""))
    pkcs8 = _der(0x30, _der_int(0) + alg + _der(0x04, pkcs1))
    pem = "-----BEGIN PRIVATE KEY-----\n" + base64.encodebytes(pkcs8).decode() + "-----END PRIVATE KEY-----\n"
    pem1 = "-----BEGIN RSA PRIVATE KEY-----\n" + base64.encodebytes(pkcs1).decode() + "-----END RSA PRIVATE KEY-----\n"
    return {"n": n, "e": e, "d": d, "pem": pem, "pem1": pem1}


def _unb64(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def test_rsa_keys_parse_from_pkcs8_and_pkcs1(rsa_key):
    assert fb.rsa_key_from_pem(rsa_key["pem"]) == (rsa_key["n"], rsa_key["d"])
    assert fb.rsa_key_from_pem(rsa_key["pem1"]) == (rsa_key["n"], rsa_key["d"])
    with pytest.raises(fb.FeedbackError):
        fb.rsa_key_from_pem("-----BEGIN PRIVATE KEY-----\n" + base64.b64encode(_der(0x30, _der(0x04, b"x"))).decode())


def test_service_account_jwt_is_a_valid_rs256_signature(rsa_key):
    sa = {"type": "service_account", "client_email": "reader@tosk-test.iam.gserviceaccount.com",
          "private_key": rsa_key["pem"], "private_key_id": "k1", "token_uri": "https://oauth2.googleapis.com/token"}
    jwt = fb.service_account_jwt(sa, now=1_760_000_000)
    head, claims, sig = jwt.split(".")
    assert json.loads(_unb64(head)) == {"alg": "RS256", "typ": "JWT", "kid": "k1"}
    c = json.loads(_unb64(claims))
    assert c["iss"] == sa["client_email"]
    assert c["scope"] == "https://www.googleapis.com/auth/datastore"
    assert c["aud"] == "https://oauth2.googleapis.com/token"
    assert c["exp"] - c["iat"] == 3600
    # Verify like Google does: s^e mod n is the PKCS#1 v1.5 SHA-256 encoding.
    k = (rsa_key["n"].bit_length() + 7) // 8
    em = pow(int.from_bytes(_unb64(sig), "big"), rsa_key["e"], rsa_key["n"]).to_bytes(k, "big")
    assert em == fb.pkcs1v15_encode(f"{head}.{claims}".encode(), k)
    assert em.endswith(hashlib.sha256(f"{head}.{claims}".encode()).digest())


# ------------------------------------------------------------------ a fake Firestore

class Resp:
    def __init__(self, status: int, body):
        self.status_code = status
        self.text = json.dumps(body) if body is not None else ""

    def json(self):
        return json.loads(self.text)


def _fields(d: dict) -> dict:
    out = {}
    for k, v in d.items():
        if isinstance(v, bool):
            out[k] = {"booleanValue": v}
        elif isinstance(v, int):
            out[k] = {"integerValue": str(v)}
        elif k in ("up", "seen"):
            out[k] = {"timestampValue": v}
        else:
            out[k] = {"stringValue": v}
    return out


class FakeSession:
    """Google's token endpoint and Firestore's list/get/commit."""

    def __init__(self, docs: dict[str, dict]):
        self.docs = docs  # "collection/id" -> fields (plain values)
        self.calls: list[tuple[str, str]] = []
        self.headers: list[dict] = []
        self.token_requests: list[dict] = []
        self.status = 200

    def post(self, url, data=None, json=None, headers=None, timeout=None):
        self.calls.append(("POST", url))
        if url.startswith("https://oauth2.googleapis.com/token"):
            self.token_requests.append(data)
            return Resp(200, {"access_token": "sa-token", "expires_in": 3599})
        self.headers.append(headers)
        if url == f"{fb.FIRESTORE}/{DOCS}:runQuery":
            return self._query(json["structuredQuery"])
        assert url == f"{fb.FIRESTORE}/{DOCS}:commit"
        for w in json["writes"]:
            if "delete" in w:
                self.docs.pop(w["delete"].split("/documents/")[1], None)
                continue
            path = w["update"]["name"].split("/documents/")[1]
            assert w["updateMask"] == {"fieldPaths": ["seen"]}
            assert w["currentDocument"] == {"exists": True}
            self.docs[path]["seen"] = w["update"]["fields"]["seen"]["timestampValue"]
        return Resp(200, {"commitTime": "2026-10-25T10:00:00Z"})

    def _query(self, q):
        """A collection-group query ordered by name, with a limit and a startAt cursor."""
        if self.status != 200:
            return Resp(self.status, {"error": {"message": "PERMISSION_DENIED"}})
        (src,) = q["from"]
        assert src["allDescendants"] is True
        assert q["orderBy"] == [{"field": {"fieldPath": "__name__"}, "direction": "ASCENDING"}]
        coll = src["collectionId"]
        names = sorted(f"{DOCS}/{n}" for n in self.docs if n.split("/")[-2] == coll)
        if "startAt" in q:
            after = q["startAt"]["values"][0]["referenceValue"]
            names = [n for n in names if n > after]
        page = names[:q["limit"]]
        if not page:
            return Resp(200, [{"readTime": "2026-10-25T10:00:00Z"}])
        return Resp(200, [{"document": {"name": n, "fields": _fields(self.docs[n.split("/documents/")[1]]),
                                        "createTime": f"2026-10-2{i}T08:00:00Z"}, "readTime": "x"}
                          for i, n in enumerate(page)])

    def get(self, url, params=None, headers=None, timeout=None):
        raise AssertionError("not used")


FLAG = {"format": "tosk-flag/1", "id": "f-0001", "created_at": "2026-10-14T09:30:00.000Z", "course_id": "it",
        "skill_id": "present_are", "facet_id": "it:mangiare#form:presente", "exercise_type": "cloze",
        "exercise": {"type": "cloze", "before": "Noi ", "after": " il pane.", "expected": "mangiamo",
                     "options": ["mangiamo", "mangiate"], "correct_index": 0},
        "given": "mangiate", "expected": "mangiamo", "correct": False, "reasons": ["multiple_answers"],
        "comment": "Both should work?", "ai_verdict": None, "ai_reasoning": None, "app_version": "0.7.6+19",
        "pack_version": "1.5.0", "source_lang": "en"}


def _docs():
    base = {"v": 1, "app": "0.7.6+19", "at": 1_760_000_000_000, "up": "2026-10-20T08:00:00Z"}
    return {
        "users/alice/feedback/f-0001": {**base, "kind": "flag", "platform": "android", "text": "Both should work?",
                                        "flag": json.dumps(FLAG), "course": "it"},
        "users/bob/feedback/g-0001": {**base, "kind": "general", "platform": "web", "text": "Dark mode please",
                                      "email": "bob@example.com"},
        "users/bob/feedback/g-0002": {**base, "kind": "general", "platform": "web", "text": "old one",
                                      "seen": "2026-10-01T00:00:00Z"},
        "users/alice/crashes/c-0001": {**base, "platform": "android", "device": "Google Pixel 8",
                                       "report": "Uncaught error: boom\n#0 main"},
        "users/alice/batches/b1": {"v": 1, "dev": "d", "n": 1, "events": "{}"},  # not a report
    }


def test_credentials_access_token_and_service_account(tmp_path, rsa_key):
    tok, project, user = fb.resolve_credentials("ya29.x", None, None, env={"TOSK_FIREBASE_PROJECT_ID": PROJECT})
    assert (tok, project, user) == ("ya29.x", PROJECT, True)
    sa_path = tmp_path / "sa.json"
    sa_path.write_text(json.dumps({"type": "service_account", "project_id": PROJECT, "private_key": rsa_key["pem"],
                                   "client_email": "r@x.iam.gserviceaccount.com"}), encoding="utf-8")
    s = FakeSession({})
    tok, project, user = fb.resolve_credentials(None, None, None, session=s,
                                                env={"GOOGLE_APPLICATION_CREDENTIALS": str(sa_path)})
    assert (tok, project, user) == ("sa-token", PROJECT, False)
    assert s.token_requests[0]["grant_type"] == "urn:ietf:params:oauth:grant-type:jwt-bearer"
    with pytest.raises(fb.FeedbackError, match="no credentials"):
        fb.resolve_credentials(None, None, PROJECT, env={})
    (tmp_path / "bad.json").write_text("{}", encoding="utf-8")
    with pytest.raises(fb.FeedbackError, match="not a service-account"):
        fb.resolve_credentials(None, str(tmp_path / "bad.json"), PROJECT, env={})


def test_pull_writes_local_files_marks_seen_and_merges(tmp_path, capsys):
    s = FakeSession(_docs())
    fs = fb.Firestore("ya29.x", PROJECT, user_token=True, session=s)
    counts = fb.pull(fs, tmp_path, mark_seen=True)
    assert counts["pulled"] == 3  # the seen one is skipped
    assert counts["marked"] == 3
    assert all(h["x-goog-user-project"] == PROJECT for h in s.headers)
    flags = [json.loads(l) for l in (tmp_path / "flags.jsonl").read_text(encoding="utf-8").splitlines()]
    assert flags[0]["id"] == "f-0001" and flags[0]["format"] == "tosk-flag/1"
    assert flags[0]["uid"] == "alice" and flags[0]["report_id"] == "f-0001"
    general = [json.loads(l) for l in (tmp_path / "feedback.jsonl").read_text(encoding="utf-8").splitlines()]
    assert [g["text"] for g in general] == ["Dark mode please"]
    assert general[0]["email"] == "bob@example.com"
    assert general[0]["at"] == "2025-10-09T08:53:20Z"
    crashes = [json.loads(l) for l in (tmp_path / "crashes.jsonl").read_text(encoding="utf-8").splitlines()]
    assert crashes[0]["device"] == "Google Pixel 8"
    assert all(s.docs[k].get("seen") for k in s.docs if "/batches/" not in k)
    out = capsys.readouterr().out
    assert "Dark mode please" in out and "(reply to bob@example.com)" in out and "Uncaught error: boom" in out

    # Pulling again: nothing unseen is left; --all brings everything, merged by id.
    assert fb.pull(fs, tmp_path)["pulled"] == 0
    again = fb.pull(fs, tmp_path, include_seen=True)
    assert again["pulled"] == 4 and again["feedback"] == 1  # only "old one" is new locally
    assert len((tmp_path / "feedback.jsonl").read_text(encoding="utf-8").splitlines()) == 2


def test_pulled_flags_summarize(tmp_path):
    fb.pull(fb.Firestore("t", PROJECT, session=FakeSession(_docs())), tmp_path)
    flags, warnings = load_flags([tmp_path / "flags.jsonl"])
    assert warnings == []
    text = summarize(flags)
    assert "present_are" in text and "Both should work?" in text and "*mangiamo" in text


def test_seen_and_delete_by_uid(tmp_path, monkeypatch):
    s = FakeSession(_docs())
    fs = fb.Firestore("t", PROJECT, session=s)
    assert fs.mark_seen(fb._names_for(fs, ["g-0001", "users/alice/crashes/c-0001"])) == 2
    assert s.docs["users/bob/feedback/g-0001"]["seen"] and s.docs["users/alice/crashes/c-0001"]["seen"]
    with pytest.raises(fb.FeedbackError, match="no report"):
        fb._names_for(fs, ["nope"])

    class A:
        feedback_cmd, uid, yes = "delete", "alice", True
        access_token, service_account, project = "t", None, PROJECT

    monkeypatch.setattr(fb, "_session", lambda: s)
    assert fb.main(A) == 0
    assert sorted(s.docs) == ["users/alice/batches/b1", "users/bob/feedback/g-0001", "users/bob/feedback/g-0002"]


def test_access_refused_is_explained(tmp_path):
    s = FakeSession(_docs())
    s.status = 403
    with pytest.raises(fb.FeedbackError, match="refused access"):
        fb.pull(fb.Firestore("t", PROJECT, session=s), tmp_path)


def test_listing_pages_through_every_user(tmp_path):
    docs = {f"users/u{i:02d}/feedback/g-{i:04d}": {"v": 1, "kind": "general", "app": "x", "platform": "web",
                                                    "at": 1, "text": f"t{i}"} for i in range(7)}
    s = FakeSession(docs)
    got = fb.Firestore("t", PROJECT, session=s).list("feedback", page_size=3)
    assert [d["id"] for d in got] == [f"g-{i:04d}" for i in range(7)]
    assert [d["uid"] for d in got] == [f"u{i:02d}" for i in range(7)]
    assert sum(1 for c in s.calls if c[1].endswith(":runQuery")) == 3


def test_cli_parses_feedback_commands():
    import argparse
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd")
    fb.add_parser(sub)
    a = ap.parse_args(["feedback", "pull", "--access-token", "x", "--out", "o", "--mark-seen"])
    assert (a.feedback_cmd, a.access_token, a.out, a.mark_seen, a.all) == ("pull", "x", "o", True, False)
    a = ap.parse_args(["feedback", "delete", "--uid", "u1", "--yes"])
    assert (a.feedback_cmd, a.uid, a.yes) == ("delete", "u1", True)
