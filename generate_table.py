#!/usr/bin/env python3
"""Read memray profiles, compute copy counts, and update the README tables."""

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ARRAY_BYTES = 5_000 * 5_000 * 4  # 100 MB float32

# Flamegraphs are linked by absolute URL to the GitHub Pages copy, since
# github.com serves committed .html files as source rather than rendering them.
# Set FLAMEGRAPH_BASE=flamegraphs to generate relative links to the local files
# instead (useful for checking freshly generated, unpushed flamegraphs).
FLAMEGRAPH_BASE = (
    os.environ.get("FLAMEGRAPH_BASE")
    or "https://tomwhite.github.io/memray-array/flamegraphs"
).rstrip("/")

BEST = {
    ("write", "compressed"):   1,
    ("write", "uncompressed"): 0,
    ("read",  "compressed"):   1,
    ("read",  "uncompressed"): 0,
}

# Only the currently tracked targets appear in the auto-generated table.
# Older library versions (and S3) live in the static "Legacy results" table in
# the README, which this script does not touch. When a new library version is
# released, promote the outgoing row into the legacy table by hand and update
# these tables plus CURRENT_ZARR in the Makefile.
VERSION_DISPLAY = {
    "3.3.0":         ("v3 (3.3.0/0.16.5)", "3"),
    "zarrista-0.1.0": ("zarrista 0.1.0",    "3"),
}

STORE_LABEL = {
    ("local", "fsspec"):   "local",
    ("local", "obstore"):  "obstore",
    ("local", "icechunk"): "icechunk",
    ("local", "local"):    "local",
}

# zarrista-icechunk is read-only (see the Makefile), so it contributes a row to
# the reads table and none to writes — `generate_table` drops rows with no data.
# zarrista cannot write to icechunk: its session bridge reconstructs a separate
# Rust session, so writes never reach the repository.
READ_ONLY_COMBINATIONS = {
    ("write", "icechunk", "zarrista-0.1.0"),
}

ROW_ORDER = [
    ("local", "fsspec",   "3.3.0"),
    ("local", "obstore",  "3.3.0"),
    ("local", "icechunk", "3.3.0"),
    ("local", "local",    "zarrista-0.1.0"),
    ("local", "obstore",  "zarrista-0.1.0"),
    ("local", "icechunk", "zarrista-0.1.0"),
]


def get_peak_memory(profile: Path) -> int | None:
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir) / "stats.json"
        result = subprocess.run(
            [
                "uv", "run", "--python", "3.14", "--isolated", "--with", "memray",
                "python", "-m", "memray", "stats", "--json", "-o", str(tmp), str(profile),
            ],
            capture_output=True,
        )
        if result.returncode != 0:
            print(f"  {result.stderr.decode().strip()}", file=sys.stderr)
            return None
        return json.loads(tmp.read_text())["metadata"]["peak_memory"]


def copy_count(peak: int) -> int:
    return max(0, round((peak - ARRAY_BYTES) / ARRAY_BYTES))


def parse_profile(path: Path):
    """Return (op, fs, version, library, compression) or None."""
    m = re.fullmatch(
        r"(read|write)-(local|s3)-zarr-(\d+\.\d+\.\d+)-(fsspec|obstore|icechunk)"
        r"-(compressed|uncompressed)\.bin",
        path.name,
    )
    if m:
        return m.groups()
    m = re.fullmatch(
        r"(read|write)-(local|s3)-zarrista-(\d+\.\d+\.\d+)-(local|obstore|icechunk)"
        r"-(compressed|uncompressed)\.bin",
        path.name,
    )
    if m:
        op, fs, ver, store, compression = m.groups()
        return op, fs, f"zarrista-{ver}", store, compression
    return None


def make_cell(n: int, op: str, compression: str, fg: str) -> str:
    label = f"**{n}**" if n == BEST[(op, compression)] else str(n)
    return f"[{label}]({fg})"


