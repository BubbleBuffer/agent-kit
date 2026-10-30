#!/usr/bin/env python3
"""Convert docs/ into GitHub wiki pages (Python standard library only).

    python scripts/build_wiki.py OUT_DIR [--repo-root DIR]

Writes flat pages into OUT_DIR: docs/README.md becomes Home.md, other pages get
unique names (components/composer/ApprovalBar.md -> Composer-ApprovalBar.md),
relative .md links point at the wiki pages, relative images and other repo files
point at GitHub, and _Sidebar.md is built from the index. Exits non-zero if a
link or image does not resolve.
"""
import argparse
import os
import posixpath
import re
import sys

REPO = "BubbleBuffer/agent-kit"
RAW = f"https://raw.githubusercontent.com/{REPO}/main/"
BLOB = f"https://github.com/{REPO}/blob/main/"
TREE = f"https://github.com/{REPO}/tree/main/"

LINK = re.compile(r"(!?\[[^\]]*\]\()([^)\s]+)(\s+\"[^\"]*\")?(\))")
ATTR = re.compile(r'\b(src|srcset|href)="([^"]+)"')
CODE = re.compile(r"(`+)(?:(?!\1).)+?\1")


def page_name(rel):
    """Wiki page name for a path under docs/, without extension."""
    if rel == "README.md":
        return "Home"
    parts = rel[:-3].split("/")
    if parts[0] == "components":
        parts = parts[1:]
    parts[0] = parts[0][:1].upper() + parts[0][1:]
    return "-".join(parts)


def collect(docs):
    pages = {}
    for root, _, files in os.walk(docs):
        for f in sorted(files):
            if f.endswith(".md"):
                rel = os.path.relpath(os.path.join(root, f), docs).replace(os.sep, "/")
                pages[rel] = page_name(rel)
    names = {}
    for rel, name in pages.items():
        if name in names:
            sys.exit(f"wiki name clash: {rel} and {names[name]} -> {name}")
        names[name] = rel
    return pages


class Ctx:
    def __init__(self, docs, root, pages):
        self.docs, self.root, self.pages, self.errors = docs, root, pages, []

    def target(self, rel_page, url, image):
        """Return the rewritten URL, or the original for external/anchor links."""
        if re.match(r"[a-z][a-z0-9+.-]*:", url, re.I) or url.startswith(("#", "/")):
            return url
        path, _, frag = url.partition("#")
        full = posixpath.normpath(posixpath.join(posixpath.dirname("docs/" + rel_page), path))
        if full.startswith("../") or not os.path.exists(os.path.join(self.root, full)):
            self.errors.append(f"{rel_page}: {url} does not exist")
            return url
        if full.startswith("docs/") and full.endswith(".md") and not image:
            name = self.pages.get(full[5:])
            if name is None:
                self.errors.append(f"{rel_page}: {url} is not a generated page")
                return url
            return name + ("#" + frag if frag else "")
        if image or full.endswith((".png", ".svg", ".jpg", ".gif")):
            return RAW + full
        base = TREE if os.path.isdir(os.path.join(self.root, full)) else BLOB
        return base + full + ("#" + frag if frag else "")

    def convert(self, rel_page, text):
        out, fenced = [], False
        for line in text.split("\n"):
            if re.match(r"\s*(```|~~~)", line):
                fenced = not fenced
                out.append(line)
                continue
            if fenced:
                out.append(line)
                continue
            # Rewrite only outside inline code spans.
            pieces, last = [], 0
            for m in CODE.finditer(line):
                pieces.append((line[last:m.start()], True))
                pieces.append((m.group(0), False))
                last = m.end()
            pieces.append((line[last:], True))
            res = []
            for seg, live in pieces:
                if live:
                    seg = LINK.sub(
                        lambda m: m.group(1)
                        + self.target(rel_page, m.group(2), m.group(1).startswith("!"))
                        + (m.group(3) or "") + m.group(4), seg)
                    seg = ATTR.sub(
                        lambda m: f'{m.group(1)}="'
                        + self.target(rel_page, m.group(2), m.group(1) != "href") + '"', seg)
                res.append(seg)
            out.append("".join(res))
        return "\n".join(out)


def sidebar(docs, pages):
    lines = ["**[Home](Home)**", ""]
    heading = None
    for raw in open(os.path.join(docs, "README.md"), encoding="utf-8").read().splitlines():
        h = re.match(r"(#{2,3}) (.+)", raw)
        if h:
            heading = h.group(2)
            if h.group(1) == "###":
                lines += ["", f"**{heading}**", ""]
            elif heading == "Component sheets":
                lines += ["", "**Component sheets**"]
            continue
        m = re.match(r"- \[([^\]]+)\]\(([^)#]+\.md)\)", raw)
        if m and m.group(2) in pages:
            if heading is None and not any(l.startswith("**Guides") for l in lines):
                lines += ["**Guides**", ""]
            lines.append(f"- [{m.group(1)}]({pages[m.group(2)]})")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--repo-root", default=os.path.join(os.path.dirname(__file__), ".."))
    a = ap.parse_args()
    root = os.path.abspath(a.repo_root)
    docs = os.path.join(root, "docs")
    pages = collect(docs)
    ctx = Ctx(docs, root, pages)
    os.makedirs(a.out, exist_ok=True)
    for rel, name in pages.items():
        text = open(os.path.join(docs, rel), encoding="utf-8").read().replace("\r\n", "\n")
        body = ctx.convert(rel, text).rstrip("\n")
        footer = (f"---\n\nGenerated from [`docs/{rel}`]({BLOB}docs/{rel}). "
                  "Edit the file there; changes made on the wiki are overwritten.\n")
        with open(os.path.join(a.out, name + ".md"), "w", encoding="utf-8", newline="\n") as f:
            f.write(body + "\n\n" + footer)
    with open(os.path.join(a.out, "_Sidebar.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(sidebar(docs, pages))
    if ctx.errors:
        print("\n".join(ctx.errors), file=sys.stderr)
        sys.exit(1)
    print(f"{len(pages)} pages written to {a.out}")


if __name__ == "__main__":
    main()
