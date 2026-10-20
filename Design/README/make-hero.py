"""Writes the README's animated hero banner, light and dark.

Run: python3 Design/README/make-hero.py
GitHub shows SVGs as images, so the animation is pure CSS inside the SVG: no
scripts, no web fonts. Each word appears light (still being heard), turns dark
(committed), then the translation fades in, as in the app. Every element has its
own keyframes on one shared 14-second loop, so the whole scene restarts cleanly.
"""
from pathlib import Path
from xml.sax.saxutils import escape

LOOP = 14.0  # seconds
WIDTH, HEIGHT = 880, 440

LINES = [
    ("0:12", "Today we'll look at how neurons pass signals.", "今天我们来看看神经元是如何传递信号的。"),
    ("0:19", "When a neuron fires, an action potential travels down the axon.", "神经元放电时，动作电位会沿着轴突传导。"),
    ("0:27", "At the synapse, chemicals carry the message to the next cell.", "在突触处，化学物质把信息传给下一个细胞。"),
]
QUESTION = ("Q&A · 0:31", "Why does myelin make signals travel faster?", "老师提问：为什么髓鞘能让信号传得更快？")

THEMES = {
    "light": dict(
        page_top="#F4F7FB", page_bottom="#E6EEF7", window="#FFFFFF", bar="#F6F8FB", border="#D5DCE6",
        ink="#111418", draft="#A3ABB6", translation="#004A77", stamp="#8A929D", title="#5B6470",
        pill="#C2E8FF", pill_ink="#17587E", card="#F2F7FC", card_border="#C9DCEE", accent="#004A77", leaf="#20B68A",
    ),
    "dark": dict(
        page_top="#12161B", page_bottom="#0B0E12", window="#181C21", bar="#1F242B", border="#2A3038",
        ink="#E6E8EB", draft="#5D6670", translation="#7CC4F2", stamp="#737C87", title="#A4ACB6",
        pill="#1D3A50", pill_ink="#CDEBFF", card="#1A2530", card_border="#2B4256", accent="#7CC4F2", leaf="#34C99B",
    ),
}


def pct(seconds: float) -> str:
    return f"{min(max(seconds / LOOP * 100, 0), 100):.2f}%"


def keyframes(name: str, steps: list[tuple[float, str]]) -> str:
    body = " ".join(f"{pct(t)} {{ {style} }}" for t, style in steps)
    return f"@keyframes {name} {{ {body} }}"