def generate_table(op: str, results: dict) -> str:
    """Build a markdown table string for the given operation.

    results: {(fs, library, version, compression): (n_copies, flamegraph_path)}
    """
    lines = [
        "| Filesystem | Store   | Zarr library          | Zarr format | Uncompressed | Compressed |",
        "|------------|---------|----------------------|-------------|--------------|------------|",
    ]
    prev_fs = prev_store = None
    for fs, library, version in ROW_ORDER:
        unc = results.get((fs, library, version, "uncompressed"))
        com = results.get((fs, library, version, "compressed"))
        if unc is None and com is None:
            continue

        store = STORE_LABEL[(fs, library)]
        ver_label, fmt = VERSION_DISPLAY[version]

        present = [(c, x) for c, x in [("uncompressed", unc), ("compressed", com)] if x is not None]
        if all(x[0] == BEST[(op, c)] for c, x in present):
            ver_label = f"**{ver_label}**"

        fs_col    = fs.capitalize() if fs != prev_fs else ""
        store_col = store if (store != prev_store or fs != prev_fs) else ""

        unc_cell = make_cell(unc[0], op, "uncompressed", unc[1]) if unc else "-"
        com_cell = make_cell(com[0], op, "compressed",   com[1]) if com else "-"

        lines.append(f"| {fs_col:<10} | {store_col:<7} | {ver_label:<21} | {fmt:<11} | {unc_cell:<12} | {com_cell} |")
        prev_fs    = fs
        prev_store = store

    return "\n".join(lines) + "\n"


def has_data_rows(table: str) -> bool:
    return sum(1 for line in table.splitlines() if line.startswith("| ") and not line.startswith("| Filesystem") and not line.startswith("|---")) > 0


def update_readme(readme: Path, writes_table: str, reads_table: str) -> None:
    text = readme.read_text()
    for marker, table in [("writes", writes_table), ("reads", reads_table)]:
        if not has_data_rows(table):
            print(f"No data for {marker} table — skipping that section.", file=sys.stderr)
            continue
        pattern = (
            r"(<!-- begin-table:" + marker + r" -->)\n"
            r".*?"
            r"(<!-- end-table:" + marker + r" -->)"
        )
        # The blank lines around the table are required: kramdown (GitHub Pages)
        # swallows markdown that directly abuts an HTML comment block, so
        # without them the table renders as a paragraph on the Pages site.
        new_text, count = re.subn(
            pattern, rf"\1\n\n{table}\n\2", text, flags=re.DOTALL
        )
        if count == 0:
            print(f"WARNING: marker begin-table:{marker} not found in README", file=sys.stderr)
        text = new_text
    readme.write_text(text)


def main() -> None:
    profiles_dir = Path("profiles")
    writes: dict = {}
    reads:  dict = {}

    for profile in sorted(profiles_dir.glob("*.bin")):
        parsed = parse_profile(profile)
        if parsed is None:
            continue
        op, fs, version, library, compression = parsed
        if version not in VERSION_DISPLAY:
            continue
        if (op, library, version) in READ_ONLY_COMBINATIONS:
            # A stale profile from an experiment that could not work; ignoring it
            # here keeps a meaningless number out of the table.
            continue

        print(f"Processing {profile.name} ...", flush=True)
        peak = get_peak_memory(profile)
        if peak is None:
            print(f"  skipped (incompatible profile or error)", flush=True)
            continue

        n = copy_count(peak)
        fg = f"{FLAMEGRAPH_BASE}/{profile.name}.html"
        key = (fs, library, version, compression)
        (writes if op == "write" else reads)[key] = (n, fg)
        print(f"  {n} copies (peak {peak:,})", flush=True)

    writes_table = generate_table("write", writes)
    reads_table  = generate_table("read",  reads)

    update_readme(Path("README.md"), writes_table, reads_table)
    print("README.md updated.")


if __name__ == "__main__":
    main()
