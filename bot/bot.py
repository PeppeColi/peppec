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
STATE = Path(os.environ.get("STATE_FILE", "/data/offset"))
APP_ID = os.environ["APP_ID"]
APP_KEY = Path(os.environ.get("APP_KEY_FILE", "/data/app.pem")).read_text()
VERSION = os.environ.get("PEPPEC_VERSION", "dev")
BLOCKS = ["needs human", "question open", "awaiting quota"]
# Notifications start with the repository they come from: "[owner/name] text"
PREFIX = re.compile(r"^\[([\w.-]+/[\w.-]+)\] ")
QUESTION = re.compile(r"^(?:\[\S+\] )?Question on #(\d+):")
GH = requests.Session()
GH.headers.update({"Accept": "application/vnd.github+json"})


class UserError(Exception):
    """A message for the user: wrong usage, unknown repository."""


class Repo:
    def __init__(self, name, control):
        self.name = name
        self.control = control
        self.api = f"https://api.github.com/repos/{name}"
        self._token = ""
        self._expires = 0.0

    def token(self):
        """Installation token of the GitHub App, renewed 5 minutes before it expires."""
        if time.time() < self._expires - 300:
            return self._token
        now = int(time.time())
        signed = jwt.encode({"iat": now - 60, "exp": now + 540, "iss": APP_ID}, APP_KEY, algorithm="RS256")
        auth = {"Authorization": f"Bearer {signed}"}
        inst = GH.get(f"{self.api}/installation", headers=auth, timeout=30)
        inst.raise_for_status()
        r = GH.post(f"https://api.github.com/app/installations/{inst.json()['id']}/access_tokens",
                    headers=auth, timeout=30)
        r.raise_for_status()
        data = r.json()
        self._token = data["token"]
        self._expires = datetime.fromisoformat(data["expires_at"].replace("Z", "+00:00")).timestamp()
        return self._token

    def gh(self, method, path, **kwargs):
        headers = {"Authorization": f"Bearer {self.token()}"}
        r = GH.request(method, f"{self.api}{path}", headers=headers, timeout=30, **kwargs)
        if method == "DELETE" and r.status_code == 404:
            return None  # label or comment already gone
        r.raise_for_status()
        return r.json() if r.content else None

    def labels(self, n):
        return [x["name"] for x in self.gh("GET", f"/issues/{n}/labels")]

    def add(self, n, label):
        self.gh("POST", f"/issues/{n}/labels", json={"labels": [label]})

    def rm(self, n, label):
        self.gh("DELETE", f"/issues/{n}/labels/{quote(label, safe='')}")

    def comment(self, n, body):
        self.gh("POST", f"/issues/{n}/comments", json={"body": body})

    def dispatch(self):
        self.gh("POST", "/actions/workflows/agent.yml/dispatches", json={"ref": "main"})

    def issues(self, label):
        params = {"state": "open", "labels": label, "per_page": 100, "sort": "created", "direction": "asc"}
        return [i for i in self.gh("GET", "/issues", params=params) if "pull_request" not in i]

    def agent_pr(self, n):
        owner = self.name.split("/")[0]
        prs = self.gh("GET", "/pulls", params={"head": f"{owner}:agent/issue-{n}", "state": "open"})
        return prs[0]["number"] if prs else None

    def active(self):
        a = self.issues("in progress")
        return a[0]["number"] if a else None

    def reset_minutes(self, n):
        for c in self.gh("GET", f"/issues/{n}/comments", params={"per_page": 100}):
            if c["body"].startswith("<!-- peppec:minutes="):
                self.gh("DELETE", f"/issues/comments/{c['id']}")

    def unblock(self, n):
        for label in BLOCKS:
            self.rm(n, label)
        self.reset_minutes(n)
        pr = self.agent_pr(n)
        if pr:
            for label in self.labels(pr):
                if re.fullmatch(r"(review|ci) \d+", label) or label in ("needs human", "ready to merge"):
                    self.rm(pr, label)
            self.add(pr, "review 1")

    def status(self):
        c = self.labels(self.control)
        out = [self.name,
               f"Mode: {'automatic' if 'auto mode' in c else 'manual'}",
               f"Schedule: {'always' if 'always on' in c else 'nightly'}",
               f"Paused: {'yes' if 'paused' in c else 'no'}"]
        n = self.active()
        if n:
            out.append(f"In progress: #{n}, labels: {', '.join(self.labels(n))}")
            pr = self.agent_pr(n)
            if pr:
                out.append(f"PR #{pr}: {', '.join(self.labels(pr))}")
        else:
            out.append("No issue in progress")
        out.append(f"In queue: {len(self.issues('ready'))}")
        return "\n".join(out)


def load_repos():
    """REPOS is a list of owner/name#N, N being the number of the "Control panel" issue.
    REPO and CONTROL_ISSUE, the settings of the single-repository bot, still work."""
    spec = os.environ.get("REPOS", "")
    if not spec.strip() and os.environ.get("REPO"):
        spec = f"{os.environ['REPO']}#{os.environ.get('CONTROL_ISSUE', '')}"
    repos = []
    for item in re.split(r"[,\s]+", spec.strip()):
        if not item:
            continue
        m = re.fullmatch(r"([\w.-]+/[\w.-]+)#(\d+)", item)
        if not m:
            raise SystemExit(f"REPOS: '{item}' is not owner/name#N, N being the control panel issue")
        if any(r.name.lower() == m.group(1).lower() for r in repos):
            raise SystemExit(f"REPOS: {m.group(1)} is listed twice")
        repos.append(Repo(m.group(1), m.group(2)))
    if not repos:
        raise SystemExit("REPOS is empty: set it to owner/name#N[,owner/name#N...]")
    return repos