def build(theme: dict) -> str:
    css: list[str] = []
    parts: list[str] = []
    fade_out = 12.8  # everything leaves together before the loop restarts

    # Window title and live recording pill.
    parts.append(f'<text x="164" y="88" class="title">Biology 101 · Neurons</text>')
    parts.append(
        f'<rect x="676" y="70" width="128" height="28" rx="14" fill="{theme["pill"]}"/>'
        f'<circle cx="694" cy="84" r="5" fill="#E5484D"><animate attributeName="opacity" values="1;0.35;1" dur="1.4s" repeatCount="indefinite"/></circle>'
    )
    for index in range(9):
        x = 708 + index * 5
        delay = (index * 0.13) % 0.9
        css.append(f".w{index} {{ transform-origin: {x + 1}px 84px; animation: bar 1.1s ease-in-out {delay:.2f}s infinite; }}")
        parts.append(f'<rect class="w{index}" x="{x}" y="78" width="2.4" height="12" rx="1.2" fill="{theme["pill_ink"]}"/>')
    parts.append(f'<text x="762" y="89" class="clock">12:04</text>')

    # Transcript lines: words type in, settle, then the translation appears.
    start = 0.6
    y = 140
    for line_index, (stamp, source, translation) in enumerate(LINES):
        words = source.split(" ")
        parts.append(f'<text x="128" y="{y}" class="stamp s{line_index}">{stamp}</text>')
        css.append(f".s{line_index} {{ animation: s{line_index} {LOOP}s linear infinite; }}")
        css.append(keyframes(f"s{line_index}", [(0, "opacity: 0"), (start, "opacity: 0"), (start + 0.3, "opacity: 1"), (fade_out, "opacity: 1"), (fade_out + 0.6, "opacity: 0"), (LOOP, "opacity: 0")]))
        spans = []
        for word_index, word in enumerate(words):
            name = f"l{line_index}w{word_index}"
            appear = start + 0.3 + word_index * 0.19
            commit = appear + 0.75
            css.append(f".{name} {{ animation: {name} {LOOP}s linear infinite; }}")
            css.append(keyframes(name, [
                (0, f"opacity: 0; fill: {theme['draft']}"),
                (appear, f"opacity: 0; fill: {theme['draft']}"),
                (appear + 0.12, f"opacity: 1; fill: {theme['draft']}"),
                (commit, f"opacity: 1; fill: {theme['draft']}"),
                (commit + 0.35, f"opacity: 1; fill: {theme['ink']}"),
                (fade_out, f"opacity: 1; fill: {theme['ink']}"),
                (fade_out + 0.6, f"opacity: 0; fill: {theme['ink']}"),
                (LOOP, f"opacity: 0; fill: {theme['ink']}"),
            ]))
            spans.append(f'<tspan class="{name}">{escape(word)}</tspan>')
        parts.append(f'<text x="186" y="{y}" class="source">{" ".join(spans)}</text>')
        shown = start + 0.3 + len(words) * 0.19 + 0.9
        css.append(f".t{line_index} {{ animation: t{line_index} {LOOP}s ease-out infinite; }}")
        css.append(keyframes(f"t{line_index}", [
            (0, "opacity: 0; transform: translateY(6px)"),
            (shown, "opacity: 0; transform: translateY(6px)"),
            (shown + 0.5, "opacity: 1; transform: translateY(0)"),
            (fade_out, "opacity: 1; transform: translateY(0)"),
            (fade_out + 0.6, "opacity: 0; transform: translateY(0)"),
            (LOOP, "opacity: 0; transform: translateY(0)"),
        ]))
        parts.append(f'<text x="186" y="{y + 28}" class="translation t{line_index}">{escape(translation)}</text>')
        start = shown + 0.5
        y += 76

    # The Q&A card that pops up once the teacher asks a question.
    card_at = start + 0.2
    css.append(f".qa {{ animation: qa {LOOP}s cubic-bezier(.2,.8,.2,1) infinite; }}")
    css.append(keyframes("qa", [
        (0, "opacity: 0; transform: translateY(14px)"),
        (card_at, "opacity: 0; transform: translateY(14px)"),
        (card_at + 0.6, "opacity: 1; transform: translateY(0)"),
        (fade_out, "opacity: 1; transform: translateY(0)"),
        (fade_out + 0.6, "opacity: 0; transform: translateY(0)"),
        (LOOP, "opacity: 0; transform: translateY(0)"),
    ]))
    label, question, translation = QUESTION
    parts.append(
        f'<g class="qa"><rect x="448" y="336" width="356" height="78" rx="14" fill="{theme["card"]}" stroke="{theme["card_border"]}"/>'
        f'<text x="468" y="360" class="qa-label">{escape(label)}</text>'
        f'<text x="468" y="382" class="qa-q">{escape(question)}</text>'
        f'<text x="468" y="402" class="qa-t">{escape(translation)}</text></g>'
    )

    font = "-apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', 'Noto Sans CJK SC', sans-serif"
    style = f"""
      text {{ font-family: {font}; }}
      .title {{ font-size: 15px; font-weight: 600; fill: {theme["title"]}; }}
      .clock {{ font-size: 13px; font-weight: 700; fill: {theme["pill_ink"]}; font-variant-numeric: tabular-nums; }}
      .stamp {{ font-size: 12px; font-weight: 600; fill: {theme["stamp"]}; }}
      .source {{ font-size: 18px; }}
      .translation {{ font-size: 16px; fill: {theme["translation"]}; }}
      .qa-label {{ font-size: 11.5px; font-weight: 700; fill: {theme["accent"]}; letter-spacing: .02em; }}
      .qa-q {{ font-size: 14px; font-weight: 600; fill: {theme["ink"]}; }}
      .qa-t {{ font-size: 13px; fill: {theme["translation"]}; }}
      @keyframes bar {{ 0%, 100% {{ transform: scaleY(.35); }} 50% {{ transform: scaleY(1); }} }}
      @media (prefers-reduced-motion: reduce) {{ * {{ animation: none !important; }} }}
      {chr(10).join(css)}
    """
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" role="img" aria-label="Nomi writes a lecture down as the teacher speaks, translates each passage, and answers the teacher's questions">
  <defs>
    <linearGradient id="page" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{theme["page_top"]}"/><stop offset="1" stop-color="{theme["page_bottom"]}"/></linearGradient>
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="0" dy="12" stdDeviation="16" flood-color="#0A1020" flood-opacity="0.16"/></filter>
    <style>{style}</style>
  </defs>
  <rect width="{WIDTH}" height="{HEIGHT}" rx="24" fill="url(#page)"/>
  <ellipse cx="96" cy="400" rx="150" ry="90" fill="{theme["leaf"]}" opacity="0.08"/>
  <ellipse cx="820" cy="40" rx="140" ry="80" fill="{theme["accent"]}" opacity="0.07"/>
  <g filter="url(#shadow)">
    <rect x="56" y="48" width="768" height="356" rx="18" fill="{theme["window"]}" stroke="{theme["border"]}"/>
  </g>
  <path d="M56 66 a18 18 0 0 1 18 -18 h732 a18 18 0 0 1 18 18 v54 h-768 z" fill="{theme["bar"]}"/>
  <line x1="56" y1="120" x2="824" y2="120" stroke="{theme["border"]}"/>
  <circle cx="84" cy="84" r="6" fill="#FF5F57"/><circle cx="104" cy="84" r="6" fill="#FEBC2E"/><circle cx="124" cy="84" r="6" fill="#28C840"/>
  {chr(10).join("  " + part for part in parts)}
</svg>
"""


here = Path(__file__).resolve().parent
for name, theme in THEMES.items():
    (here / f"hero-{name}.svg").write_text(build(theme), encoding="utf-8")
    print(f"wrote hero-{name}.svg")
