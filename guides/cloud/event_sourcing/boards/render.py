"""Render an event storming board.json to HTML.

python3 -I render.py board.json board.html
Stickies: {id, kind, text, author, context, order, for, status}
kinds: event command actor aggregate policy read_model external hotspot
"""
import html
import json
import sys

COLORS = {
    "event": ("#ff9f43", "#2b1a05"),
    "command": ("#5aa9ff", "#04162b"),
    "actor": ("#fff176", "#2b2805"),
    "aggregate": ("#ffd54f", "#2b2005"),
    "policy": ("#c39bff", "#1d0b33"),
    "read_model": ("#7ee081", "#06260a"),
    "external": ("#ff8ac4", "#33061c"),
    "hotspot": ("#ff5c5c", "#fff"),
}
LABEL = {
    "event": "Domain event", "command": "Command", "actor": "Actor", "aggregate": "Aggregate",
    "policy": "Policy", "read_model": "Read model", "external": "External system", "hotspot": "Hot spot",
}
AUTHORS = {
    "avery": ("Avery", "Auditor", "#ffb86b"),
    "rui": ("Rui", "Runtime", "#8be9fd"),
    "sam": ("Sam", "Security", "#ff79c6"),
    "priya": ("Priya", "Product", "#50fa7b"),
    "dana": ("Dana", "Data", "#bd93f9"),
    "facilitator": ("Fac", "Facilitator", "#f1fa8c"),
}

def esc(s):
    return html.escape(str(s))

def sticky(s, small=False):
    bg, fg = COLORS.get(s["kind"], ("#ddd", "#000"))
    who = AUTHORS.get(s.get("author", ""), (s.get("author", "?"), "", "#999"))
    cls = "sticky small" if small else "sticky"
    if s.get("status") == "resolved":
        cls += " resolved"
    if s.get("status") == "disputed":
        cls += " disputed"
    badge = f'<span class="who" style="background:{who[2]}">{esc(who[0][0])}</span>' if s.get("author") else ""
    return f'<div class="{cls}" style="background:{bg};color:{fg}">{badge}<span class="kind">{esc(LABEL.get(s["kind"], s["kind"]))}</span>{esc(s["text"])}</div>'

