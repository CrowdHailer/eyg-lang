#!/usr/bin/env python3
"""Render a narrated, captioned walkthrough from verified Gleam capture data.

Dependencies: Pillow, libespeak-ng, and ffmpeg with libx264/AAC support.
The UI is an illustration. Git commits and authorization outcomes are captured
by capture.mjs from the real local repository and EYG evaluator.
"""
import argparse
import ctypes
import ctypes.util
import json
import math
import re
import subprocess
import wave
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "output"
W, H, FPS = 1920, 1080, 24
BG = "#0b1020"
PANEL = "#121c30"
LINE = "#29384f"
TEXT = "#edf4ff"
MUTED = "#a1b2ce"
GREEN = "#60e3b0"
RED = "#ff8594"
BLUE = "#8db9ff"
YELLOW = "#ffd484"


@lru_cache(maxsize=128)
def font(size, mono=False, bold=False):
    name = "DejaVuSansMono" if mono else "DejaVuSans"
    path = Path("/usr/share/fonts/truetype/dejavu") / (name + ("-Bold" if bold else "") + ".ttf")
    return ImageFont.truetype(str(path), size)


def label(d, xy, value, size=28, fill=TEXT, mono=False, bold=False):
    d.text(xy, str(value), font=font(size, mono, bold), fill=fill)


def wrap(d, text, size, width, mono=False):
    lines, line = [], ""
    for word in text.split():
        candidate = (line + " " + word).strip()
        if d.textlength(candidate, font=font(size, mono)) > width and line:
            lines.append(line)
            line = word
        else:
            line = candidate
    if line:
        lines.append(line)
    return lines


def paragraph(d, xy, text, size=28, width=580, fill=MUTED, line_height=None):
    x, y = xy
    for line in wrap(d, text, size, width):
        label(d, (x, y), line, size, fill)
        y += line_height or size * 1.5
    return y


def box(d, rect, fill=PANEL, outline=LINE, radius=18):
    d.rounded_rectangle(rect, radius=radius, fill=fill, outline=outline, width=2)


def pill(d, x, y, text, color=GREEN, size=20):
    width = int(d.textlength(text, font=font(size, bold=True))) + 32
    box(d, (x, y, x + width, y + 40), "#18263a", color, 10)
    label(d, (x + 16, y + 7), text, size, color, bold=True)
    return width


def panel(d, rect, title):
    box(d, rect)
    x, y, r, _ = rect
    d.line((x, y + 57, r, y + 57), fill=LINE, width=2)
    label(d, (x + 25, y + 17), title, 21, MUTED, mono=True)


def code(d, rect, title, source, progress=1.0, size=24):
    panel(d, rect, title)
    x, y, right, bottom = rect
    visible = source[:int(len(source) * min(1, max(0, progress)))]
    lines = visible.split("\n")
    tokenizer = re.compile(r'("[^"\n]*"|//[^\n]*|\b(?:let|var|rule|resolve|fact|match|pub|fn)\b|![a-z_]+|\b[A-Z][A-Za-z]+\b|\b\d+\b)')
    for i, line in enumerate(lines):
        yy = y + 80 + i * (size + 9)
        if yy + size > bottom - 18:
            break
        label(d, (x + 20, yy), f"{i + 1:2}", size - 4, "#5b7396", mono=True)
        xx = x + 72
        for token in tokenizer.split(line):
            color = TEXT
            if token.startswith('"'):
                color = "#c4b0ff"
            elif token.startswith("//"):
                color = "#7995a9"
            elif token in ("let", "var", "rule", "resolve", "fact", "match", "pub", "fn") or token.startswith("!"):
                color = GREEN
            elif token[:1].isupper() or token.isdigit():
                color = YELLOW
            label(d, (xx, yy), token, size, color, mono=True)
            xx += d.textlength(token, font=font(size, True))
        if i == len(lines) - 1 and progress < 1:
            d.rectangle((xx + 2, yy + 2, xx + 5, yy + size + 2), fill=GREEN)


def button(d, rect, title, active=True):
    box(d, rect, "#24614e" if active else "#243049", GREEN if active else LINE, 12)
    x, y, r, b = rect
    width = d.textlength(title, font=font(27, bold=True))
    label(d, ((x + r - width) / 2, (y + b) / 2 - 18), title, 27, bold=True)


