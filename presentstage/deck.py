"""Read deck content and produce the audience markup and visible speaker notes."""

import base64
import hashlib
import json
import mimetypes
import re
from html import escape
from pathlib import Path

SOURCE = Path(__file__).resolve().parent


def json_script(value):
    # JSON is embedded in a script element. A literal </script> would close it.
    return json.dumps(value, ensure_ascii=False).replace("<", r"\u003c")


def media_element(path):
    mime, _ = mimetypes.guess_type(path.name)
    if not mime or not mime.startswith(("image/", "video/")):
        raise ValueError(f"Unsupported image or video format: {path.name}")
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    uri = f"data:{mime};base64,{encoded}"
    if mime.startswith("video/"):
        return f'<figure><video data-media="{uri}" muted playsinline loop></video></figure>'
    return f'<figure><img src="{uri}" alt=""></figure>'


def read_json(deck):
    data = json.loads(deck.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("slides"), list):
        raise ValueError("Expected a JSON object with a slides array.")
    title = data.get("title", deck.stem)
    if not isinstance(title, str):
        raise ValueError("Deck title must be a string.")
    slides = []
    notes = []
    for number, slide in enumerate(data["slides"], start=1):
        if not isinstance(slide, dict):
            raise ValueError(f"Slide {number} must be an object.")
        for field in ("title", "body", "notes", "time", "media"):
            if field in slide and not isinstance(slide[field], str):
                raise ValueError(f"Slide {number}: {field} must be a string.")
        if not isinstance(slide.get("hidden", False), bool):
            raise ValueError(f"Slide {number}: hidden must be true or false.")
        if slide.get("hidden"):
            continue
        heading = slide.get("title", "")
        image = media_element(deck.parent / slide["media"]) if slide.get("media") else ""
        parts = [f"<h1>{escape(heading)}</h1>" if heading else "", slide.get("body", ""), image]
        slides.append('<section class="slide">' + "".join(parts) + "</section>")
        notes.append(dict(title=heading, text=slide.get("notes", ""), time=slide.get("time", "")))
    css = (SOURCE / "slides.css").read_text(encoding="utf-8")
    audience = (
        '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        f'<title>{escape(title)}</title><style>{css}</style></head>'
        '<body><main class="view"><div class="stage">' + "".join(slides) + "</div></main>"
    )
    return audience, notes


def read_legacy_html(deck):
    html = deck.read_text(encoding="utf-8")
    audience, separator, controls = html.partition('<nav class="bar">')
    marker = re.search(r"\bconst\s+script\s*=\s*", controls)
    if not separator or not marker:
        raise ValueError("Expected an offline presenter HTML deck with a navigation bar and script notes.")
    entries, _ = json.JSONDecoder().raw_decode(controls[marker.end():])
    revisions_marker = re.search(r"\bconst\s+importedNotes\s*=\s*", controls)
    revisions = {}
    if revisions_marker:
        revisions, _ = json.JSONDecoder().raw_decode(controls[revisions_marker.end():])
        if not isinstance(revisions, dict) or not all(isinstance(v, str) for v in revisions.values()):
            raise ValueError("Imported speaker notes must map slide titles to text.")
    sections = re.findall(r'<section class="slide(?: [^"]*)?"[^>]*>', audience)
    if not isinstance(entries, list) or len(sections) != len(entries):
        raise ValueError("Each slide, including hidden slides, needs one notes entry.")
    notes = []
    for section, entry in zip(sections, entries):
        if not isinstance(entry, list) or len(entry) != 3 or not all(isinstance(v, str) for v in entry):
            raise ValueError("Each notes entry must contain three strings: time, title and notes.")
        time, title, text = entry
        if not re.search(r"\shidden(?:[\s=>])", section):
            notes.append(dict(time=time, title=title, text=revisions.get(title, text)))
    audience = audience.replace("</style>", ".view{inset:0}body{background:white}</style>", 1)
    return audience, notes


def read_deck(deck):
    if deck.suffix.lower() == ".json":
        audience, notes = read_json(deck)
    elif deck.suffix.lower() == ".html":
        audience, notes = read_legacy_html(deck)
    else:
        raise ValueError("Input must be a JSON deck or an offline presenter HTML deck.")
    if not notes:
        raise ValueError("The deck needs at least one visible slide.")
    player = (SOURCE / "audience.js").read_text(encoding="utf-8")
    return f"{audience}<script>{player}</script>", notes


def extract_videos(audience, resources):
    def save(match):
        mime, payload = match.groups()
        extension = mimetypes.guess_extension(mime)
        if not extension:
            return match[0]
        data = base64.b64decode(payload, validate=True)
        name = hashlib.sha256(data).hexdigest() + extension
        path = resources / "movies" / name
        path.parent.mkdir(exist_ok=True)
        if not path.exists():
            path.write_bytes(data)
        return f'data-media="movies/{name}"'

    return re.sub(r'data-media="data:(video/[\w.+-]+);base64,([^"]+)"', save, audience)
