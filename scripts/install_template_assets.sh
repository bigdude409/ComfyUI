#!/usr/bin/env bash
#
# install_template_assets.sh — download the INPUT MEDIA used by built-in
# workflow templates (the images/audio/video that LoadImage/LoadAudio/etc.
# nodes reference) into ComfyUI/input/, so templates run out of the box.
#
# This does NOT download models (use download_models.sh for those) and does NOT
# touch template thumbnails/logos — those ship inside the installed
# comfyui-workflow-templates-media-* pip packages already.
#
# The file list comes from each template's io.inputs[].file in the installed
# index.json; files are fetched from the official template repo and existing
# files are skipped, so re-running is safe.
#
set -uo pipefail

COMFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$COMFY_DIR/.venv/bin/python"
INPUT_DIR="$COMFY_DIR/input"
BASE_URL="https://raw.githubusercontent.com/Comfy-Org/workflow_templates/main/input"

mkdir -p "$INPUT_DIR"

mapfile -t FILES < <("$PY" - <<'PYEOF'
import json, sys
from importlib import resources
try:
    idx = json.loads(
        (resources.files("comfyui_workflow_templates_media_other")
         / "templates" / "index.json").read_text()
    )
except Exception as e:
    print(f"ERROR: cannot read templates index.json: {e}", file=sys.stderr)
    raise SystemExit(1)

files = set()
for cat in idx:
    for t in cat.get("templates", []) or []:
        io = t.get("io") or {}
        for inp in (io.get("inputs") or []):
            f = inp.get("file")
            if f:
                files.add(f)
for f in sorted(files):
    print(f)
PYEOF
)

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "no input media referenced (is comfyui-workflow-templates installed?)" >&2
    exit 1
fi

echo ">> ${#FILES[@]} input media files referenced by templates -> $INPUT_DIR"
ok=0; skip=0; miss=0; missing=()
for f in "${FILES[@]}"; do
    dest="$INPUT_DIR/$f"
    if [ -f "$dest" ]; then
        skip=$((skip + 1)); continue
    fi
    mkdir -p "$(dirname "$dest")"
    if curl -fsSL --retry 2 "$BASE_URL/$f" -o "$dest"; then
        ok=$((ok + 1)); echo "  [get ] $f"
    else
        rm -f "$dest"; miss=$((miss + 1)); missing+=("$f")
    fi
done

echo ""
echo ">> downloaded $ok, skipped $skip (existing), unavailable $miss"
if [ "$miss" -gt 0 ]; then
    echo "   not found in the template repo (safe to ignore unless you need that template):"
    printf '   - %s\n' "${missing[@]}"
fi
