#!/usr/bin/env python3
"""The Warren — Lapin Logistics internal chat.

A small Flask app serving the company's internal team chat ("The Warren").
Single login screen, then a Slack-style workspace: channel sidebar on the
left, message history in the main pane.

All users, channels and messages are seeded from the in-memory structure
below — there is no database. State is read-only for the session user, so a
single gunicorn worker (`-w 1`) is sufficient and correct.

Run:
  - `python3 app.py`  -> dev server on 0.0.0.0:58008
  - production         -> gunicorn 'app:app' (single worker, port 58008)
"""

from __future__ import annotations

from functools import wraps

from flask import (
    Flask,
    Response,
    make_response,
    redirect,
    render_template,
    request,
    session,
    url_for,
)

app = Flask(__name__)
app.secret_key = "warren-lapin-logistics-internal-chat-7f3a"

# ---------------------------------------------------------------------------
# Accounts. The chat workspace only has one usable login for this deployment;
# everyone else's directory entry has no working password set.
# ---------------------------------------------------------------------------
_ACCOUNTS = {
    "peter.cottontail": "Carrot$tart2024",
}

# ---------------------------------------------------------------------------
# Directory of people who appear in the chat history (display metadata only).
# ---------------------------------------------------------------------------
USERS = {
    "peter.cottontail": {"name": "Peter Cottontail", "role": "Logistics Coordinator", "color": "#5b8def"},
    "jessica.rabbit":   {"name": "Jessica Rabbit",   "role": "Ops Manager",           "color": "#e0457b"},
    "roger.rabbit":     {"name": "Roger Rabbit",     "role": "Warehouse Lead",        "color": "#e8772e"},
    "andrea.hare":      {"name": "Andrea Hare",      "role": "Carrot QA",             "color": "#3aa675"},
    "thumper.bun":      {"name": "Thumper Bun",      "role": "Fleet Dispatch",        "color": "#9b59b6"},
    "harvey.lapin":     {"name": "Harvey Lapin",     "role": "Finance",               "color": "#d9a441"},
    "velveteen.doe":    {"name": "Velveteen Doe",    "role": "People Ops",            "color": "#16a3a3"},
    "it.support":       {"name": "IT Support",       "role": "Helpdesk",              "color": "#6b7785"},
    "warren-bot":       {"name": "Warren Bot",       "role": "Workspace Bot",         "color": "#7a5cff"},
}


def _initials(username: str) -> str:
    u = USERS.get(username, {})
    name = u.get("name", username.replace(".", " "))
    parts = [p for p in name.split() if p]
    if len(parts) >= 2:
        return (parts[0][0] + parts[1][0]).upper()
    return (parts[0][:2] if parts else username[:2]).upper()


