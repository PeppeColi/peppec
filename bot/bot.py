import os
import re
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import quote

import jwt
import requests

TG = f"https://api.telegram.org/bot{os.environ['TELEGRAM_BOT_TOKEN']}"
CHAT = int(os.environ["TELEGRAM_CHAT_ID"])
REPO = os.environ["REPO"]
CTRL = os.environ["CONTROL_ISSUE"]
API = f"https://api.github.com/repos/{REPO}"
STATE = Path(os.environ.get("STATE_FILE", "/data/offset"))
APP_ID = os.environ["APP_ID"]
APP_KEY = Path(os.environ.get("APP_KEY_FILE", "/data/app.pem")).read_text()
VERSION = os.environ.get("PEPPEC_VERSION", "dev")
BLOCKS = ["needs human", "question open", "awaiting quota"]
QUESTION = re.compile(r"^Question on #(\d+):")
GH = requests.Session()
GH.headers.update({"Accept": "application/vnd.github+json"})
_token = {"value": "", "expires": 0.0}


def app_token():
    """Installation token of the GitHub App, renewed 5 minutes before it expires."""
    if time.time() < _token["expires"] - 300:
        return _token["value"]
    now = int(time.time())
    signed = jwt.encode({"iat": now - 60, "exp": now + 540, "iss": APP_ID}, APP_KEY, algorithm="RS256")
    auth = {"Authorization": f"Bearer {signed}"}
    inst = GH.get(f"{API}/installation", headers=auth, timeout=30)
    inst.raise_for_status()
    r = GH.post(f"https://api.github.com/app/installations/{inst.json()['id']}/access_tokens",
                headers=auth, timeout=30)
    r.raise_for_status()
    data = r.json()
    _token["value"] = data["token"]
    _token["expires"] = datetime.fromisoformat(data["expires_at"].replace("Z", "+00:00")).timestamp()
    return _token["value"]


def gh(method, path, **kwargs):
    headers = {"Authorization": f"Bearer {app_token()}"}
    r = GH.request(method, f"{API}{path}", headers=headers, timeout=30, **kwargs)
    if method == "DELETE" and r.status_code == 404:
        return None  # label or comment already gone
    r.raise_for_status()
    return r.json() if r.content else None


def send(text):
    requests.post(f"{TG}/sendMessage", data={"chat_id": CHAT, "text": text[:4000]}, timeout=30)


def labels(n):
    return [x["name"] for x in gh("GET", f"/issues/{n}/labels")]


def add(n, label):
    gh("POST", f"/issues/{n}/labels", json={"labels": [label]})


def rm(n, label):
    gh("DELETE", f"/issues/{n}/labels/{quote(label, safe='')}")


def comment(n, body):
    gh("POST", f"/issues/{n}/comments", json={"body": body})


def dispatch():
    gh("POST", "/actions/workflows/agent.yml/dispatches", json={"ref": "main"})


def issues(label):
    params = {"state": "open", "labels": label, "per_page": 100, "sort": "created", "direction": "asc"}
    return [i for i in gh("GET", "/issues", params=params) if "pull_request" not in i]


def agent_pr(n):
    owner = REPO.split("/")[0]
    prs = gh("GET", "/pulls", params={"head": f"{owner}:agent/issue-{n}", "state": "open"})
    return prs[0]["number"] if prs else None


def active():
    a = issues("in progress")
    return a[0]["number"] if a else None


def reset_minutes(n):
    for c in gh("GET", f"/issues/{n}/comments", params={"per_page": 100}):
        if c["body"].startswith("<!-- peppec:minutes="):
            gh("DELETE", f"/issues/comments/{c['id']}")


def unblock(n):
    for label in BLOCKS:
        rm(n, label)
    reset_minutes(n)
    pr = agent_pr(n)
    if pr:
        for label in labels(pr):
            if re.fullmatch(r"(review|ci) \d+", label) or label in ("needs human", "ready to merge"):
                rm(pr, label)
        add(pr, "review 1")


def status():
    c = labels(CTRL)
    out = [f"Mode: {'automatic' if 'auto mode' in c else 'manual'}",
           f"Paused: {'yes' if 'paused' in c else 'no'}"]
    n = active()
    if n:
        out.append(f"In progress: #{n}, labels: {', '.join(labels(n))}")
        pr = agent_pr(n)
        if pr:
            out.append(f"PR #{pr}: {', '.join(labels(pr))}")
    else:
        out.append("No issue in progress")
    out.append(f"In queue: {len(issues('ready'))}")
    return "\n".join(out)


def handle(msg):
    text = (msg.get("text") or "").strip()
    reply = msg.get("reply_to_message")
    if reply and not text.startswith("/"):
        m = QUESTION.match(reply.get("text", ""))
        if not m:
            return send("Replies are accepted only to \"Question on #N\" messages.")
        n = int(m.group(1))
        comment(n, text)
        rm(n, "question open")
        dispatch()
        return send(f"Answer posted on #{n}, restarting.")
    cmd, _, arg = text.partition(" ")
    cmd, arg = cmd.split("@")[0], arg.strip()
    if cmd == "/status":
        send(status())
    elif cmd == "/version":
        send(f"peppec-bot {VERSION}")
    elif cmd == "/pause":
        add(CTRL, "paused")
        send("Queue paused.")
    elif cmd == "/unblock":
        rm(CTRL, "paused")
        n = int(arg) if arg.isdigit() else active()
        if n:
            unblock(n)
        dispatch()
        send(f"Unblocked{f' #{n}' if n else ''}, restarting.")
    elif cmd == "/hint":
        num, _, body = arg.partition(" ")
        if not num.isdigit() or not body:
            return send("Usage: /hint <number> <text>")
        comment(int(num), f"Hint for the agent: {body}")
        unblock(int(num))
        rm(CTRL, "paused")
        dispatch()
        send(f"Hint added to #{num}, restarting.")
    elif cmd == "/mode":
        if arg == "automatic":
            add(CTRL, "auto mode")
        elif arg == "manual":
            rm(CTRL, "auto mode")
        else:
            return send("Usage: /mode manual | automatic")
        dispatch()
        send(f"Mode set to {arg}.")
    else:
        send("Commands: /status /pause /unblock [n] /hint <n> <text> /mode manual|automatic /version. "
             "To answer a question, reply to its message.")
    return None


def safe_handle(msg):
    try:
        handle(msg)
    except requests.HTTPError as e:
        req = e.request
        send(f"GitHub error {e.response.status_code} {e.response.reason} on {req.method} {req.url}")
    except Exception as e:  # report anything else instead of failing silently
        send(f"Error: {e}")


def load_offset():
    try:
        return int(STATE.read_text())
    except (OSError, ValueError):
        return 0


def save_offset(offset):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(str(offset))


def main():
    offset = load_offset()
    while True:
        try:
            r = requests.get(f"{TG}/getUpdates", params={"timeout": 50, "offset": offset}, timeout=60)
            for u in r.json().get("result", []):
                offset = u["update_id"] + 1
                save_offset(offset)  # saved before handling: an update is never processed twice
                msg = u.get("message")
                if msg and msg["chat"]["id"] == CHAT:
                    safe_handle(msg)
        except requests.RequestException as e:
            print("network error:", e, flush=True)
            time.sleep(10)


if __name__ == "__main__":
    main()