def pointer(d, x, y, click=False):
    if click:
        d.ellipse((x - 25, y - 25, x + 25, y + 25), outline=GREEN, width=3)
    d.polygon([(x, y), (x + 3, y + 32), (x + 12, y + 23), (x + 23, y + 37),
               (x + 29, y + 33), (x + 18, y + 20), (x + 32, y + 17)],
              fill="white", outline=BG)


def scalar(fields, name, fallback=""):
    value = fields.get(name, fallback)
    try:
        return str(json.loads(value))
    except (ValueError, TypeError):
        return str(value)


def resource_path(fields):
    raw = fields.get("resource", "")
    match = re.search(r'path: "([^"]+)"', raw)
    return match.group(1) if match else scalar(fields, "resource")


def proof_text(node):
    """Readable projections of captured engine evidence; no invented nodes."""
    fields = node["fields"]
    who = scalar(fields, "actor")
    tenant = scalar(fields, "tenant")
    if node["kind"] == "rule":
        action = scalar(fields, "action", "infer")
        return node["title"], f"{tenant} / {who}  ·  {action} {resource_path(fields)}"
    if node["title"] == "Member":
        return "FACT · Member", f"{tenant} / {who} belongs to {scalar(fields, 'role')}"
    if node["title"] == "RolePermission":
        return "FACT · RolePermission", (f"{scalar(fields, 'role')} may {scalar(fields, 'action')} {resource_path(fields)}\n"
                f"policy: {scalar(fields, 'policy')}")
    if node["title"] in ("Quota", "Usage"):
        key = "limit" if node["title"] == "Quota" else "used"
        return "FACT · " + node["title"], (f"{who}  ·  {resource_path(fields)}  ·  {key} = {scalar(fields, key)}\n"
                f"workspace: {tenant}  ·  window: {scalar(fields, 'window')}")
    if node["kind"] == "predicate":
        source = node["source"]
        if "int_compare(used, limit)" in source:
            title = f"{scalar(fields, 'used')} < {scalar(fields, 'limit')} = True"
        elif source == "nonnegative(used)":
            title = f"{scalar(fields, 'used')} >= 0 = True"
        elif source == '!equal(action, "infer")':
            title = f'action = "{scalar(fields, "action")}" = True'
        else:
            title = "Predicate returned True"
        return "CHECK · " + title, source
    return node["title"], ", ".join(f"{key}={value}" for key, value in fields.items())


def proof_panel(d, rect, heading, root, fraction, compact=False):
    panel(d, rect, heading)
    x, y, right, bottom = rect
    nodes = []

    def visit(node, depth):
        nodes.append((node, depth))
        for child in node["children"]:
            visit(child, depth + 1)

    visit(root, 0)
    gap = 20 if len(nodes) <= 3 else 8
    height = min(154 if not compact else 145,
                 (bottom - y - 93 - gap * (len(nodes) - 1)) / len(nodes))
    emphasis = min(len(nodes) - 1, int(fraction * len(nodes)))
    for n, (node, depth) in enumerate(nodes):
        left = x + 28 + depth * 38
        top = y + 79 + n * (height + gap)
        if depth:
            d.line((left - 20, y + 79 + height, left - 20, top + 25), fill=GREEN, width=2)
            d.line((left - 20, top + 25, left, top + 25), fill=GREEN, width=2)
        box(d, (left, top, right - 25, top + height),
            "#18362d" if n == emphasis else "#101e2d",
            GREEN if n == emphasis or n == 0 else LINE, 12)
        title, detail = proof_text(node)
        size = 22 if len(nodes) > 3 else 23 if compact else 28
        label(d, (left + 18, top + 12), title, size, GREEN, bold=True)
        yy = top + (43 if len(nodes) > 3 else 48)
        detail_size = 18 if len(nodes) > 3 else 19 if compact else 24
        for part in detail.split("\n"):
            for line in wrap(d, part, detail_size, right - left - 65):
                if yy + detail_size <= top + height - 6:
                    label(d, (left + 18, yy), line, detail_size, TEXT)
                    yy += detail_size + (4 if len(nodes) > 3 else 7)


def action_tree(trees, action):
    return next(tree for tree in trees if scalar(tree["fields"], "action") == action)


