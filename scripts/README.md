# ComfyUI helper scripts

This install is tuned for an **RTX 5090 (Blackwell, sm_120)**: PyTorch `cu130`,
SageAttention 2, and ComfyUI's `--fast` (fp16 accumulation + fp8 matmul). LTX 2.3
uses the **NVFP4** checkpoint for native Blackwell FP4.

## Run the server — `../comfy-ctrl.sh`
Binds `0.0.0.0:8188` and launches with `--fast --use-sage-attention --enable-manager`.

```bash
./comfy-ctrl.sh start      # background start
./comfy-ctrl.sh status     # PID + URL
./comfy-ctrl.sh log        # tail -f logs/comfyui.log  (log 500 = last 500 first)
./comfy-ctrl.sh restart
./comfy-ctrl.sh stop
```
> ⚠️ `0.0.0.0` exposes ComfyUI to the whole LAN with no authentication. Restrict
> via firewall if the host is not on a trusted network.

## Download models — `scripts/download_models.sh`
Resolves model URLs from the installed workflow templates (`template_models.py`),
downloads via `comfy-cli`, and skips files already on disk.

```bash
./scripts/download_models.sh              # CURATED set (default, ~110 GB)
./scripts/download_models.sh --list        # list every template + its models
./scripts/download_models.sh --template image_qwen_image video_wan2_2_14B_t2v
./scripts/download_models.sh --all         # every model in every template (huge)
```

**Curated set:** Flux.1-dev (full), Qwen-Image (+8-step Lightning), SDXL base 1.0,
WAN 2.2 14B (t2v + i2v), **LTX 2.3 NVFP4**, **Flux.2-dev NVFP4** (+ FP4 text encoder
+ flux2-vae), and SeedVR2 7B (fp16 + fp8) weights.

**HuggingFace auth** (required for gated repos like Flux.1-dev): run `hf auth login`
once, or `export HF_TOKEN=hf_xxx`. The token is detected automatically.

## Download template input media — `scripts/install_template_assets.sh`
Downloads the input images/audio/video that templates load (from each template's
`io.inputs`) into `../input/`, so the built-in templates run out of the box.
Thumbnails/logos are not downloaded — they ship inside the templates pip packages.

```bash
./scripts/install_template_assets.sh
```

## `scripts/template_models.py`
Library/CLI used by `download_models.sh` to extract `(directory, filename, url)`
specs from the installed templates (from each node's `properties.models` and from
model links in `MarkdownNote` nodes). `--list`, `--json`, `--all`, or template names.