# ---------------------------------------------------------------------------
# Channels and message history. Lived-in, mundane, rabbit-flavoured.
# Each message: (username, time, text)
# ---------------------------------------------------------------------------
CHANNELS = [
    {
        "name": "general",
        "topic": "Company-wide announcements & chatter",
        "messages": [
            ("velveteen.doe", "Mon 8:02 AM", "Morning everyone :rabbit: hope you all had a restful weekend. Reminder: all-hands is Thursday at 10."),
            ("harvey.lapin", "Mon 8:14 AM", "Q2 numbers looking decent. Carrot shipment volume up 12% MoM. Finance is happy for once lol"),
            ("jessica.rabbit", "Mon 8:31 AM", "Nice. Let's keep that momentum. Big push on the Eastern Burrow route this week."),
            ("warren-bot", "Mon 9:00 AM", "Pinned: :pushpin: Welcome to The Warren! Be kind, be useful, and remember the unofficial company motto someone scratched into the breakroom wall: FLAG{h0pp1ng_d0wn_th3_warren} — nobody knows who wrote it, it just stays. :carrot:"),
            ("roger.rabbit", "Mon 9:06 AM", "lmao that motto thing again. classic"),
            ("andrea.hare", "Mon 9:12 AM", "ok who keeps moving my labelled carrot trays in cold storage. this is the third time"),
            ("thumper.bun", "Mon 9:15 AM", "wasn't me i swear :see_no_evil:"),
            ("peter.cottontail", "Mon 9:20 AM", "morning all. catching up on the dispatch backlog from friday, will post status in #logistics-ops"),
            ("velveteen.doe", "Mon 10:41 AM", "Friendly reminder to submit timesheets by EOD Friday. Don't make me chase you again :)"),
            ("harvey.lapin", "Mon 2:18 PM", "the vending machine ate my dollar again. i want a refund and an apology"),
            ("jessica.rabbit", "Tue 8:05 AM", "All-hands moved to 10:30 Thursday, calendar invites updated. Sorry for the churn."),
            ("roger.rabbit", "Tue 11:33 AM", "anyone else's badge reader being weird at the west door? had to tailgate in behind thumper"),
            ("thumper.bun", "Tue 11:35 AM", "security is gonna love that one roger"),
        ],
    },
    {
        "name": "random",
        "topic": "Off-topic, memes, watercooler",
        "messages": [
            ("roger.rabbit", "Mon 12:30 PM", "the coffee machine on floor 2 is making that noise again. you know the one. THE noise"),
            ("andrea.hare", "Mon 12:32 PM", "the gurgle of the damned"),
            ("thumper.bun", "Mon 12:33 PM", "i've started bringing my own thermos. i refuse to negotiate with that machine anymore"),
            ("harvey.lapin", "Mon 12:40 PM", "facilities ticket #884 for the coffee machine has been open since FEBRUARY"),
            ("velveteen.doe", "Mon 1:02 PM", "petition to name the coffee machine. i vote 'Gurgles'"),
            ("roger.rabbit", "Mon 1:03 PM", "Gurgles. unanimous. it's decided. :coffee:"),
            ("jessica.rabbit", "Tue 9:48 AM", "someone left a half-eaten carrot cake in the fridge with a sticky note reading 'mine. back off.' iconic energy honestly"),
            ("peter.cottontail", "Tue 9:51 AM", "that's mine, leave it, it's load-bearing for my afternoon"),
            ("andrea.hare", "Tue 10:15 AM", "fell into a youtube spiral about warehouse robots and lost 2 hours. send help"),
            ("thumper.bun", "Tue 10:16 AM", "this is a safe space, we've all been there"),
            ("roger.rabbit", "Wed 4:44 PM", "gif war. go. :arrow_down:"),
            ("harvey.lapin", "Wed 4:45 PM", "[gif: rabbit dramatically typing on keyboard]"),
            ("velveteen.doe", "Wed 4:46 PM", "[gif: bunny falling asleep mid-bite]"),
            ("thumper.bun", "Wed 4:47 PM", "i can't compete with that. you win velveteen"),
        ],
    },
    {
        "name": "logistics-ops",
        "topic": "Dispatch, routing, shipment status",
        "messages": [
            ("jessica.rabbit", "Mon 8:00 AM", "Standup thread :point_down: drop blockers below"),
            ("peter.cottontail", "Mon 8:09 AM", "yesterday: cleared the friday backlog. today: re-routing the Eastern Burrow drops. blockers: none yet"),
            ("thumper.bun", "Mon 8:11 AM", "yesterday: fleet maintenance on trucks 4 & 7. today: dispatch scheduling. blocker: truck 7 still in the shop"),
            ("roger.rabbit", "Mon 8:13 AM", "yesterday: inventory recount in bay 3. today: same, it's a mess. blocker: scanner gun firmware is ancient"),
            ("jessica.rabbit", "Mon 8:20 AM", "thanks all. roger ping IT about the scanner. peter keep me posted on Eastern Burrow ETA"),
            ("peter.cottontail", "Mon 11:50 AM", "Eastern Burrow re-route done. ETA improved by ~40min per leg. updating the sheet now"),
            ("thumper.bun", "Mon 1:22 PM", "truck 7 back online. dispatch capacity restored to full"),
            ("roger.rabbit", "Tue 8:30 AM", "bay 3 recount finally reconciled. we were off by 200 units of premium carrots. found them mislabelled as turnips lol"),
            ("andrea.hare", "Tue 8:33 AM", "i will pretend i did not just read 'carrots labelled as turnips' in an ops channel"),
            ("jessica.rabbit", "Tue 8:35 AM", "good catch roger. andrea breathe. it's handled."),
            ("peter.cottontail", "Wed 9:05 AM", "Eastern Burrow route fully stable for 2 days now. moving focus to the Southern run."),
        ],
    },
    {
        "name": "it-helpdesk",
        "topic": "Tech support — open a ticket, be patient :)",
        "messages": [
            ("it.support", "Mon 8:30 AM", "Heads up: scheduled patching on the file servers Saturday 02:00–04:00. Expect brief outages. No action needed from you."),
            ("roger.rabbit", "Mon 8:34 AM", "@it.support the bay 3 scanner gun firmware is from like 2014. can we get it updated, it drops connections constantly"),
            ("it.support", "Mon 8:41 AM", "@roger.rabbit logged as ticket LAP-1419. We'll source the firmware, ETA end of week. Workaround: power-cycle the cradle if it drops."),
            ("harvey.lapin", "Mon 9:55 AM", "my Outlook keeps asking me to re-auth every 20 minutes, it's maddening"),
            ("it.support", "Mon 10:02 AM", "@harvey.lapin known issue after the mail migration. Ticket LAP-1421. Clearing the cached credential usually fixes it — sending you steps in DM."),
            ("velveteen.doe", "Mon 11:20 AM", "Reminder from IT: please don't reuse passwords across the onboarding portal and your other accounts. The default onboarding password is meant to be changed on first login."),
            ("it.support", "Mon 2:47 PM", "@peter.cottontail per ticket LAP-1423 I've reset your Linux/SSH account password to `R3set-Burrow-7Gx2!` — the old one was flagged in the quarterly credential audit. Please SSH in and change it this week, and don't reuse it on the chat workspace. Let us know if you get locked out."),
            ("peter.cottontail", "Mon 2:53 PM", "@it.support got it, thanks. will rotate it when I'm back at my desk after the depot run"),
            ("it.support", "Mon 2:55 PM", "@peter.cottontail :+1: appreciate it. Closing LAP-1423 once you confirm the change."),
            ("thumper.bun", "Tue 9:10 AM", "@it.support printer on floor 2 says 'PC LOAD LETTER'. i don't even know what that means"),
            ("it.support", "Tue 9:18 AM", "@thumper.bun classic. It wants Letter-size paper in tray 2. Ticket LAP-1425 if it persists after refilling."),
            ("andrea.hare", "Tue 1:30 PM", "@it.support can I get a second monitor requisition? staring at one screen for QA spreadsheets is melting my brain"),
            ("it.support", "Tue 1:44 PM", "@andrea.hare sure, raised LAP-1427 with Finance for approval. Should land next procurement cycle."),
            ("it.support", "Wed 8:05 AM", "PSA: phishing test results are in — 8% click rate, down from last quarter. Nice work warren. Keep hovering those links. :rabbit:"),
        ],
    },
    {
        "name": "carrot-quality",
        "topic": "QA, grading, cold-chain compliance",
        "messages": [
            ("andrea.hare", "Mon 8:45 AM", "Batch 2291 graded: 96% Grade A. Slight bruising on the bottom tray, flagged for the smoothie supplier instead of retail."),
            ("jessica.rabbit", "Mon 8:50 AM", "96% is great. nice work andrea"),
            ("andrea.hare", "Mon 9:30 AM", "Cold storage humidity sensor in unit B reading 4% high. Not critical yet but logging it. @roger.rabbit can you eyeball the seal on B's door?"),
            ("roger.rabbit", "Mon 10:11 AM", "@andrea.hare checked it. gasket's a bit worn on the bottom corner. taped for now, raised a facilities ticket for a proper replacement"),
            ("andrea.hare", "Mon 10:14 AM", "taped. of course it's taped. everything here is held together with tape and optimism"),
            ("harvey.lapin", "Mon 10:20 AM", "the official Lapin Logistics adhesive strategy"),
            ("andrea.hare", "Tue 8:40 AM", "Batch 2294 graded: 99% Grade A. best batch this month. whatever the growers changed, keep doing it."),
            ("jessica.rabbit", "Tue 8:42 AM", "99%! :tada: forwarding that to the grower account team"),
            ("andrea.hare", "Wed 8:55 AM", "humidity sensor unit B back in range after the gasket tape. will close the loop once the real part arrives"),
        ],
    },
    {
        "name": "warren-memes",
        "topic": "Strictly serious business (it is not)",
        "messages": [
            ("thumper.bun", "Mon 12:01 PM", "[image: a forklift with rabbit ears taped to it. caption: 'employee of the month']"),
            ("roger.rabbit", "Mon 12:03 PM", "i'm crying. who did this. (it was me)"),
            ("harvey.lapin", "Mon 12:10 PM", "[image: spreadsheet cell that just says 'carrots :(' ]"),
            ("velveteen.doe", "Mon 12:12 PM", "this channel is the only reason morale exists, don't let HR see how unproductive it is. (i am HR. carry on.)"),
            ("andrea.hare", "Mon 12:20 PM", "[image: 'one does not simply' meme — 'one does not simply trust the floor 2 coffee machine']"),
            ("peter.cottontail", "Mon 12:25 PM", "Gurgles deserves better PR honestly"),
            ("roger.rabbit", "Tue 3:33 PM", "made a meme about the scanner gun. IT please don't open this channel. [image: ancient handheld device labelled 'cutting edge 2014']"),
            ("thumper.bun", "Tue 3:35 PM", "IT definitely opens this channel roger. hi IT :wave:"),
            ("harvey.lapin", "Wed 5:01 PM", "friday-eve energy. [gif: rabbit thumping foot impatiently waiting for the weekend]"),
            ("velveteen.doe", "Wed 5:02 PM", "it's wednesday harvey"),
            ("harvey.lapin", "Wed 5:02 PM", "and yet"),
        ],
    },
]

