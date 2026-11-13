import hashlib
import hmac
import json
import os
import re
import subprocess
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import quote, unquote

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
# The message a "Hint" button asks to reply to
HINT = re.compile(r"^Hint for ([\w.-]+/[\w.-]+)#(\d+):")
# The message a "Report a problem" button asks to reply to; the number is the specification's
REPORT = re.compile(r"^Problem with ([\w.-]+/[\w.-]+)#(\d+):")
# The menu Telegram shows when you type "/"
COMMANDS = [
    ("status", "State of the queues, with buttons to change it"),
    ("pause", "Stop the queue"),
    ("unblock", "Clear pause and blocks, then restart"),
    ("hint", "Give the agent a hint on an issue"),
    ("mode", "Merge mode: manual or automatic"),
    ("schedule", "Work hours: nightly or always"),
    ("version", "Version of the bot"),
    ("help", "How to use the commands"),
]
# The dashboard: a web page served by the bot, off unless DASHBOARD_PASSWORD is set
PASSWORD = os.environ.get("DASHBOARD_PASSWORD", "")
DASHBOARD_PORT = 8737
PAGE = Path(__file__).with_name("dashboard.html")
# One thread at a time talks to GitHub: the Telegram loop or a request of the dashboard
LOCK = threading.RLock()
GH = requests.Session()
GH.headers.update({"Accept": "application/vnd.github+json"})
# Claude usage on the dashboard: on when Claude Code is logged in inside the bot's container,
# with its configuration in this directory (mounted from the host, see docker-compose.yml)
CLAUDE_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", "/claude"))
CREDENTIALS = CLAUDE_DIR / ".credentials.json"
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
USAGE_LOCK = threading.Lock()
USAGE_REUSE = 60  # seconds a reading is shown again instead of asking Anthropic
USAGE_CACHE = {"last": None, "wait_until": 0}  # last reading; no request before wait_until (429)
LOGIN_HINT = "run 'docker compose run --rm peppec-bot claude' on the bot's machine and log in"


class UserError(Exception):
    """A message for the user: wrong usage, unknown repository."""


