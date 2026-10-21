#!/usr/bin/env python3
"""Regenerate the AUTO-marked tables in README.md from fresh benchmark output and
append a record to results/history.json for per-version evolution tracking.

  scripts/update-readme.py \
      --readme README.md \
      --static results/results.md \
      --durations durations \
      --versions versions.json \
      --history results/history.json \
      --commit <sha>

Only the regions wrapped in <!-- AUTO:<id> start --> / <!-- AUTO:<id> end --> are
touched; the surrounding prose is left alone.
"""
import argparse
import glob
import json
import os
import re
from datetime import date

# tool key -> (display name, url) for the Versions table
TOOL_META = {
    "phpstan": ("PHPStan", "https://phpstan.org/"),
    "mago": ("Mago", "https://github.com/carthage-software/mago"),
    "ecs": ("ECS", "https://github.com/ecsphp/ecs"),
    "php-cs-fixer": ("PHP-CS-Fixer", "https://github.com/PHP-CS-Fixer/PHP-CS-Fixer"),
}

# static-table Tool label -> versions.json key, so the Version column reflects the
# pinned release rather than whatever the tool's --version banner happens to print
# first (ECS, for one, reports a bundled component version there).
TOOL_KEY = {
    "PHPStan": "phpstan",
    "Mago": "mago",
    "ECS": "ecs",
    "ECS --blink": "ecs",
    "PHP-CS-Fixer": "php-cs-fixer",
}


def replace_region(text, marker_id, body):
    """Swap the content between the AUTO:<marker_id> start/end comments for body."""
    pattern = re.compile(
        r"(<!-- AUTO:%s start[^>]*-->\n).*?(\n<!-- AUTO:%s end -->)" % (marker_id, marker_id),
        re.DOTALL,
    )
    if not pattern.search(text):
        raise SystemExit(f"marker AUTO:{marker_id} not found in README")
    return pattern.sub(lambda m: m.group(1) + body + m.group(2), text)


def parse_static(path):
    """Read the assembled static results table into a list of row dicts."""
    rows = []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != 6 or cells[0] == "Project" or set("".join(cells)) <= set("-: "):
            continue
        rows.append(dict(zip(["project", "files", "tool", "version", "cold", "hot"], cells)))
    return rows


def bold_fast(value):
    """Bold a timing under 2 seconds, per the README convention; blank stays blank."""
    if not value:
        return ""
    try:
        return f"**{value}**" if float(value) < 2 else value
    except ValueError:
        return value


def static_table(rows):
    out = [
        "| Project | Files | Tool | Version | Cold (s) | Hot (s) |",
        "|---------|------:|------|---------|---------:|--------:|",
    ]
    for r in rows:
        out.append(
            f"| {r['project']} | {r['files']} | {r['tool']} | {r['version']} "
            f"| {bold_fast(r['cold'])} | {bold_fast(r['hot'])} |"
        )
    return "\n".join(out)


def read_durations(durations_dir, prefix):
    """Read single-*.txt / multi-*.txt fragments into [(name, ms, mem_mb)] lists."""
    entries = []
    for path in sorted(glob.glob(os.path.join(durations_dir, f"{prefix}-*.txt"))):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if not line:
                continue
            name, ms, mem = line.split("|")
            entries.append((name, int(ms), int(mem)))
    return entries


def parser_table(entries):
    """Render a fastest-first fixed-width ranking (seconds, comma decimal, vs slowest)."""
    entries = sorted(entries, key=lambda e: e[1])
    slowest = max(e[1] for e in entries)
    cols = []
    for i, (name, ms, _mem) in enumerate(entries, 1):
        avg = f"{ms / 1000:.2f}".replace(".", ",") + " s"
        ratio = f"{slowest / ms:.1f}x"
        cols.append((str(i), name, avg, ratio))

    w_rank = max(len("Rank"), *(len(c[0]) for c in cols))
    w_name = max(len("Parser"), *(len(c[1]) for c in cols))
    w_avg = max(len("Avg (5 runs)"), *(len(c[2]) for c in cols))
    w_ratio = max(len("vs slowest"), *(len(c[3]) for c in cols))

    lines = ["```", f"{'Rank':>{w_rank}} | {'Parser':<{w_name}} | {'Avg (5 runs)':>{w_avg}} | {'vs slowest':>{w_ratio}}"]
    for rank, name, avg, ratio in cols:
        lines.append(f"{rank:>{w_rank}} | {name:<{w_name}} | {avg:>{w_avg}} | {ratio:>{w_ratio}}")
    lines.append("```")
    return "\n".join(lines)


def versions_table(versions):
    out = [
        "| Tool | Version | Released | Min PHP to run |",
        "|------|---------|----------|----------------|",
    ]
    for key, (name, url) in TOOL_META.items():
        v = versions[key]
        out.append(f"| [{name}]({url}) | {v['version']} | {v['released']} | {v['min_php']} |")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--readme", default="README.md")
    ap.add_argument("--static", default="results/results.md")
    ap.add_argument("--durations", default="durations")
    ap.add_argument("--versions", default="versions.json")
    ap.add_argument("--history", default="results/history.json")
    ap.add_argument("--commit", default="")
    args = ap.parse_args()

    versions = json.load(open(args.versions, encoding="utf-8"))
    static_rows = parse_static(args.static)
    # pin the Version column to the authoritative release from versions.json
    for r in static_rows:
        key = TOOL_KEY.get(r["tool"])
        if key in versions:
            r["version"] = versions[key]["version"]
    # the PHP 7.4 table is the Laravel 8.x project; everything else is the 8.4 table.
    php74 = [r for r in static_rows if re.match(r"Laravel 8\.", r["project"])]
    php84 = [r for r in static_rows if r not in php74]

    single = read_durations(args.durations, "single")
    multi = read_durations(args.durations, "multi")

    text = open(args.readme, encoding="utf-8").read()
    text = replace_region(text, "static-php84", static_table(php84))
    text = replace_region(text, "static-php74", static_table(php74))
    text = replace_region(text, "versions", versions_table(versions))
    text = replace_region(text, "parser-single", parser_table(single))
    text = replace_region(text, "parser-all", parser_table(multi))
    open(args.readme, "w", encoding="utf-8").write(text)

    record = {
        "date": date.today().isoformat(),
        "commit": args.commit,
        "versions": {k: versions[k]["version"] for k in versions},
        "static": static_rows,
        "parsers": {
            "single": [{"parser": n, "ms": ms, "mem_mb": mem} for n, ms, mem in single],
            "all": [{"parser": n, "ms": ms, "mem_mb": mem} for n, ms, mem in multi],
        },
    }
    history = []
    if os.path.exists(args.history):
        history = json.load(open(args.history, encoding="utf-8"))
    history.append(record)
    with open(args.history, "w", encoding="utf-8") as fh:
        json.dump(history, fh, indent=2)
        fh.write("\n")

    print(f"updated {args.readme} and appended 1 record to {args.history}")


if __name__ == "__main__":
    main()