def render(board):
    stickies = board["stickies"]
    by_for = {}
    for s in stickies:
        if s.get("for"):
            by_for.setdefault(s["for"], []).append(s)
    contexts = board.get("contexts", [])
    out = []
    out.append("""<!doctype html><meta charset=utf-8><title>Event storming board</title><style>
    body{margin:0;background:#1b1d23;color:#e6e6e6;font:13px/1.3 -apple-system,Segoe UI,sans-serif}
    header{padding:18px 24px;border-bottom:1px solid #333;display:flex;gap:28px;align-items:flex-end;flex-wrap:wrap}
    h1{margin:0;font-size:24px} .stage{color:#f1fa8c;font-size:16px;font-weight:600} .sub{color:#aaa;max-width:900px}
    .legend{display:flex;gap:6px;flex-wrap:wrap;padding:10px 24px} .legend .sticky{width:auto;min-height:0;padding:4px 8px}
    .people{display:flex;gap:10px;padding:0 24px 10px;color:#ccc} .people span{display:inline-flex;gap:6px;align-items:center}
    .dot{width:14px;height:14px;border-radius:50%;display:inline-block}
    .wall{display:flex;flex-wrap:wrap;gap:10px;padding:16px 24px}
    .sticky{position:relative;width:150px;min-height:70px;padding:16px 8px 8px;border-radius:3px;box-shadow:2px 3px 0 rgba(0,0,0,.35);font-weight:600;word-break:break-word}
    .sticky.small{width:136px;min-height:44px;font-size:12px}
    .sticky .kind{position:absolute;top:2px;left:6px;font-size:9px;font-weight:500;opacity:.7;text-transform:uppercase;letter-spacing:.04em}
    .sticky .who{position:absolute;top:-6px;right:-6px;width:18px;height:18px;border-radius:50%;color:#111;font-size:11px;display:flex;align-items:center;justify-content:center;font-weight:700}
    .sticky.resolved{opacity:.45;text-decoration:line-through}
    .sticky.disputed{outline:3px dashed #ff5c5c}
    .lane{border-top:1px solid #333;padding:10px 24px 16px}
    .lane h2{margin:0 0 4px;font-size:16px;color:#f1fa8c} .lane .purpose{color:#999;margin-bottom:8px;max-width:1100px}
    .flow{display:flex;gap:12px;align-items:flex-start;overflow:visible;flex-wrap:wrap}
    .col{display:flex;flex-direction:column;gap:6px;align-items:center;padding:6px;border-radius:6px;background:rgba(255,255,255,.03)}
    .anchors{display:flex;flex-direction:column;gap:6px;padding:6px;border-right:2px dashed #444;margin-right:4px}
    .band{display:flex;gap:10px;flex-wrap:wrap;padding:10px 24px;border-top:1px solid #333}
    .band h3{width:100%;margin:0;font-size:14px;color:#ff8ac4}
    .discussion{padding:12px 24px 30px;border-top:1px solid #333;columns:2;column-gap:40px;color:#ccc}
    .discussion p{margin:0 0 8px;break-inside:avoid} .discussion b{color:#fff}
    </style>""")
    out.append(f'<header><div><h1>{esc(board.get("title", "Event storming"))}</h1><div class="stage">{esc(board.get("stage", ""))}</div></div><div class="sub">{esc(board.get("subtitle", ""))}</div></header>')
    out.append('<div class="legend">' + "".join(sticky({"kind": k, "text": ""}) .replace('<span class="kind">', '<span class="kind" style="position:static">') for k in COLORS) + "</div>")
    counts = {}
    for s in stickies:
        counts[s["kind"]] = counts.get(s["kind"], 0) + 1
    people = "".join(f'<span><i class="dot" style="background:{c}"></i>{esc(n)} · {esc(r)}</span>' for k, (n, r, c) in AUTHORS.items() if k != "facilitator")
    summary = " · ".join(f"{v} {LABEL.get(k, k).lower()}s" for k, v in sorted(counts.items()))
    out.append(f'<div class="people">{people}<span style="margin-left:auto;color:#888">{esc(summary)}</span></div>')
    if not contexts:
        out.append('<div class="wall">' + "".join(sticky(s) for s in stickies if s["kind"] in ("event", "hotspot")) + "</div>")
    else:
        externals = [s for s in stickies if s["kind"] == "external" and not s.get("for")]
        if externals:
            out.append('<div class="band"><h3>External systems</h3>' + "".join(sticky(s, True) for s in externals) + "</div>")
        for c in contexts:
            events = sorted([s for s in stickies if s["kind"] == "event" and s.get("context") == c["id"]], key=lambda s: s.get("order", 999))
            anchors = [s for s in stickies if s.get("context") == c["id"] and s["kind"] in ("aggregate", "read_model", "policy", "hotspot", "actor", "command") and not s.get("for")]
            out.append(f'<section class="lane"><h2>{esc(c["name"])}</h2><div class="purpose">{esc(c.get("purpose", ""))}</div><div class="flow">')
            if anchors:
                order = {"aggregate": 0, "actor": 1, "command": 2, "policy": 3, "read_model": 4, "hotspot": 5}
                out.append('<div class="anchors">' + "".join(sticky(s, True) for s in sorted(anchors, key=lambda s: order.get(s["kind"], 9))) + "</div>")
            for e in events:
                linked = by_for.get(e["id"], [])
                above = [s for s in linked if s["kind"] in ("actor", "command", "aggregate", "external")]
                below = [s for s in linked if s["kind"] in ("policy", "read_model", "hotspot")]
                order = {"actor": 0, "command": 1, "aggregate": 2, "external": 3, "policy": 0, "read_model": 1, "hotspot": 2}
                above.sort(key=lambda s: order[s["kind"]])
                below.sort(key=lambda s: order[s["kind"]])
                out.append('<div class="col">' + "".join(sticky(s, True) for s in above) + sticky(e) + "".join(sticky(s, True) for s in below) + "</div>")
            out.append("</div></section>")
        loose = [s for s in stickies if s["kind"] == "hotspot" and not s.get("context") and not s.get("for")]
        if loose:
            out.append('<div class="band"><h3>Hot spots across contexts</h3>' + "".join(sticky(s) for s in loose) + "</div>")
    if board.get("discussion"):
        out.append('<div class="discussion">' + "".join(f"<p><b>{esc(AUTHORS.get(d['author'], (d['author'],))[0])}:</b> {esc(d['text'])}</p>" for d in board["discussion"]) + "</div>")
    return "\n".join(out)

if __name__ == "__main__":
    board = json.load(open(sys.argv[1]))
    open(sys.argv[2], "w").write(render(board))