class Repo:
    def __init__(self, name, control):
        self.name = name
        self.control = control
        self.api = f"https://api.github.com/repos/{name}"
        # Names the repository in the data of a button, which Telegram limits to 64 bytes
        self.key = hashlib.sha1(name.lower().encode()).hexdigest()[:8]
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

    def queue(self):
        """The ready issues the agent will build: not the ones decide.sh skips as not work units."""
        return [i for i in self.issues("ready") if not not_work_unit(i)]

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

    def button(self, text, action, value=""):
        return {"text": text, "callback_data": f"{action}|{value}|{self.key}"}

    def panel(self):
        """The state of the repository and the buttons that change it."""
        c = self.labels(self.control)
        auto, always, paused = "auto mode" in c, "always on" in c, "paused" in c
        out = [self.name,
               f"Mode: {'automatic' if auto else 'manual'}",
               f"Schedule: {'always' if always else 'nightly'}",
               f"Paused: {'yes' if paused else 'no'}"]
        if "base missing" in c:
            out.append("Stopped: the base branch does not exist")
        rows = [[self.button("Resume", "resume") if paused else self.button("Pause", "pause")],
                [self.button(f"Mode \u2192 {'manual' if auto else 'automatic'}", "mode",
                             "manual" if auto else "automatic"),
                 self.button(f"Schedule \u2192 {'nightly' if always else 'always'}", "schedule",
                             "nightly" if always else "always")]]
        n = self.active()
        if n:
            out.append(f"In progress: #{n}, labels: {', '.join(self.labels(n))}")
            pr = self.agent_pr(n)
            if pr:
                out.append(f"PR #{pr}: {', '.join(self.labels(pr))}")
        else:
            out.append("No issue in progress")
        out.append(f"In queue: {len(self.queue())}")
        if n:
            rows.append([self.button(f"Unblock #{n}", "unblock", n), self.button(f"Hint #{n}", "hint", n)])
        rows.append([self.button("Refresh", "refresh")])
        return "\n".join(out), {"inline_keyboard": rows}

    def state(self):
        """What the dashboard shows of the repository."""
        c = self.labels(self.control)
        out = {"name": self.name, "key": self.key, "url": f"https://github.com/{self.name}",
               "mode": "automatic" if "auto mode" in c else "manual",
               "schedule": "always" if "always on" in c else "nightly",
               "paused": "paused" in c, "base_missing": "base missing" in c, "active": None}
        active = self.issues("in progress")
        if active:
            issue = active[0]
            n, labels = issue["number"], [x["name"] for x in issue["labels"]]
            minutes, said = 0, ""
            for comment in self.gh("GET", f"/issues/{n}/comments", params={"per_page": 100}):
                m = re.match(r"<!-- peppec:minutes=(\d+)", comment["body"])
                if m:
                    minutes = int(m.group(1))
                elif not comment["body"].startswith("<!-- peppec:"):
                    said = comment["body"]
            pr = self.agent_pr(n)
            out["active"] = {
                "number": n, "title": issue["title"], "url": f"{out['url']}/issues/{n}",
                "size": size_of(labels), "minutes": minutes,
                "block": next((b for b in BLOCKS if b in labels), None),
                # The question is the last comment: after.sh posts it right before the label
                "question": said if "question open" in labels else "",
                "pr": {"number": pr, "labels": self.labels(pr), "url": f"{out['url']}/pull/{pr}"} if pr else None}
        out["queue"] = [{"number": i["number"], "title": i["title"], "size": size_of([x["name"] for x in i["labels"]])}
                        for i in self.queue() if not any(x["name"] == "in progress" for x in i["labels"])]
        out["trying"] = [{"number": i["number"], "title": i["title"], "url": f"{out['url']}/issues/{i['number']}",
                          "total": i["sub_issues_summary"]["total"]} for i in self.features_done()]
        return out

    def features_done(self):
        """The open specifications whose sub-issues are all closed: features ready to be tried.
        A cleared wayfinder map is left out: its destination is a specification still to write."""
        params = {"state": "open", "per_page": 100, "sort": "created", "direction": "asc"}
        return [i for i in self.gh("GET", "/issues", params=params) if "pull_request" not in i
                and (s := i.get("sub_issues_summary") or {}).get("total") and s["completed"] == s["total"]
                and not any(x["name"] == "wayfinder:map" for x in i["labels"])]

    def report(self, spec, text):
        """A problem found while trying a feature: a new sub-issue of its specification, size S,
        in the queue. Labelled only once linked, so the agent never starts it without the spec."""
        parent = self.gh("GET", f"/issues/{spec}")
        if parent.get("state") != "open" or "pull_request" in parent:
            raise UserError(f"{self.name}#{spec} is not an open issue.")
        text = text.strip()
        first = text.splitlines()[0].strip()
        title = first if len(first) <= 80 else first[:79].rstrip() + "…"
        body = (f"Found while trying the feature of #{spec} on the base branch, reported from the bot:\n\n"
                f"{text}\n\nThe specification, with its scenarios, is the parent issue.")
        issue = self.gh("POST", "/issues", json={"title": title, "body": body})
        self.gh("POST", f"/issues/{spec}/sub_issues", json={"sub_issue_id": issue["id"]})
        self.gh("POST", f"/issues/{issue['number']}/labels", json={"labels": ["ready", "size: S"]})
        self.dispatch()
        return f"Reported as {self.name}#{issue['number']}, a sub-issue of #{spec}, size S, in the queue."

    def apply(self, action, value=""):
        """The actions that need no text, shared by the buttons and the dashboard."""
        if action == "pause":
            self.add(self.control, "paused")
            return f"Queue paused: {self.name}."
        if action == "resume":
            self.rm(self.control, "paused")
            self.dispatch()
            return f"Queue resumed: {self.name}."
        if action == "mode" and value in ("manual", "automatic"):
            return self.set_mode(value)
        if action == "schedule" and value in ("nightly", "always"):
            return self.set_schedule(value)
        if action == "unblock" and value.isdigit():
            return self.restart(int(value))
        raise UserError("I do not know this action.")

    def answer(self, n, text):
        self.comment(n, text)
        self.rm(n, "question open")
        self.dispatch()
        return f"Answer posted on {self.name}#{n}, restarting."

    def set_mode(self, value):
        if value == "automatic":
            self.add(self.control, "auto mode")
        else:
            self.rm(self.control, "auto mode")
        self.dispatch()
        return f"Mode of {self.name} set to {value}."

    def set_schedule(self, value):
        if value == "always":
            self.add(self.control, "always on")
        else:
            self.rm(self.control, "always on")
        self.dispatch()
        return f"Schedule of {self.name} set to {value}."

    def restart(self, n=None):
        """Clears the pause and the blocks of issue n, if any, then restarts."""
        self.rm(self.control, "paused")
        if n:
            self.unblock(n)
        self.dispatch()
        return f"Unblocked {self.name}{f'#{n}' if n else ''}, restarting."

    def hint(self, n, body):
        self.comment(n, f"Hint for the agent: {body.strip()}")
        self.unblock(n)
        self.rm(self.control, "paused")
        self.dispatch()
        return f"Hint added to {self.name}#{n}, restarting."