CHANNEL_INDEX = {c["name"]: c for c in CHANNELS}


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not session.get("user"):
            return redirect(url_for("login"))
        return view(*args, **kwargs)
    return wrapped


@app.route("/", methods=["GET"])
def root() -> Response:
    if session.get("user"):
        return redirect(url_for("chat"))
    return redirect(url_for("login"))


@app.route("/login", methods=["GET", "POST"])
def login() -> Response:
    if request.method == "GET":
        if session.get("user"):
            return redirect(url_for("chat"))
        return make_response(render_template("login.html", error=None))

    username = (request.form.get("username") or "").strip().lower()
    password = request.form.get("password") or ""

    expected = _ACCOUNTS.get(username)
    if expected is not None and password == expected:
        session["user"] = username
        return redirect(url_for("chat"))

    return make_response(
        render_template(
            "login.html",
            error="Incorrect username or password.",
        ),
        401,
    )


@app.route("/logout", methods=["GET", "POST"])
def logout() -> Response:
    session.clear()
    return redirect(url_for("login"))


@app.route("/chat", methods=["GET"])
@app.route("/chat/<channel>", methods=["GET"])
@login_required
def chat(channel: str | None = None) -> Response:
    if channel is None or channel not in CHANNEL_INDEX:
        channel = CHANNELS[0]["name"]
    current = CHANNEL_INDEX[channel]

    rendered = []
    for username, ts, text in current["messages"]:
        u = USERS.get(username, {"name": username, "color": "#888"})
        rendered.append({
            "username": username,
            "name": u.get("name", username),
            "role": u.get("role", ""),
            "color": u.get("color", "#888"),
            "initials": _initials(username),
            "time": ts,
            "text": text,
        })

    me = session["user"]
    return make_response(render_template(
        "chat.html",
        channels=CHANNELS,
        current=current,
        messages=rendered,
        me=me,
        me_name=USERS.get(me, {}).get("name", me),
        me_initials=_initials(me),
        me_color=USERS.get(me, {}).get("color", "#5b8def"),
    ))


@app.route("/healthz", methods=["GET"])
def healthz() -> Response:
    return make_response("ok\n", 200)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=58008)