REPOS = load_repos()


def send(text):
    requests.post(f"{TG}/sendMessage", data={"chat_id": CHAT, "text": text[:4000]}, timeout=30)


def names():
    return ", ".join(r.name for r in REPOS)


def find(word):
    """The repository called word: its full name, or the name alone when only one has it."""
    w = word.lower()
    if not w or w.isdigit():
        return None
    for r in REPOS:
        if r.name.lower() == w:
            return r
    short = [r for r in REPOS if r.name.lower().split("/")[1] == w]
    if len(short) > 1:
        raise UserError(f"'{word}' matches several repositories: use the full name ({names()}).")
    return short[0] if short else None


def repo_of(reply):
    """The repository a notification comes from; None if it is not a reply or it cannot be told."""
    if not reply:
        return None
    m = PREFIX.match(reply.get("text") or "")
    if not m:
        # Sent by a repository on an engine older than 1.6, or by the bot itself
        return REPOS[0] if len(REPOS) == 1 else None
    for r in REPOS:
        if r.name.lower() == m.group(1).lower():
            return r
    raise UserError(f"I do not follow {m.group(1)}. Repositories: {names()}.")


def split_repo(arg, context):
    """Takes the repository off the front of the arguments. Without one, the repository
    of the message replied to, or the only one followed."""
    word, _, rest = arg.partition(" ")
    repo = find(word)
    if repo:
        return repo, rest.strip()
    if context:
        return context, arg
    return (REPOS[0] if len(REPOS) == 1 else None), arg


def need(repo, usage):
    if not repo:
        raise UserError(f"Which repository? Usage: {usage}\nRepositories: {names()}.\n"
                        "Or send the command as a reply to a notification.")
    return repo


def handle(msg):
    text = (msg.get("text") or "").strip()
    reply = msg.get("reply_to_message")
    context = repo_of(reply)
    if reply and not text.startswith("/"):
        m = QUESTION.match(reply.get("text") or "")
        if not m:
            return send("Replies are accepted only to \"Question on #N\" messages.")
        if not context:
            return send("This message does not say which repository it comes from: "
                        "upgrade the engine of that repository to 1.6 or later.")
        n = int(m.group(1))
        context.comment(n, text)
        context.rm(n, "question open")
        context.dispatch()
        return send(f"Answer posted on {context.name}#{n}, restarting.")
    cmd, _, arg = text.partition(" ")
    cmd = cmd.split("@")[0]
    if cmd == "/version":
        return send(f"peppec-bot {VERSION}")
    repo, arg = split_repo(arg.strip(), context)
    if cmd in ("/status", "/pause") and arg:
        # A mistyped name must not turn into "all of them"
        raise UserError(f"I do not follow '{arg}'. Repositories: {names()}.")
    if cmd == "/status":
        send("\n\n".join(r.status() for r in ([repo] if repo else REPOS)))
    elif cmd == "/pause":
        targets = [repo] if repo else REPOS
        for r in targets:
            r.add(r.control, "paused")
        send(f"Queue paused: {', '.join(r.name for r in targets)}.")
    elif cmd == "/unblock":
        need(repo, "/unblock <repo> [n]")
        repo.rm(repo.control, "paused")
        n = int(arg) if arg.isdigit() else repo.active()
        if n:
            repo.unblock(n)
        repo.dispatch()
        send(f"Unblocked {repo.name}{f'#{n}' if n else ''}, restarting.")
    elif cmd == "/hint":
        num, _, body = arg.partition(" ")
        if not num.isdigit() or not body.strip():
            return send("Usage: /hint [repo] <number> <text>")
        need(repo, "/hint <repo> <number> <text>")
        repo.comment(int(num), f"Hint for the agent: {body.strip()}")
        repo.unblock(int(num))
        repo.rm(repo.control, "paused")
        repo.dispatch()
        send(f"Hint added to {repo.name}#{num}, restarting.")
    elif cmd == "/mode":
        if arg not in ("manual", "automatic"):
            return send("Usage: /mode [repo] manual | automatic")
        need(repo, "/mode <repo> manual | automatic")
        if arg == "automatic":
            repo.add(repo.control, "auto mode")
        else:
            repo.rm(repo.control, "auto mode")
        repo.dispatch()
        send(f"Mode of {repo.name} set to {arg}.")
    elif cmd == "/schedule":
        if arg not in ("nightly", "always"):
            return send("Usage: /schedule [repo] nightly | always")
        need(repo, "/schedule <repo> nightly | always")
        if arg == "always":
            repo.add(repo.control, "always on")
        else:
            repo.rm(repo.control, "always on")
        repo.dispatch()
        send(f"Schedule of {repo.name} set to {arg}.")
    else:
        send("Commands: /status [repo], /pause [repo], /unblock [repo] [n], /hint [repo] <n> <text>, "
             "/mode [repo] manual|automatic, /schedule [repo] nightly|always, /version.\n"
             "Without a repository, /status and /pause apply to all of them. The other commands need it "
             "when there is more than one, unless you send them as a reply to a notification.\n"
             "To answer a question, reply to its message.\n"
             f"Repositories: {names()}.")
    return None


def safe_handle(msg):
    try:
        handle(msg)
    except UserError as e:
        send(str(e))
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
    print(f"peppec-bot {VERSION}, repositories: {names()}", flush=True)
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