def not_work_unit(issue):
    """A specification (it has sub-issues) or a wayfinder map or ticket: never built by the agent.
    Same rule as NOT_WORK_UNIT in scripts/lib.sh."""
    return bool((issue.get("sub_issues_summary") or {}).get("total")) \
        or any(x["name"].startswith("wayfinder:") for x in issue["labels"])


def size_of(labels):
    return next((x[6:] for x in labels if x.startswith("size: ")), "M")


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


def tg(method, **payload):
    r = requests.post(f"{TG}/{method}", json=payload, timeout=30)
    if not r.ok:
        print(f"telegram {method}: {r.status_code} {r.text[:300]}", flush=True)


def send(text, markup=None):
    # Telegram shows plain text: a backtick from Markdown (titles, questions) is only noise
    tg("sendMessage", chat_id=CHAT, text=text.replace("`", "")[:4000], **({"reply_markup": markup} if markup else {}))


def send_panels(repos):
    for r in repos:
        try:
            send(*r.panel())
        except Exception as e:  # one repository that cannot be read does not hide the others
            send(f"{r.name}\n{explain(e)}")


def ask_hint(repo, n):
    """Asks for the text of a hint: the answer is a reply to this message, see HINT."""
    send(f"Hint for {repo.name}#{n}: reply to this message with the text.",
         {"force_reply": True, "input_field_placeholder": "Hint for the agent"})


def ask_report(repo, spec):
    """Asks what does not work in a feature: the answer is a reply to this message, see REPORT."""
    send(f"Problem with {repo.name}#{spec}: reply to this message with what does not work, in one sentence.",
         {"force_reply": True, "input_field_placeholder": "What does not work"})


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


USAGE = {
    "/unblock": "/unblock [repo] [n]",
    "/hint": "/hint [repo] <n> <text>",
    "/mode": "/mode [repo] manual | automatic",
    "/schedule": "/schedule [repo] nightly | always",
}


