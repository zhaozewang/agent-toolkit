"""Build an offline presentation from a local deck."""

import argparse
import ctypes
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
from deck import SOURCE, extract_videos, json_script, read_deck


def write_web(audience, notes, output):
    speaker = (SOURCE / "speaker.html").read_text(encoding="utf-8")
    controls = (SOURCE / "browser.js").read_text(encoding="utf-8")
    document = (
        f'{audience}{speaker}<script type="application/json" id="speaker-notes">'
        f'{json_script(notes)}</script><script>{controls}</script></body></html>'
    )
    with tempfile.TemporaryDirectory(dir=output.parent) as staging:
        page = Path(staging) / output.name
        page.write_text(document, encoding="utf-8")
        page.replace(output)


def publish_bundle(bundle, destination):
    if not destination.exists():
        bundle.rename(destination)
        return
    metadata = destination / "Contents" / "Info.plist"
    if not metadata.is_file() or not plistlib.loads(metadata.read_bytes()).get(
        "CFBundleIdentifier", ""
    ).startswith("local.presentstage."):
        raise ValueError(f"An unrelated app already exists at {destination}.")
    # Swap the two directories atomically. The old app is now in staging.
    rename_swap = 2
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.renamex_np(bytes(bundle), bytes(destination), rename_swap) != 0:
        raise OSError(os.strerror(ctypes.get_errno()))


def build_app(deck, audience, notes, destination):
    # Build and sign a complete bundle before publishing it.
    with tempfile.TemporaryDirectory(dir=destination.parent) as staging:
        bundle = Path(staging) / destination.name
        contents = bundle / "Contents"
        resources = contents / "Resources"
        resources.mkdir(parents=True)
        slides = extract_videos(audience, resources) + "</body></html>"
        (resources / "Slides.html").write_text(slides, encoding="utf-8")
        (resources / "Transcript.json").write_text(json.dumps(notes, ensure_ascii=False), encoding="utf-8")
        executable = contents / "MacOS" / "Presenter"
        executable.parent.mkdir()
        identity = hashlib.sha256(os.fsencode(deck.resolve())).hexdigest()[:20]
        info = dict(
            CFBundleName=destination.stem,
            CFBundleExecutable=executable.name,
            CFBundleIdentifier=f"local.presentstage.deck-{identity}",
            CFBundlePackageType="APPL",
            CFBundleShortVersionString="1.0",
            CFBundleVersion="1",
            NSHighResolutionCapable=True,
            LSMinimumSystemVersion="13.0",
        )
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        subprocess.run(["swiftc", "-O", SOURCE / "Presenter.swift", "-o", executable], check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", bundle], check=True)
        publish_bundle(bundle, destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("deck", type=Path, help="JSON deck or legacy offline presenter HTML")
    parser.add_argument("-o", "--output", type=Path, help="output .html or .app (default: .app beside the deck)")
    args = parser.parse_args()
    output = args.output or args.deck.with_suffix(".app")
    if output.resolve() == args.deck.resolve():
        parser.error("Choose an output path different from the source deck.")
    if output.suffix.lower() not in {".app", ".html"}:
        parser.error("Output must end in .app or .html.")
    try:
        audience, notes = read_deck(args.deck)
        if output.suffix.lower() == ".html":
            write_web(audience, notes, output)
        else:
            build_app(args.deck, audience, notes, output)
    except (ValueError, OSError, plistlib.InvalidFileException, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{parser.prog}: {error}\n")
    print(output)


if __name__ == "__main__":
    main()
