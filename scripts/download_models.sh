#!/usr/bin/env bash
#
# download_models.sh — download model weights for ComfyUI using comfy-cli.
#
# Model URLs are resolved straight out of the installed workflow templates
# (scripts/template_models.py), so they track whatever template version this
# venv has. Files that already exist on disk are skipped.
#
# Usage:
#   download_models.sh                 # CURATED starter set (default) — see below
#   download_models.sh --list          # list every template + its model files
#   download_models.sh --template NAME [NAME ...]   # models for those templates
#   download_models.sh --all           # every model in every template (huge!)
#
# Curated default set (tuned for the RTX 5090 / 32 GB, ~110 GB total):
#   Flux.1-dev (full)         SDXL base 1.0
#   Qwen-Image (+Lightning)   WAN 2.2 14B  (t2v + i2v)
#   LTX 2.3  (NVFP4 — native Blackwell FP4 path)
#   SeedVR2  (7B fp16 + fp8 upscaler weights, for the SeedVR2 custom node)
#
# HuggingFace auth: gated repos (Flux.1-dev, possibly LTX) need a token. Run
# `hf auth login` first, or export HF_TOKEN=hf_xxx. The token is picked up
# automatically.
#
set -uo pipefail

COMFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$COMFY_DIR/.venv/bin/python"
HF="$COMFY_DIR/.venv/bin/hf"
COMFY_CLI="$COMFY_DIR/.venv/bin/comfy"
EXTRACTOR="$COMFY_DIR/scripts/template_models.py"

# --- resolve a HuggingFace token (env > hf cli > cached token file) ----------
HF_TOKEN="${HF_TOKEN:-}"
if [ -z "$HF_TOKEN" ] && [ -x "$HF" ]; then
    HF_TOKEN="$("$HF" auth token 2>/dev/null || true)"
fi
if [ -z "$HF_TOKEN" ] && [ -f "$HOME/.cache/huggingface/token" ]; then
    HF_TOKEN="$(cat "$HOME/.cache/huggingface/token" 2>/dev/null || true)"
fi
if [ -n "$HF_TOKEN" ]; then
    echo ">> using HuggingFace token (gated repos enabled)"
else
    echo ">> no HuggingFace token found — gated repos (e.g. Flux.1-dev) may 401."
    echo "   run 'hf auth login' or export HF_TOKEN=hf_xxx, then re-run."
fi

# --- one download via comfy-cli, skipping files already present -------------
dl() {
    local dir="$1" fn="$2" url="$3"
    url="${url/\/blob\///resolve/}"          # HF blob page -> raw download
    local dest="$COMFY_DIR/models/$dir/$fn"
    if [ -f "$dest" ]; then
        echo "  [skip] $dir/$fn (exists)"
        return 0
    fi
    echo "  [get ] $dir/$fn"
    local args=(--skip-prompt --workspace "$COMFY_DIR" model download
                --url "$url" --relative-path "models/$dir" --filename "$fn")
    [ -n "$HF_TOKEN" ] && args+=(--set-hf-api-token "$HF_TOKEN")
    if ! "$COMFY_CLI" "${args[@]}"; then
        echo "  [FAIL] $dir/$fn — see message above" >&2
        FAILS+=("$dir/$fn")
    fi
}

# read "dir filename url" lines (comments / blanks ignored) and download each
download_specs() {
    local dir fn url
    while read -r dir fn url _; do
        [ -z "${dir:-}" ] && continue
        case "$dir" in \#*) continue ;; esac
        [ -z "${url:-}" ] && continue
        dl "$dir" "$fn" "$url"
    done
}