def handle(msg):
    text = (msg.get("text") or "").strip()
    reply = msg.get("reply_to_message")
    context = repo_of(reply)
    if reply and not text.startswith("/"):
        m = HINT.match(reply.get("text") or "")
        if m:
            repo = find(m.group(1))
            if not repo:
                raise UserError(f"I do not follow {m.group(1)}. Repositories: {names()}.")
            return send(repo.hint(int(m.group(2)), text))
        m = REPORT.match(reply.get("text") or "")
        if m:
            repo = find(m.group(1))
            if not repo:
                raise UserError(f"I do not follow {m.group(1)}. Repositories: {names()}.")
            return send(repo.report(int(m.group(2)), text))
        m = QUESTION.match(reply.get("text") or "")
        if not m:
            return send("Replies are accepted only to \"Question on #N\", \"Hint for\" and \"Problem with\" messages.")
        if not context:
            return send("This message does not say which repository it comes from: "
                        "upgrade the engine of that repository to 1.6 or later.")
        return send(context.answer(int(m.group(1)), text))
    cmd, _, arg = text.partition(" ")
    cmd = cmd.split("@")[0]
    if cmd == "/version":
        return send(f"peppec-bot {VERSION}")
    repo, arg = split_repo(arg.strip(), context)
    if cmd in ("/status", "/pause") and arg:
        # A mistyped name must not turn into "all of them"
        raise UserError(f"I do not follow '{arg}'. Repositories: {names()}.")
    if cmd == "/status":
        send_panels([repo] if repo else REPOS)
    elif cmd == "/pause":
        targets = [repo] if repo else REPOS
        for r in targets:
            r.add(r.control, "paused")
        send(f"Queue paused: {', '.join(r.name for r in targets)}.")
    elif cmd in ("/unblock", "/hint", "/mode", "/schedule") and (not repo or (not arg and cmd != "/unblock")):
        # Something is missing: the buttons offer the same choices, with nothing to type
        send(f"{'Which repository? ' if not repo else ''}Use the buttons, or the full command: {USAGE[cmd]}")
        send_panels([repo] if repo else REPOS)
    elif cmd == "/unblock":
        send(repo.restart(int(arg) if arg.isdigit() else repo.active()))
    elif cmd == "/hint":
        num, _, body = arg.partition(" ")
        if not num.isdigit():
            return send(f"Usage: {USAGE[cmd]}")
        if not body.strip():
            return ask_hint(repo, int(num))
        send(repo.hint(int(num), body))
    elif cmd == "/mode":
        if arg not in ("manual", "automatic"):
            return send(f"Usage: {USAGE[cmd]}")
        send(repo.set_mode(arg))
    elif cmd == "/schedule":
        if arg not in ("nightly", "always"):
            return send(f"Usage: {USAGE[cmd]}")
        send(repo.set_schedule(arg))
    else:
        send("Commands: /status [repo], /pause [repo], /unblock [repo] [n], /hint [repo] <n> <text>, "
             "/mode [repo] manual|automatic, /schedule [repo] nightly|always, /version.\n"
             "/status shows buttons for all of them: nothing else to type.\n"
             "Without a repository, /status and /pause apply to all of them. The other commands need it "
             "when there is more than one, unless you send them as a reply to a notification.\n"
             "To answer a question, reply to its message.\n"
             "When a feature is ready to be tried, its message has a \"Report a problem\" button.\n"
             f"Repositories: {names()}.")
    return None


def press(query):
    """A button was pressed. Its data is "action|value|key": key names the repository on the
    panels of /status and is empty on the notifications of the workflows, which start with it."""
    msg = query.get("message") or {}
    action, value, key = ((query.get("data") or "").split("|") + ["", ""])[:3]
    repo = next((r for r in REPOS if r.key == key), None) if key else repo_of(msg)
    if not repo:
        raise UserError("I no longer follow the repository of this message.")
    if action == "hint" and value.isdigit():
        ask_hint(repo, int(value))
        done = "Reply with the text of the hint."
    elif action == "report" and value.isdigit():
        ask_report(repo, int(value))
        done = "Reply with what does not work."
    elif action == "refresh":
        done = "Updated."
    else:
        done = repo.apply(action, value)
    if key:
        text, markup = repo.panel()
        tg("editMessageText", chat_id=CHAT, message_id=msg["message_id"], text=text.replace("`", ""),
           reply_markup=markup)
    elif action not in ("hint", "report"):
        send(done)  # a notification stays as it is: the outcome goes in a new message
    return done


def explain(e):
    if isinstance(e, UserError):
        return str(e)
    if isinstance(e, requests.HTTPError):
        req = e.request
        return f"GitHub error {e.response.status_code} {e.response.reason} on {req.method} {req.url}"
    return f"Error: {e}"


def guarded(action, report):
    with LOCK:
        try:
            report(action())
        except Exception as e:  # report anything instead of failing silently
            report(explain(e))


def safe_handle(msg):
    guarded(lambda: handle(msg), lambda text: text and send(text))


