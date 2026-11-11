import hashlib
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
# The message a "Hint" button asks to reply to
HINT = re.compile(r"^Hint for ([\w.-]+/[\w.-]+)#(\d+):")
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
GH = requests.Session()
GH.headers.update({"Accept": "application/vnd.github+json"})


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
        out.append(f"In queue: {len(self.issues('ready'))}")
        if n:
            rows.append([self.button(f"Unblock #{n}", "unblock", n), self.button(f"Hint #{n}", "hint", n)])
        rows.append([self.button("Refresh", "refresh")])
        return "\n".join(out), {"inline_keyboard": rows}

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
    tg("sendMessage", chat_id=CHAT, text=text[:4000], **({"reply_markup": markup} if markup else {}))


def send_panels(repos):
    for r in repos:
        send(*r.panel())


def ask_hint(repo, n):
    """Asks for the text of a hint: the answer is a reply to this message, see HINT."""
    send(f"Hint for {repo.name}#{n}: reply to this message with the text.",
         {"force_reply": True, "input_field_placeholder": "Hint for the agent"})


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
    if action == "pause":
        repo.add(repo.control, "paused")
        done = f"Queue paused: {repo.name}."
    elif action == "resume":
        repo.rm(repo.control, "paused")
        repo.dispatch()
        done = f"Queue resumed: {repo.name}."
    elif action == "mode" and value in ("manual", "automatic"):
        done = repo.set_mode(value)
    elif action == "schedule" and value in ("nightly", "always"):
        done = repo.set_schedule(value)
    elif action == "unblock" and value.isdigit():
        done = repo.restart(int(value))
    elif action == "hint" and value.isdigit():
        ask_hint(repo, int(value))
        done = "Reply with the text of the hint."
    elif action == "refresh":
        done = "Updated."
    else:
        raise UserError("I do not know this button.")
    if key:
        text, markup = repo.panel()
        tg("editMessageText", chat_id=CHAT, message_id=msg["message_id"], text=text, reply_markup=markup)
    elif action != "hint":
        send(done)  # a notification stays as it is: the outcome goes in a new message
    return done


def guarded(action, report):
    try:
        report(action())
    except UserError as e:
        report(str(e))
    except requests.HTTPError as e:
        req = e.request
        report(f"GitHub error {e.response.status_code} {e.response.reason} on {req.method} {req.url}")
    except Exception as e:  # report anything else instead of failing silently
        report(f"Error: {e}")


def safe_handle(msg):
    guarded(lambda: handle(msg), lambda text: text and send(text))


def safe_press(query):
    # Always answered, or the button keeps spinning; the text shows up as a toast
    guarded(lambda: press(query),
            lambda text: tg("answerCallbackQuery", callback_query_id=query["id"], text=text[:200]))


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