curated_specs() {
cat <<'SPECS'
# --- Flux.1-dev (full text-to-image) ---
diffusion_models flux1-dev.safetensors https://huggingface.co/Comfy-Org/flux1-dev/resolve/main/flux1-dev.safetensors
text_encoders clip_l.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors
text_encoders t5xxl_fp16.safetensors https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors
vae ae.safetensors https://huggingface.co/Comfy-Org/Lumina_Image_2.0_Repackaged/resolve/main/split_files/vae/ae.safetensors
# --- Qwen-Image (+ 8-step Lightning LoRA) ---
diffusion_models qwen_image_fp8_e4m3fn.safetensors https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_fp8_e4m3fn.safetensors
text_encoders qwen_2.5_vl_7b_fp8_scaled.safetensors https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors
vae qwen_image_vae.safetensors https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors
loras Qwen-Image-Lightning-8steps-V1.0.safetensors https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Lightning-8steps-V1.0.safetensors
# --- SDXL base 1.0 ---
checkpoints sd_xl_base_1.0.safetensors https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors
# --- WAN 2.2 14B (text-to-video + image-to-video, fp8) ---
diffusion_models wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_high_noise_14B_fp8_scaled.safetensors
diffusion_models wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_t2v_low_noise_14B_fp8_scaled.safetensors
diffusion_models wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors
diffusion_models wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors
loras wan2.2_t2v_lightx2v_4steps_lora_v1.1_high_noise.safetensors https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_t2v_lightx2v_4steps_lora_v1.1_high_noise.safetensors
loras wan2.2_t2v_lightx2v_4steps_lora_v1.1_low_noise.safetensors https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_t2v_lightx2v_4steps_lora_v1.1_low_noise.safetensors
loras wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors
loras wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors
vae wan_2.1_vae.safetensors https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors
text_encoders umt5_xxl_fp8_e4m3fn_scaled.safetensors https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors
# --- LTX 2.3 (NVFP4 base — native Blackwell FP4) ---
checkpoints ltx-2.3-22b-dev-nvfp4.safetensors https://huggingface.co/Lightricks/LTX-2.3-nvfp4/resolve/main/ltx-2.3-22b-dev-nvfp4.safetensors
loras ltx_2.3_22b_distilled_1.1_lora_dynamic_fro09_avg_rank_111_bf16.safetensors https://huggingface.co/Comfy-Org/ltx-2.3/resolve/main/split_files/loras/ltx_2.3_22b_distilled_1.1_lora_dynamic_fro09_avg_rank_111_bf16.safetensors
loras gemma-3-12b-it-abliterated_lora_rank64_bf16.safetensors https://huggingface.co/Comfy-Org/ltx-2/resolve/main/split_files/loras/gemma-3-12b-it-abliterated_lora_rank64_bf16.safetensors
latent_upscale_models ltx-2.3-spatial-upscaler-x2-1.1.safetensors https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-spatial-upscaler-x2-1.1.safetensors
# --- SeedVR2 (weights for the SeedVR2 custom node; -> models/seedvr2/) ---
seedvr2 seedvr2_ema_7b_fp16.safetensors https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_fp16.safetensors
seedvr2 seedvr2_ema_7b_fp8_e4m3fn.safetensors https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_7b_fp8_e4m3fn.safetensors
SPECS
}

FAILS=()

case "${1:-}" in
    --list)
        exec "$PY" "$EXTRACTOR" --list
        ;;
    --all)
        echo ">> ALL models from every template (this is hundreds of GB)."
        "$PY" "$EXTRACTOR" --all | download_specs
        ;;
    --template)
        shift
        [ "$#" -ge 1 ] || { echo "usage: $0 --template NAME [NAME ...]" >&2; exit 2; }
        echo ">> models for templates: $*"
        "$PY" "$EXTRACTOR" "$@" | download_specs
        ;;
    -h|--help)
        sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    "")
        echo ">> downloading CURATED starter set into $COMFY_DIR/models"
        curated_specs | download_specs
        ;;
    *)
        echo "unknown argument: $1" >&2
        echo "try: $0 [--list | --template NAME... | --all]" >&2
        exit 2
        ;;
esac

if [ "${#FAILS[@]}" -gt 0 ]; then
    echo ""
    echo ">> ${#FAILS[@]} download(s) failed:"
    printf '   - %s\n' "${FAILS[@]}"
    echo "   (gated repos? run 'hf auth login' and re-run — existing files are skipped.)"
    exit 1
fi
echo ">> done."