def safe_press(query):
    # Always answered, or the button keeps spinning; the text shows up as a toast
    guarded(lambda: press(query),
            lambda text: tg("answerCallbackQuery", callback_query_id=query["id"], text=text[:200]))


CACHE = {}  # key of a repository -> (time of the reading, its state)


def dashboard_state(fresh=False):
    """The state of every repository as JSON. Each one is read from GitHub at most every
    20 seconds, or every 5 when the page asks for a fresh reading."""
    with LOCK:
        now = time.time()
        for r in REPOS:
            if now - CACHE.get(r.key, (0.0, None))[0] > (5 if fresh else 20):
                try:
                    read = r.state()
                except Exception as e:  # one repository that cannot be read does not hide the others
                    read = {"name": r.name, "key": r.key, "url": f"https://github.com/{r.name}",
                            "error": explain(e)}
                CACHE[r.key] = (time.time(), read)
        # "at" is the oldest reading: the page never claims to be fresher than it is
        data = {"version": VERSION, "at": int(min(CACHE[r.key][0] for r in REPOS)),
                "repos": [CACHE[r.key][1] for r in REPOS]}
        return json.dumps(data).encode()


def dashboard_action(req):
    repo = next((r for r in REPOS if r.key == req.get("repo")), None)
    if not repo:
        raise UserError("I do not follow this repository.")
    action, value = str(req.get("action", "")), str(req.get("value", ""))
    text = str(req.get("text", "")).strip()[:4000]
    with LOCK:
        if action in ("hint", "answer", "report"):
            if not value.isdigit() or not text:
                raise UserError("The text is missing.")
            done = {"hint": repo.hint, "answer": repo.answer, "report": repo.report}[action](int(value), text)
        else:
            done = repo.apply(action, value)
        CACHE.pop(repo.key, None)  # only this repository is read again
        send(f"Dashboard: {done}")  # what the dashboard does leaves a trace in the chat
    return done


def claude_token():
    """The access token of the Claude Code login, and when it expires (seconds)."""
    oauth = json.loads(CREDENTIALS.read_text()).get("claudeAiOauth") or {}
    return oauth.get("accessToken", ""), oauth.get("expiresAt", 0) / 1000


def refresh_claude_login():
    """Claude Code renews an expired access token when it runs: a minimal prompt is enough."""
    try:
        subprocess.run(["claude", "-p", "ok", "--model", "haiku"], cwd="/tmp", timeout=90,
                       capture_output=True, check=False)
    except (OSError, subprocess.TimeoutExpired) as e:
        print("claude refresh failed:", e, flush=True)


def usage_name(limit):
    kind = limit.get("kind", "")
    name = {"session": "Session", "weekly_all": "Week"}.get(kind) or kind.replace("_", " ").capitalize()
    model = ((limit.get("scope") or {}).get("model") or {}).get("display_name")
    return f"Week · {model}" if model else name


def retry_after(r):
    """Seconds Anthropic asks to wait after a 429: Retry-After in seconds, else one minute."""
    try:
        return max(1, min(int(r.headers.get("Retry-After", "")), 3600))
    except ValueError:
        return USAGE_REUSE


def claude_usage():
    """The limits of the Claude subscription, read from Anthropic when the page asks.

    A reading younger than USAGE_REUSE seconds is returned again, and after a 429 nothing is
    asked until Retry-After has passed: the last reading is returned with a note, if there is one.
    """
    if not CREDENTIALS.exists():
        return {"enabled": False}
    with USAGE_LOCK:
        now = time.time()
        last = USAGE_CACHE["last"]
        if last and now - last["at"] < USAGE_REUSE:
            return last
        if now < USAGE_CACHE["wait_until"]:
            return usage_later(last, USAGE_CACHE["wait_until"] - now)
        token, expires = claude_token()
        if expires - time.time() < 60:
            refresh_claude_login()
            token, expires = claude_token()
        if expires - time.time() < 0:
            raise UserError(f"The Claude login has expired: {LOGIN_HINT}.")
        r = requests.get(USAGE_URL, timeout=20, headers={
            "Authorization": f"Bearer {token}", "anthropic-beta": "oauth-2025-04-20"})
        if r.status_code in (401, 403):
            raise UserError(f"Anthropic refused the Claude login ({r.status_code}): {LOGIN_HINT}.")
        if r.status_code == 429:
            wait = retry_after(r)
            USAGE_CACHE["wait_until"] = time.time() + wait
            return usage_later(last, wait)
        r.raise_for_status()
        limits = [{"name": usage_name(x), "percent": x.get("percent"),
                   "warn": x.get("severity", "normal") != "normal", "resets": x.get("resets_at")}
                  for x in r.json().get("limits") or []]
        USAGE_CACHE["last"] = {"enabled": True, "at": int(time.time()), "limits": limits}
        return USAGE_CACHE["last"]