SCENES = [
    ("intro", "One policy. Every decision.",
     "Let's build access policies with Gleam and E Y G. We will sign in, create commits, approve changes, and limit inference usage. For every allowed policy decision, the engine will now show its actual proof tree."),
    ("rule", "Write the relationship rule",
     "First, write the E Y G rule. Join a user's channel membership with a role permission. Tenant, actor, action, and resource come from the authenticated request. A matching row is the permission proof."),
    ("grants", "Choose who can do what",
     "Now write the Gleam grants. Platform members may open the deployments page, change infrastructure files, and approve those changes. These are separate permissions. Unknown paths are denied by default."),
    ("login", "Sign in as Ada",
     "Ada chooses Sign in with Slack. Our mock completes the login flow. The Gleam host checks single use state, browser binding, nonce, workspace, and expiry. Ada then links her GitHub identity."),
    ("pages", "Enforce the page permission",
     "Ada belongs to Platform, so deployments returns two hundred. Finance returns four oh three. These results come from the actual E Y G evaluator. The protected data loader runs only after authorization."),
    ("proof_page", "Why Ada is allowed: the page proof",
     "Read the engine generated tree from the leaves upward. The Member fact puts Ada in Platform. The Role Permission fact lets Platform view deployments. Rule zero joins those exact facts and produces Permit. Session checks are performed separately by the host."),
    ("commit", "Create a real commit",
     "In an isolated local Git repository, Ada increases the worker replicas from two to three. We inspect the diff, stage the file, and commit. This is a real commit; the main project history is untouched."),
    ("blocked", "Open the pull request",
     "The mock pull request points to that exact commit. Ada has permission to change infrastructure. But there is no eligible approval yet, so the channel policy check blocks merging."),
    ("wrong", "An approval must carry permission",
     "Cal approves the pull request. Cal belongs to Finance, not Platform. The approval exists, but it cannot authorize this infrastructure change. The check stays blocked."),
    ("approve", "Bea approves the current commit",
     "Bea signs in and approves the current head. She belongs to Platform. Both submitter and reviewer permissions now have proofs, and the mock check succeeds. GitHub must require this check to enforce it."),
    ("proof_pr", "Why this PR passes: two permission trees",
     "The passing pull request has two engine generated trees. Ada's membership joins the infrastructure change grant. Bea's membership joins the infrastructure approval grant. The host additionally verifies the linked GitHub identities, the current commit approval, and coverage of every changed path."),
    ("newcommit", "A new commit needs a new approval",
     "Ada creates a second real commit, increasing replicas to four. Bea's earlier approval names the old commit. The current head has changed, so the policy blocks the pull request again."),
    ("reapprove", "Review the updated change",
     "Bea reviews the new commit and approves again. The current head now has an eligible approval, so both permission checks pass."),
    ("proof_reapproved", "New head. Fresh evaluation. Explained allow.",
     "Here are the proof trees returned by the new evaluation. Both memberships and grants still hold. The host now associates Bea's fresh review with the new commit. The same policy facts explain access, while the host enforces commit specific approval."),
    ("revoke", "Membership controls ongoing access",
     "Now remove Bea from Platform and refresh membership. Reevaluating the same pull request removes her approval's authority. The check fails. Production webhooks or scheduled refreshes must trigger this reevaluation."),
    ("quota_rule", "Add an LLM inference quota",
     "Here is a second E Y G policy. Match trusted usage and quota facts for the same workspace, user, endpoint, and billing window. Only permit inference when usage is nonnegative and strictly below the limit."),
    ("quota", "Query the model below the limit",
     "Ada has used forty nine of fifty inference requests. The policy allows the next request. Let's inspect the full engine generated proof before forwarding anything to the model."),
    ("proof_quota", "Why inference is allowed: facts plus predicates",
     "The quota is fifty and usage is forty nine, for the same user, endpoint, and billing window. Three predicates passed: the action is inference, usage is nonnegative, and forty nine is less than fifty. These are actual recorded guard results, with their bound values."),
    ("quota_denied", "At the limit, there is no permit tree",
     "Once the allowed request is reserved, usage reaches fifty. Fifty is not less than fifty, so the next call has no Permit row and no successful proof tree. The gateway must reserve usage atomically before calling the model."),
    ("outro", "Try it, then connect the adapters",
     "Proof trees now come from the Datalog engine, alongside its ordinary answers. Run the Gleam examples to inspect them. Slack and GitHub are still mocked, and the interface is illustrated. The video includes captured proof data and a readable transcript."),
]


