#!/usr/bin/env python3
"""Write the Sparkle appcast for one architecture's release DMG.

Each architecture has its own feed (appcast-<arch>.xml) holding only the
latest release, since a release replaces the previous one as GitHub's
latest. The notes file lists one change per line; they become the Markdown
release notes Sparkle shows above the install button.
"""

import argparse
import html
from datetime import datetime, timezone
from pathlib import Path

MINIMUM_SYSTEM_VERSION = "14.0"


def notes_markdown(lines):
    # Sparkle renders Markdown natively; its WebKit view does not load in a
    # Catalyst process, where HTML notes would show as raw tags.
    if not lines:
        return "Bug fixes and improvements."
    return "## What's Changed\n\n" + "\n".join(f"- {line}" for line in lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--url", required=True, help="download URL of the DMG")
    parser.add_argument("--length", required=True, type=int, help="DMG size in bytes")
    parser.add_argument("--signature", required=True, help="base64 EdDSA signature of the DMG")
    parser.add_argument("--notes", required=True, type=Path, help="one change per line")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    lines = [line.strip() for line in args.notes.read_text().splitlines() if line.strip()]
    date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    version = html.escape(args.version)
    feed = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>FlowDown</title>
    <item>
      <title>{version}</title>
      <pubDate>{date}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MINIMUM_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[{notes_markdown(lines)}]]></description>
      <enclosure url="{html.escape(args.url)}" length="{args.length}" type="application/octet-stream" sparkle:edSignature="{html.escape(args.signature)}"/>
    </item>
  </channel>
</rss>
"""
    args.output.write_text(feed)


if __name__ == "__main__":
    main()