def usage_later(last, wait):
    """Anthropic asked to wait: the last reading with a note, or an error when there is none."""
    note = f"Anthropic asks to wait: try again in {max(1, round(wait))} s."
    if not last:
        raise UserError(note)
    return {**last, "note": note}


class Dashboard(BaseHTTPRequestHandler):
    def reply(self, status, body, kind="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; "
                         "script-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'")
        self.end_headers()
        self.wfile.write(body)

    def error(self, status, text):
        self.reply(status, json.dumps({"error": text}).encode())

    def allowed(self):
        """Everything but the page itself, which holds no data, needs the password."""
        given = unquote(self.headers.get("Authorization", "").removeprefix("Bearer "))
        if hmac.compare_digest(given.encode(), PASSWORD.encode()):
            return True
        time.sleep(1)  # slows down guessing
        self.error(401, "Wrong password.")
        return False

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            return self.reply(200, PAGE.read_bytes(), "text/html; charset=utf-8")
        if self.path == "/api/usage":
            if self.allowed():
                try:
                    self.reply(200, json.dumps(claude_usage()).encode())
                except UserError as e:
                    self.error(502, str(e))
                except requests.RequestException as e:
                    self.error(502, f"Anthropic did not answer: {e}")
                except Exception as e:
                    self.error(502, f"Error: {e}")
            return
        if self.path not in ("/api/state", "/api/state?fresh=1"):
            return self.error(404, "Not found.")
        if self.allowed():
            try:
                self.reply(200, dashboard_state(self.path.endswith("fresh=1")))
            except Exception as e:
                self.error(502, explain(e))

    def do_POST(self):
        if self.path != "/api/action":
            return self.error(404, "Not found.")
        if not self.allowed():
            return
        try:
            size = int(self.headers.get("Content-Length") or 0)
            if not 0 < size <= 20000:
                raise UserError("The request is empty or too long.")
            req = json.loads(self.rfile.read(size))
            if not isinstance(req, dict):
                raise UserError("The request is not an object.")
            self.reply(200, json.dumps({"message": dashboard_action(req)}).encode())
        except UserError as e:
            self.error(400, str(e))
        except Exception as e:
            self.error(502, explain(e))

    def log_message(self, *args):
        pass


def start_dashboard():
    if not PASSWORD:
        return
    server = ThreadingHTTPServer(("0.0.0.0", DASHBOARD_PORT), Dashboard)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"dashboard on port {DASHBOARD_PORT}", flush=True)


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
    start_dashboard()
    tg("setMyCommands", commands=[{"command": c, "description": d} for c, d in COMMANDS])
    offset = load_offset()
    while True:
        try:
            r = requests.get(f"{TG}/getUpdates", timeout=60, params={
                "timeout": 50, "offset": offset, "allowed_updates": '["message","callback_query"]'})
            for u in r.json().get("result", []):
                offset = u["update_id"] + 1
                save_offset(offset)  # saved before handling: an update is never processed twice
                msg = u.get("message")
                if msg and msg["chat"]["id"] == CHAT:
                    safe_handle(msg)
                query = u.get("callback_query")
                if query and (query.get("message") or {}).get("chat", {}).get("id") == CHAT:
                    safe_press(query)
        except requests.RequestException as e:
            print("network error:", e, flush=True)
            time.sleep(10)


if __name__ == "__main__":
    main()