def synthesize(scenes):
    libname = ctypes.util.find_library("espeak-ng") or ctypes.util.find_library("espeak")
    if not libname:
        raise RuntimeError("Install libespeak-ng for offline narration")
    lib = ctypes.CDLL(libname)
    lib.espeak_Initialize.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
    rate = lib.espeak_Initialize(2, 0, None, 0)
    if rate <= 0:
        raise RuntimeError("Cannot initialize speech synthesis")
    callback_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.POINTER(ctypes.c_short), ctypes.c_int, ctypes.c_void_p)
    chunks = []

    @callback_type
    def callback(samples, count, _events):
        if samples and count > 0:
            chunks.append(ctypes.string_at(samples, count * 2))
        return 0

    lib.espeak_SetSynthCallback(callback)
    lib.espeak_SetVoiceByName(b"en-gb")
    lib.espeak_SetParameter(1, 163, 0)
    lib.espeak_SetParameter(2, 90, 0)
    lib.espeak_Synth.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint, ctypes.c_int,
                               ctypes.c_uint, ctypes.c_uint, ctypes.c_void_p, ctypes.c_void_p]
    pcm, timeline = bytearray(), []
    for key, title, speech in scenes:
        chunks.clear()
        buffer = ctypes.create_string_buffer(speech.encode("utf8"))
        status = lib.espeak_Synth(buffer, len(buffer), 0, 1, 0, 1, None, None)
        if status != 0:
            raise RuntimeError(f"Speech synthesis failed: {status}")
        lib.espeak_Synchronize()
        audio = b"".join(chunks)
        spoken = len(audio) / (rate * 2)
        start = len(pcm) / (rate * 2)
        duration = math.ceil((spoken + 1.8) * FPS) / FPS
        pcm.extend(b"\0" * round(rate * .5) * 2)
        pcm.extend(audio)
        pcm.extend(b"\0" * (round((start + duration) * rate) * 2 - len(pcm)))
        timeline.append(dict(key=key, title=title, speech=speech, start=start, duration=duration, spoken=spoken))
    with wave.open(str(OUT / "narration.wav"), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(pcm)
    return timeline


def subtitle_chunks(scene):
    sentences = re.split(r"(?<=[.!?])\s+", scene["speech"])
    total = sum(len(sentence) for sentence in sentences)
    elapsed = scene["start"] + .5
    chunks = []
    for sentence in sentences:
        length = scene["spoken"] * len(sentence) / total
        chunks.append((elapsed, elapsed + length, sentence))
        elapsed += length
    return chunks


def timecode(seconds, srt=False):
    ms = round(seconds * 1000)
    hours, ms = divmod(ms, 3600000)
    minutes, ms = divmod(ms, 60000)
    secs, ms = divmod(ms, 1000)
    return f"{hours:02}:{minutes:02}:{secs:02}{',' if srt else '.'}{ms:03}"


def render_scene(scene, local, data, index, total, subtitle):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    label(d, (64, 34), "EYG / POLICY LAB", 23, GREEN, bold=True)
    pill(d, 1240, 29, "ILLUSTRATED UI  /  MOCK PROVIDERS", BLUE, 18)
    label(d, (64, 102), scene["title"], 48, bold=True)
    label(d, (66, 166), f"{index + 1:02} / {len(SCENES):02}     GLEAM HOST + EYG DATALOG", 18, MUTED)
    key = scene["key"]
    fraction = local / scene["duration"]
    typing = min(1, local / min(7, scene["duration"] * .48))
    head, head2 = data["head"][:7], data["nextHead"][:7]
    facts = data["facts"]

    if key in ("intro", "outro"):
        cards = [("01", "WRITE", "Relationships + explicit grants"),
                 ("02", "SIGN IN", "Slack identity + channel membership"),
                 ("03", "REVIEW", "Commit-specific authorization")]
        for n, (num, title, body) in enumerate(cards):
            x = 64 + n * 605
            box(d, (x, 254, x + 575, 594))
            label(d, (x + 34, 285), num, 65, GREEN)
            label(d, (x + 34, 388), title, 35, bold=True)
            paragraph(d, (x + 34, 457), body, 26, 505)
        if key == "intro":
            box(d, (64, 634, 1856, 866), "#142937", "#28574e")
            label(d, (103, 665), "+ ENGINE-GENERATED PROOF TREES", 28, GREEN, bold=True)
            label(d, (103, 726), "Every allowed policy decision has a reason", 39, bold=True)
            label(d, (103, 800), "Real evaluator results  ·  Real local commits  ·  Mock Slack and GitHub", 25, MUTED)
        else:
            code(d, (64, 635, 1130, 870), "Run from packages/channel_policy", "gleam run --runtime bun\ngleam test --runtime bun", 1, 31)
            paragraph(d, (1190, 663), "Source, replay page, captions and verified scenario data are included.", 30, 610, TEXT)
            paragraph(d, (1190, 778), "See video/README.md", 25, 610, GREEN)
    elif key.startswith("proof_"):
        if key in ("proof_pr", "proof_reapproved"):
            proofs = facts["reapproved_proofs"] if key == "proof_reapproved" else facts["approved_proofs"]
            commit = head2 if key == "proof_reapproved" else head
            proof_panel(d, (64, 228, 950, 815), "ADA / SUBMITTER PERMISSION",
                        action_tree(proofs, "change"), fraction, True)
            proof_panel(d, (974, 228, 1856, 815), "BEA / REVIEWER PERMISSION",
                        action_tree(proofs, "approve"), fraction, True)
            label(d, (80, 842), f"HOST CHECKS: linked identities · eligible approval on {commit} · all changed paths covered", 25, MUTED)
        elif key == "proof_page":
            proof_panel(d, (64, 228, 1210, 885), "ENGINE TRACE / Permit",
                        facts["page_proof"], fraction)
            label(d, (1250, 274), "ALLOWED BECAUSE", 28, GREEN, bold=True)
            paragraph(d, (1250, 345), "Ada's Platform membership matches a grant to view /deployments.", 32, 560, TEXT)
            paragraph(d, (1250, 530), "Two fact leaves. One joining rule. One Permit answer.", 29, 560)
            paragraph(d, (1250, 700), "Host checks: valid session and fresh membership snapshot.", 26, 560)
        else:
            proof_panel(d, (64, 228, 1230, 906), "ENGINE TRACE / Permit + evaluated predicates",
                        facts["inference_proof"], fraction)
            label(d, (1270, 274), "ALLOWED BECAUSE", 28, GREEN, bold=True)
            label(d, (1270, 353), "49 < 50", 67, GREEN, bold=True)
            paragraph(d, (1270, 468), "The matching quota and usage facts satisfy every guard.", 31, 540, TEXT)
            paragraph(d, (1270, 646), "Predicate source and bound values are recorded by the evaluator.", 27, 540)
            paragraph(d, (1270, 785), "Reserve usage atomically before forwarding.", 25, 540)
    elif key in ("rule", "grants", "quota_rule"):
        if key == "rule":
            source = data["source"].split("\n", 1)[1].strip()
            title = "policies/rbac.eyg"
            heading, bullets = "A proof is a join", ["Member: who belongs", "RolePermission: what is allowed", "Permit: evidence for this request", "No matching row means DENY"]
            size = 22
        elif key == "grants":
            source, title, size = data["grants"], "mock.gleam / rules()", 22
            heading, bullets = "Platform channel", ["View /deployments", "Change infra/ files", "Approve infra/ files", "Three explicit grants"]
        else:
            lines = data["quotaSource"].splitlines()
            source = "\n".join(line.strip() for line in lines if any(token in line for token in
                ["var policy", "Quota({", "Usage({", '!equal(action', "nonnegative(used),", "!equal(!int_compare(used, limit)"]))
            title, size = "policies/llm_quota.eyg / rule body", 23
            heading, bullets = "Same scope, fresh meter", ["Workspace + user", "Endpoint + billing window", "Usage is nonnegative", "Strict comparison: used < limit"]
        code(d, (64, 228, 1190, 890), title, source, typing, size)
        label(d, (1234, 267), heading, 32, GREEN, bold=True)
        for n, text in enumerate(bullets):
            pill(d, 1236, 345 + n * 103, f"{n + 1:02}", BLUE)
            paragraph(d, (1308, 345 + n * 103), text, 26, 510, TEXT)
        if key == "quota_rule":
            label(d, (1236, 797), "49 < 50  →  PERMIT", 30, GREEN, mono=True)
    elif key == "login":
        panel(d, (64, 228, 1005, 890), "console.local / sign-in — mock screen")
        label(d, (283, 344), "Welcome to Acme", 42, bold=True)
        paragraph(d, (266, 420), "Use your Slack account to continue.", 27, 590)
        button(d, (272, 504, 794, 580), "Sign in with Slack")
        pointer(d, 623, 554, .24 < fraction < .43)
        label(d, (306, 649), "Workspace   Acme / T_ACME", 24, MUTED)
        label(d, (306, 699), "Member      Ada / U_ADA", 24, MUTED)
        if fraction > .42:
            pill(d, 330, 784, "SIGNED IN AS ADA")
        label(d, (1072, 269), "Host login checks", 35, GREEN, bold=True)
        checks = ["State consumed once", "Browser binding matches", "Nonce and workspace match", "Session expiry checked", "GitHub account 101 linked"]
        for n, text in enumerate(checks):
            if fraction > .12 + n * .11:
                label(d, (1090, 359 + n * 85), "✓", 34, GREEN)
                label(d, (1142, 362 + n * 85), text, 28)
        label(d, (1080, 830), "OIDC exchange is mocked", 23, MUTED)
    elif key == "pages":
        for n, (route, status, permitted, detail) in enumerate([
            ("/deployments", facts["deployments_status"], True, "Platform membership grants access"),
            ("/finance", facts["finance_status"], False, "Ada has no Finance membership")]):
            x = 64 + n * 912
            panel(d, (x, 248, x + 880, 821), "console.local" + route)
            label(d, (x + 42, 359), str(status), 110, GREEN if permitted else RED, bold=True)
            label(d, (x + 46, 507), "ACCESS ALLOWED" if permitted else "ACCESS DENIED", 31, bold=True)
            paragraph(d, (x + 46, 584), detail, 30, 775)
            label(d, (x + 46, 733), "EYG result • authenticated user U_ADA", 22, MUTED)
    elif key in ("commit", "newcommit"):
        new = key == "newcommit"
        before, after = (3, 4) if new else (2, 3)
        code(d, (64, 228, 1856, 464), "infra/main.tf — real local diff",
             f" locals {{\n-  replicas = {before}\n+  replicas = {after}\n }}", 1, 28)
        commit = data["secondCommit"] if new else data["firstCommit"]
        commands = ("$ git diff -- infra/main.tf\n$ git add infra/main.tf\n"
                    f'$ git commit -m "Scale workers to {"four" if new else "three"} replicas"\n\n{commit}')
        code(d, (64, 489, 1856, 890), "terminal / isolated demo repository", commands, typing, 27)
        if fraction > .6:
            pill(d, 1420, 518, "COMMIT " + (head2 if new else head), GREEN)
    elif key in ("blocked", "wrong", "approve", "reapprove", "revoke"):
        is_new = key in ("reapprove", "revoke")
        commit = head2 if is_new else head
        success = key in ("approve", "reapprove") and fraction > .4
        reviewer = "Cal" if key == "wrong" else "Bea"
        panel(d, (64, 228, 1856, 890), "github.mock / acme/app / pull/42")
        label(d, (104, 319), "Scale workers", 43, bold=True)
        pill(d, 451, 323, "OPEN #42", GREEN)
        label(d, (104, 389), f"Ada wants to merge  ada/scale-workers → main   ·   {commit}", 27, MUTED)
        box(d, (104, 464, 1122, 666), "#0d1627")
        label(d, (137, 488), "Files changed", 23, MUTED)
        label(d, (137, 537), "infra/main.tf", 34, mono=True)
        label(d, (137, 593), "+ 1 line     − 1 line", 23, GREEN, mono=True)
        pill(d, 1158, 471, "SUBMITTER: ALLOWED", GREEN)
        if key == "blocked":
            review_text = "No review submitted"
        elif key == "wrong":
            review_text = "Cal approved · Finance member"
        elif key == "revoke":
            review_text = "Bea left Platform · refreshed"
        else:
            review_text = f"{reviewer} approves {commit}" if success else f"Signed in as {reviewer}"
        paragraph(d, (1160, 545), review_text, 29, 630, TEXT)
        if key in ("approve", "reapprove"):
            button(d, (1160, 638, 1787, 707), "Approved" if success else "Approve current commit")
            if not success:
                pointer(d, 1599, 680, True)
        else:
            pill(d, 1160, 644, "REVIEWER: NOT AUTHORIZED" if key != "blocked" else "REVIEWER: REQUIRED", RED, 19)
        color = GREEN if success else RED
        box(d, (104, 736, 1814, 850), "#122c26" if success else "#321d2c", color)
        label(d, (139, 758), "✓" if success else "×", 45, color)
        label(d, (202, 766), "channel-policy", 31, bold=True)
        label(d, (591, 770), "SUCCESS — both permission proofs exist" if success else "BLOCKED — eligible approval required", 29, color)
    elif key in ("quota", "quota_denied"):
        at_limit = key == "quota_denied"
        used = 50 if at_limit else 49
        permitted = facts["inference_at_limit"] if at_limit else facts["inference_below_limit"]
        panel(d, (64, 228, 1164, 890), "console.local / inference — mock gateway")
        label(d, (104, 329), "POST /v1/inference", 39, mono=True, bold=True)
        label(d, (104, 397), "Ada / T_ACME     ·     Billing window: 2026-10", 25, MUTED)
        box(d, (104, 467, 1124, 593), "#0d1627")
        label(d, (134, 491), "Summarize this deployment change.", 29)
        button(d, (104, 644, 1124, 724), "Query model" if permitted else "Usage limit reached", permitted)
        label(d, (108, 776), "PERMIT — reserve request, then forward" if permitted else "DENY — do not call the model", 28, GREEN if permitted else RED)
        label(d, (1240, 281), "INFERENCE REQUESTS", 23, MUTED, bold=True)
        label(d, (1235, 343), f"{used}", 132, GREEN if permitted else RED, bold=True)
        label(d, (1455, 419), "/ 50", 59, MUTED)
        box(d, (1240, 540, 1810, 566), "#26314b", "#26314b", 12)
        box(d, (1240, 540, 1240 + round(570 * used / 50), 566), GREEN if permitted else RED, GREEN if permitted else RED, 12)
        label(d, (1240, 625), f"{used} < 50  =  {'TRUE' if permitted else 'FALSE'}", 32, GREEN if permitted else RED, mono=True)
        paragraph(d, (1240, 719), "Usage is trusted server data. Reserve atomically before forwarding.", 28, 590)

    # Burned-in captions remain readable in any player; SRT is also included.
    box(d, (64, 928, 1856, 1023), "#070b13", "#070b13", 10)
    lines = wrap(d, subtitle, 27, 1720)
    for n, line in enumerate(lines[:2]):
        width = d.textlength(line, font=font(27))
        label(d, ((W - width) / 2, 940 + n * 36), line, 27)
    elapsed = scene["start"] + local
    d.rectangle((64, 1044, 1856, 1049), fill=LINE)
    d.rectangle((64, 1044, 64 + 1792 * elapsed / total, 1049), fill=GREEN)
    return im


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--preview-only", action="store_true")
    args = parser.parse_args()
    OUT.mkdir(exist_ok=True)
    data = json.loads((OUT / "capture.json").read_text())
    timeline = synthesize(SCENES)
    total = timeline[-1]["start"] + timeline[-1]["duration"]
    subtitles = [chunk for scene in timeline for chunk in subtitle_chunks(scene)]
    (OUT / "walkthrough.srt").write_text("\n\n".join(
        f"{i + 1}\n{timecode(start, True)} --> {timecode(end, True)}\n{text}"
        for i, (start, end, text) in enumerate(subtitles)) + "\n")
    (OUT / "chapters.json").write_text(json.dumps(timeline, indent=2) + "\n")
    (OUT / "transcript.md").write_text("# Policy walkthrough\n\n" + "\n\n".join(
        f"## {int(s['start']) // 60:02}:{int(s['start']) % 60:02} — {s['title']}\n\n{s['speech']}"
        for s in timeline) + "\n")
    previews = OUT / "previews"
    previews.mkdir(exist_ok=True)
    preview_images = []
    for i, scene in enumerate(timeline):
        im = render_scene(scene, scene["duration"] * .74, data, i, total, scene["speech"][:145])
        im.save(previews / f"{i + 1:02}-{scene['key']}.png")
        preview_images.append(im.resize((384, 216)))
    sheet = Image.new("RGB", (1920, 216 * math.ceil(len(preview_images) / 5)), BG)
    for i, image in enumerate(preview_images):
        sheet.paste(image, ((i % 5) * 384, (i // 5) * 216))
    sheet.save(OUT / "contact-sheet.jpg", quality=90)
    render_scene(timeline[0], 2, data, 0, total,
                 "Write policies. Sign in. Commit. Approve. Meter inference.").save(OUT / "poster.jpg", quality=94)
    if args.preview_only:
        print(f"Previews ready: {total:.1f} seconds planned")
        return
    output = OUT / "walkthrough.mp4"
    log = OUT / "ffmpeg.log"
    command = [args.ffmpeg, "-y", "-f", "rawvideo", "-vcodec", "rawvideo", "-pix_fmt", "rgb24",
               "-s", f"{W}x{H}", "-r", str(FPS), "-i", "pipe:0", "-i", str(OUT / "narration.wav"),
               "-i", str(OUT / "walkthrough.srt"), "-map", "0:v", "-map", "1:a", "-map", "2:s",
               "-c:v", "libx264", "-preset", "veryfast", "-threads", "4", "-crf", "21", "-pix_fmt", "yuv420p",
               "-c:a", "aac", "-b:a", "128k", "-c:s", "mov_text", "-metadata:s:s:0", "language=eng",
               "-movflags", "+faststart", "-t", str(total), str(output)]
    with log.open("wb") as stderr:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=stderr)
        subtitle_index = 0
        for index, scene in enumerate(timeline):
            print(f"Rendering {index + 1}/{len(timeline)}: {scene['title']}", flush=True)
            frames = round(scene["duration"] * FPS)
            for frame in range(frames):
                local = frame / FPS
                timestamp = scene["start"] + local
                while subtitle_index < len(subtitles) - 1 and subtitles[subtitle_index][1] < timestamp:
                    subtitle_index += 1
                start, end, subtitle = subtitles[subtitle_index]
                if not start <= timestamp <= end:
                    subtitle = ""
                image = render_scene(scene, local, data, index, total, subtitle)
                process.stdin.write(image.tobytes())
        process.stdin.close()
        if process.wait() != 0:
            raise RuntimeError(f"ffmpeg failed; see {log}")
    chapters = "\n".join(
        f'<button onclick="document.querySelector(\'video\').currentTime={scene["start"]:.2f}; document.querySelector(\'video\').play()">'
        f'{int(scene["start"]) // 60:02}:{int(scene["start"]) % 60:02} {scene["title"]}</button>'
        for scene in timeline)
    (OUT / "watch.html").write_text('''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Slack policy walkthrough · EYG</title>
<style>body{background:#0b1020;color:#edf4ff;font:18px system-ui;margin:40px auto;padding:0 24px;max-width:1200px}
h1{color:#60e3b0}video{width:100%;border-radius:16px;background:#121c30}p{color:#a1b2ce}
nav{display:grid;grid-template-columns:repeat(auto-fit,minmax(310px,1fr));gap:8px;margin-top:24px}
button{background:#121c30;border:1px solid #29384f;color:#edf4ff;padding:14px;text-align:left;border-radius:8px;cursor:pointer}
a{color:#8db9ff}</style><h1>From channel membership to enforced decisions</h1>
<p>Gleam + EYG · Real local commits and evaluator results · Illustrated UI with mocked providers</p>
<video controls preload="metadata" poster="poster.jpg" src="walkthrough.mp4"></video>
<p><a href="walkthrough.mp4" download>Download MP4</a> · <a href="walkthrough.srt">Captions</a> ·
<a href="transcript.md">Transcript</a> · <a href="proofs.json">Captured proof trees</a></p><nav>''' + chapters + "</nav></html>")
    print(f"Created {output} ({total:.1f} seconds, {output.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
