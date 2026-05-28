#!/usr/bin/env python3
"""Extract model download specs from the installed ComfyUI workflow templates.

For every built-in template we collect (directory, filename, url) tuples from two
sources inside the template's workflow JSON:

  1. ``node["properties"]["models"]`` entries -> {name, url, directory}
     (this is the structured, authoritative source used by most templates).

  2. Markdown links inside ``MarkdownNote`` nodes that point at a model file
     (.safetensors/.sft/.gguf/.pt/.pth/.ckpt/.bin). The target directory is
     inferred from the nearest preceding section header in the note text
     (e.g. ``**checkpoints**``, ``## loras``, ``**text_encoders**``). Several
     templates (notably LTX-2 / LTX-2.3) ship their local-download links only
     in a MarkdownNote, so this fills the gaps left by source 1.

Templates are read straight out of the installed
``comfyui_workflow_templates_media_*`` packages, so the output always matches
whatever template version is installed in this venv.

Usage:
    template_models.py --list                 # human-readable table
    template_models.py --json                  # full map as JSON
    template_models.py NAME [NAME ...]         # tab-separated specs for templates
    template_models.py --all                   # tab-separated specs for everything

Tab-separated output is ``directory<TAB>filename<TAB>url`` (one per line), which
is what download_models.sh consumes.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from importlib import resources

MEDIA_PACKAGES = (
    "comfyui_workflow_templates_media_api",
    "comfyui_workflow_templates_media_image",
    "comfyui_workflow_templates_media_other",
    "comfyui_workflow_templates_media_video",
)

MODEL_EXTS = (".safetensors", ".sft", ".gguf", ".pt", ".pth", ".ckpt", ".bin")

# Map a normalized markdown section header (lowercase, alphanumerics + single
# spaces) to the models/<dir> subfolder it names. Templates write these headers
# in prose form (e.g. "Diffusion Model", "Text Encoder", "LoRA"), so we match
# those as well as the literal folder names.
SECTION_MAP = {
    "diffusion model": "diffusion_models", "diffusion models": "diffusion_models",
    "diffusion_models": "diffusion_models", "unet": "diffusion_models",
    "text encoder": "text_encoders", "text encoders": "text_encoders",
    "text_encoders": "text_encoders",
    "lora": "loras", "loras": "loras",
    "vae": "vae",
    "checkpoint": "checkpoints", "checkpoints": "checkpoints",
    "checkpoint model": "checkpoints", "model": "checkpoints",
    "clip": "clip", "clip model": "clip",
    "clip vision": "clip_vision", "clip_vision": "clip_vision",
    "controlnet": "controlnet", "control net": "controlnet",
    "upscale model": "upscale_models", "upscale models": "upscale_models",
    "upscaler": "upscale_models", "upscale_models": "upscale_models",
    "latent upscale model": "latent_upscale_models",
    "latent upscale models": "latent_upscale_models",
    "latent upscale": "latent_upscale_models",
    "latent upscaler": "latent_upscale_models",
    "latent_upscale_models": "latent_upscale_models",
    "style model": "style_models", "style models": "style_models",
    "audio encoder": "audio_encoders", "audio encoders": "audio_encoders",
    "model patch": "model_patches", "model patches": "model_patches",
    "photomaker": "photomaker", "gligen": "gligen",
    "embedding": "embeddings", "embeddings": "embeddings",
    "textual inversion": "embeddings",
}

MD_LINK = re.compile(r"\[[^\]]*\]\((https?://[^)\s]+)\)")
_NORM = re.compile(r"[^a-z0-9 ]+")


def _iter_template_files():
    """Yield (template_name, parsed_json) for every workflow template JSON."""
    for pkg in MEDIA_PACKAGES:
        try:
            base = resources.files(pkg) / "templates"
        except ModuleNotFoundError:
            continue
        if not base.is_dir():
            continue
        for entry in base.iterdir():
            name = entry.name
            if not name.endswith(".json"):
                continue
            if name.startswith(("index", "fuse_options")) or name.endswith(".schema.json"):
                continue
            try:
                data = json.loads(entry.read_text())
            except Exception:
                continue
            yield name[:-5], data


def _clean_url(url: str) -> str:
    # HuggingFace /blob/ links render an HTML page; /resolve/ is the raw download.
    return url.strip().replace("/blob/", "/resolve/")


def _filename_from_url(url: str) -> str:
    base = url.split("?", 1)[0].rstrip("/")
    return os.path.basename(base)


def _section_for_line(line: str) -> str | None:
    """If a markdown line looks like a section header, return the dir it names.

    Only short header-ish lines (no links, no tree-drawing chars) are considered,
    so prose and the illustrative directory-tree block don't get misread.
    """
    raw = line.strip()
    if not raw or "](" in raw or "http" in raw:
        return None
    if any(c in raw for c in "├└│"):  # directory-tree art, not a header
        return None
    text = _NORM.sub(" ", raw.lower()).strip()
    text = re.sub(r"\s+", " ", text)
    if not text or len(text) > 30:
        return None
    return SECTION_MAP.get(text)


def _models_from_properties(node: dict, out: list):
    for m in (node.get("properties", {}).get("models") or []):
        if isinstance(m, dict) and m.get("url"):
            directory = m.get("directory") or "checkpoints"
            url = _clean_url(m["url"])
            fname = m.get("name") or _filename_from_url(url)
            out.append((directory, fname, url))


def _models_from_markdown(text: str, out: list):
    current = None
    for line in text.splitlines():
        sec = _section_for_line(line)
        if sec:
            current = sec
            continue
        for url in MD_LINK.findall(line):
            low = url.split("?", 1)[0].lower()
            if not low.endswith(MODEL_EXTS):
                continue
            out.append((current or "checkpoints", _filename_from_url(url), _clean_url(url)))


def build_map() -> dict:
    """Return {template_name: [(directory, filename, url), ...]} (deduped per template)."""
    result: dict[str, list] = {}
    for name, wf in _iter_template_files():
        if not isinstance(wf, dict):
            continue
        # Pass 1: structured properties.models (authoritative directories).
        prop_specs: list = []
        md_specs: list = []
        for node in wf.get("nodes", []):
            if not isinstance(node, dict):
                continue
            _models_from_properties(node, prop_specs)
            if node.get("type") == "MarkdownNote":
                wv = node.get("widgets_values")
                texts = wv if isinstance(wv, list) else [wv]
                for t in texts:
                    if isinstance(t, str):
                        _models_from_markdown(t, md_specs)
        # properties win; markdown only adds filenames not already covered.
        prop_files = {f for _, f, _ in prop_specs}
        seen = set()
        uniq = []
        for d, f, u in prop_specs + [m for m in md_specs if m[1] not in prop_files]:
            key = (d, f)
            if key in seen:
                continue
            seen.add(key)
            uniq.append((d, f, u))
        if uniq:
            result[name] = uniq
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("templates", nargs="*", help="template names to emit specs for")
    ap.add_argument("--all", action="store_true", help="emit specs for every template")
    ap.add_argument("--list", action="store_true", help="human-readable table")
    ap.add_argument("--json", action="store_true", help="emit full map as JSON")
    args = ap.parse_args()

    mapping = build_map()

    if args.list:
        for name in sorted(mapping):
            print(name)
            for d, f, u in mapping[name]:
                print(f"    {d}/{f}")
        print(f"\n{len(mapping)} templates with downloadable models.", file=sys.stderr)
        return 0

    if args.json:
        print(json.dumps({k: [{"directory": d, "filename": f, "url": u}
                              for d, f, u in v] for k, v in mapping.items()}, indent=2))
        return 0

    if args.all:
        names = sorted(mapping)
    elif args.templates:
        names = args.templates
    else:
        ap.error("give template names, or use --all / --list / --json")
        return 2

    missing = [n for n in names if n not in mapping]
    for n in missing:
        print(f"WARN: no models found for template '{n}'", file=sys.stderr)

    seen = set()
    for n in names:
        for d, f, u in mapping.get(n, []):
            key = (d, f)
            if key in seen:
                continue
            seen.add(key)
            print(f"{d}\t{f}\t{u}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
