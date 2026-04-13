#!/usr/bin/env python3
"""Upsert a release item into a Sparkle appcast.xml file.

Usage:
  appcast-upsert.py <appcast.xml> <meta.json> <release_notes_url> <asset_url>

Schema follows Sparkle's canonical enclosure-attribute form:
  https://sparkle-project.org/documentation/publishing/

- Bootstraps appcast.xml with the Sparkle namespace if the file is absent.
- Upserts by sparkle:version *attribute on <enclosure>*: if an item with that
  version exists it is replaced; otherwise the new item is inserted at the top.
- Does NOT embed release notes inline (no <description>): GitHub release notes
  are Markdown, Sparkle <description> expects HTML — drop both the CDATA
  escape edge cases and the markdown-conversion dependency by relying on
  sparkle:releaseNotesLink for native rendering.
- Fails fast if the XML shape is unexpected (no <rss>, no <channel>, etc.).
"""
import json
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

SP = "http://www.andymatuschak.org/xml-namespaces/sparkle"
NS = {"sparkle": SP}
ET.register_namespace("sparkle", SP)


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def bootstrap(path: Path):
    path.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        f'<rss version="2.0" xmlns:sparkle="{SP}">\n'
        "  <channel>\n"
        "    <title>Pace</title>\n"
        "    <link>https://maman.github.io/pace/appcast.xml</link>\n"
        "    <description>Pace release feed</description>\n"
        "    <language>en</language>\n"
        "  </channel>\n"
        "</rss>\n"
    )


def main():
    if len(sys.argv) != 5:
        die("usage: appcast-upsert.py <appcast.xml> <meta.json> <release_notes_url> <asset_url>")
    appcast_path = Path(sys.argv[1])
    meta_path = Path(sys.argv[2])
    release_notes_url = sys.argv[3]
    asset_url = sys.argv[4]

    meta = json.loads(meta_path.read_text())
    for k in ("shortVersionString", "version", "edSignature", "length",
              "pubDate", "minimumSystemVersion"):
        if k not in meta:
            die(f"meta.json missing key: {k}")

    if not appcast_path.exists():
        bootstrap(appcast_path)

    try:
        tree = ET.parse(appcast_path)
    except ET.ParseError as e:
        die(f"appcast.xml failed to parse: {e}")

    root = tree.getroot()
    if root.tag != "rss":
        die("root element is not <rss>")
    channel = root.find("channel")
    if channel is None:
        die("<channel> missing from appcast")

    sp_version_attr = f"{{{SP}}}version"

    # Upsert key: sparkle:version *attribute on <enclosure>* (canonical Sparkle form)
    removed = 0
    for item in list(channel.findall("item")):
        enc = item.find("enclosure")
        if enc is not None and enc.get(sp_version_attr) == meta["version"]:
            channel.remove(item)
            removed += 1

    # Build new item — version metadata on enclosure attributes.
    # No <description>; Sparkle fetches sparkle:releaseNotesLink and renders
    # the linked GitHub release page natively.
    def ns(t):
        return f"{{{SP}}}{t}"

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {meta['shortVersionString']}"
    ET.SubElement(item, "pubDate").text = meta["pubDate"]
    ET.SubElement(item, ns("minimumSystemVersion")).text = meta["minimumSystemVersion"]
    ET.SubElement(item, ns("releaseNotesLink")).text = release_notes_url
    ET.SubElement(item, "enclosure", {
        "url": asset_url,
        "length": str(meta["length"]),
        "type": "application/octet-stream",
        ns("version"): meta["version"],
        ns("shortVersionString"): meta["shortVersionString"],
        ns("edSignature"): meta["edSignature"],
    })

    # Insert as first <item> (after channel header elements)
    insert_idx = len(list(channel))
    for i, child in enumerate(list(channel)):
        if child.tag == "item":
            insert_idx = i
            break
    channel.insert(insert_idx, item)

    ET.indent(tree, space="  ")
    tree.write(appcast_path, xml_declaration=True, encoding="utf-8")

    print(f"upsert ok (replaced {removed} existing item(s) for version={meta['version']})")


if __name__ == "__main__":
    main()
