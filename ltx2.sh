#!/usr/bin/env bash
set -euo pipefail

#
# Title: ltx2.sh (Vast.ai compatible)
# Author: FNGarvin (modified for Vast templates)
#

# --- Configuration ---
COMFYUI_DIR="${COMFYUI_DIR:-}"   # allow override: COMFYUI_DIR=/workspace/ComfyUI bash ltx2.sh

MADAPPS_PATH="/workspace/madapps/ComfyUI"
RUNPOD_SLIM_PATH="/workspace/runpod-slim/ComfyUI"
VAST_DEFAULT_PATH="/workspace/ComfyUI"

# --- Detect ComfyUI dir ---
if [ -n "${COMFYUI_DIR}" ] && [ -d "${COMFYUI_DIR}" ]; then
    echo "INFO: Using COMFYUI_DIR override: ${COMFYUI_DIR}"
elif [ -d "${MADAPPS_PATH}" ]; then
    COMFYUI_DIR="${MADAPPS_PATH}"
    echo "INFO: Detected ComfyUI in Madiator's custom 'madapps' path."
elif [ -d "${RUNPOD_SLIM_PATH}" ]; then
    COMFYUI_DIR="${RUNPOD_SLIM_PATH}"
    echo "INFO: Detected ComfyUI in standard 'runpod-slim' path."
elif [ -d "${VAST_DEFAULT_PATH}" ]; then
    COMFYUI_DIR="${VAST_DEFAULT_PATH}"
    echo "INFO: Detected ComfyUI in Vast default path: ${VAST_DEFAULT_PATH}"
elif [ -f "./main.py" ] && [ -d "./models" ]; then
    COMFYUI_DIR="$(pwd)"
    echo "INFO: Detected ComfyUI in current directory: ${COMFYUI_DIR}"
else
    echo "ERROR: ComfyUI directory not found."
    echo "       Tried: ${MADAPPS_PATH}, ${RUNPOD_SLIM_PATH}, ${VAST_DEFAULT_PATH}, and current directory."
    exit 1
fi

# --- Detect Python to use ---
# Prefer active venv (Vast typically: /venv/main), otherwise fall back to system python.
if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "${VIRTUAL_ENV}/bin/python" ]; then
    VENV_PYTHON="${VIRTUAL_ENV}/bin/python"
elif [ -x "/venv/main/bin/python" ]; then
    VENV_PYTHON="/venv/main/bin/python"
else
    VENV_PYTHON="$(command -v python3 || command -v python)"
fi
readonly VENV_PYTHON

echo "INFO: COMFYUI_DIR=${COMFYUI_DIR}"
echo "INFO: VENV_PYTHON=${VENV_PYTHON}"

# Put log in a path that exists
EXTERNAL_LOG="${EXTERNAL_LOG:-${COMFYUI_DIR}/comfyui.log}"

# --- 1. Infrastructure & Node Setup ---
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y --no-install-recommends aria2 curl git ca-certificates
else
    echo "WARN: apt-get not found; assuming aria2/curl/git already installed."
fi

safe_clone_and_install() {
    local repo_url="$1"
    local dest_dir="$2"

    mkdir -p "$(dirname "$dest_dir")"

    if [ ! -d "${dest_dir}" ]; then
        echo "INFO: Cloning ${repo_url}..."
        git clone "${repo_url}" "${dest_dir}"
    else
        echo "INFO: Node already present: ${dest_dir}"
    fi

    if [ -f "${dest_dir}/requirements.txt" ]; then
        echo "INFO: Installing node requirements for $(basename "$dest_dir")..."
        "${VENV_PYTHON}" -m pip install --no-cache-dir -r "${dest_dir}/requirements.txt"
    fi
}

safe_clone_and_install "https://github.com/Lightricks/ComfyUI-LTXVideo" "${COMFYUI_DIR}/custom_nodes/ComfyUI-LTXVideo"
safe_clone_and_install "https://github.com/evanspearman/ComfyMath" "${COMFYUI_DIR}/custom_nodes/ComfyMath"
safe_clone_and_install "https://github.com/ltdrdata/ComfyUI-Impact-Pack" "${COMFYUI_DIR}/custom_nodes/ComfyUI-Impact-Pack"
# RunpodDirect is optional on Vast; keep it if your workflow uses it.
safe_clone_and_install "https://github.com/MadiatorLabs/ComfyUI-RunpodDirect" "${COMFYUI_DIR}/custom_nodes/ComfyUI-RunpodDirect"

# --- 2. Model Downloads ---
echo "INFO: Checking LTX-2 Distilled model, VAEs, LoRAs, and Unsloth Text Encoder..."

CHECKPOINT_DIR="${COMFYUI_DIR}/models/checkpoints"
UPSCALE_DIR="${COMFYUI_DIR}/models/latent_upscale_models"
AUDIO_VAE_DIR="${COMFYUI_DIR}/models/audio_vae"
LORA_DIR="${COMFYUI_DIR}/models/loras"
UNSLOTH_DIR="${COMFYUI_DIR}/models/text_encoders/unsloth"

mkdir -p "${CHECKPOINT_DIR}" "${UPSCALE_DIR}" "${AUDIO_VAE_DIR}" "${LORA_DIR}" "${UNSLOTH_DIR}"

safe_download() {
    local dir="$1"
    local file="$2"
    local url="$3"

    if [ ! -f "${dir}/${file}" ]; then
        echo "INFO: Downloading ${file}..."
        aria2c -x 16 -s 16 --dir="${dir}" -o "${file}" "${url}"
    else
        echo "INFO: Skipping download; ${file} already exists."
    fi
}

safe_download "${CHECKPOINT_DIR}" "ltx-2-19b-distilled-fp8.safetensors" "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-19b-distilled-fp8.safetensors?download=true"
safe_download "${UPSCALE_DIR}" "ltx-2-spatial-upscaler-x2-1.0.safetensors" "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-spatial-upscaler-x2-1.0.safetensors?download=true"
safe_download "${UPSCALE_DIR}" "ltx-2-temporal-upscaler-x2-1.0.safetensors" "https://huggingface.co/Lightricks/LTX-2/resolve/main/ltx-2-temporal-upscaler-x2-1.0.safetensors?download=true"
safe_download "${AUDIO_VAE_DIR}" "ltx-audio-vae.safetensors" "https://huggingface.co/Lightricks/LTX-2/resolve/main/audio_vae/diffusion_pytorch_model.safetensors?download=true"

LORA_BASE="https://huggingface.co/Lightricks"
safe_download "${LORA_DIR}" "ltx-2-19b-ic-lora-canny-control.safetensors" "${LORA_BASE}/LTX-2-19b-IC-LoRA-Canny-Control/resolve/main/ltx-2-19b-ic-lora-canny-control.safetensors?download=true"
safe_download "${LORA_DIR}" "ltx-2-19b-ic-lora-depth-control.safetensors" "${LORA_BASE}/LTX-2-19b-IC-LoRA-Depth-Control/resolve/main/ltx-2-19b-ic-lora-depth-control.safetensors?download=true"
safe_download "${LORA_DIR}" "ltx-2-19b-ic-lora-detailer.safetensors" "${LORA_BASE}/LTX-2-19b-IC-LoRA-Detailer/resolve/main/ltx-2-19b-ic-lora-detailer.safetensors?download=true"
safe_download "${LORA_DIR}" "ltx-2-19b-ic-lora-pose-control.safetensors" "${LORA_BASE}/LTX-2-19b-IC-LoRA-Pose-Control/resolve/main/ltx-2-19b-ic-lora-pose-control.safetensors?download=true"
safe_download "${LORA_DIR}" "ltx-2-19b-lora-camera-control-static.safetensors" "${LORA_BASE}/LTX-2-19b-LoRA-Camera-Control-Static/resolve/main/ltx-2-19b-lora-camera-control-static.safetensors?download=true"

safe_download "${LORA_DIR}" "ltx-2-19b-lora-camera-control-dolly-in.safetensors" "${LORA_BASE}/LTX-2-19b-LoRA-Camera-Control-Dolly-In/resolve/main/ltx-2-19b-lora-camera-control-dolly-in.safetensors?download=true"
safe_download "${LORA_DIR}" "ltx-2-19b-lora-camera-control-dolly-out.safetensors" "${LORA_BASE}/LTX-2-19b-LoRA-Camera-Control-Dolly-Out/resolve/main/ltx-2-19b-lora-camera-control-dolly-out.safetensors?download=true"
safe_download "${LORA_DIR}" "ltx-2-19b-lora-camera-control-dolly-left.safetensors" "${LORA_BASE}/LTX-2-19b-LoRA-Camera-Control-Dolly-Left/resolve/main/ltx-2-19b-lora-camera-control-dolly-left.safetensors?download=true"
safe_download "${LORA_DIR}" "ltx-2-19b-lora-camera-control-dolly-right.safetensors" "${LORA_BASE}/LTX-2-19b-LoRA-Camera-Control-Dolly-Right/resolve/main/ltx-2-19b-lora-camera-control-dolly-right.safetensors?download=true"

safe_download "${LORA_DIR}" "ltx-2-19b-lora-camera-control-jib-up.safetensors" "${LORA_BASE}/LTX-2-19b-LoRA-Camera-Control-Jib-Up/resolve/main/ltx-2-19b-lora-camera-control-jib-up.safetensors?download=true"
safe_download "${LORA_DIR}" "ltx-2-19b-lora-camera-control-jib-down.safetensors" "${LORA_BASE}/LTX-2-19b-LoRA-Camera-Control-Jib-Down/resolve/main/ltx-2-19b-lora-camera-control-jib-down.safetensors?download=true"

# Unsloth 4-bit Gemma
echo "INFO: Preparing download for Unsloth bnb-4bit Gemma..."
"${VENV_PYTHON}" -m pip install bitsandbytes 'accelerate>=0.26.0'

UNSLOTH_BASE="https://huggingface.co/unsloth/gemma-3-12b-it-bnb-4bit/resolve/main"
UNSLOTH_FILES=(
  ".gitattributes" "README.md" "added_tokens.json" "chat_template.jinja"
  "chat_template.json" "config.json" "generation_config.json"
  "model-00001-of-00002.safetensors" "model-00002-of-00002.safetensors"
  "model.safetensors.index.json" "preprocessor_config.json" "processor_config.json"
  "special_tokens_map.json" "tokenizer.json" "tokenizer.model" "tokenizer_config.json"
)

for file in "${UNSLOTH_FILES[@]}"; do
  if [ ! -f "${UNSLOTH_DIR}/${file}" ]; then
    echo "INFO: Downloading ${file} from Unsloth..."
    aria2c -x 16 -s 16 --dir="${UNSLOTH_DIR}" -o "${file}" "${UNSLOTH_BASE}/${file}?download=true"
  else
    echo "INFO: Skipping ${file}; already exists."
  fi
done

# --- 3. Surgical Code Patches (Prescribed Only) ---
echo "INFO: Applying prescribed code patches..."
E_PATCH_FILE="${COMFYUI_DIR}/comfy/ldm/lightricks/embeddings_connector.py"

if [ -f "${E_PATCH_FILE}" ]; then
  if ! grep -q "to(hidden_states.device)" "${E_PATCH_FILE}"; then
    sed -i 's/learnable_registers\[hidden_states.shape\[1\]:\].unsqueeze(0).repeat(hidden_states.shape\[0\], 1, 1))/learnable_registers\[hidden_states.shape\[1\]:\].unsqueeze(0).repeat(hidden_states.shape\[0\], 1, 1).to(hidden_states.device))/g' "${E_PATCH_FILE}"
  fi
else
  echo "WARN: Patch target not found (ok if your ComfyUI build differs): ${E_PATCH_FILE}"
fi

# --- 4. Restart & Alignment ---
echo "INFO: Aligning core requirements and restarting ComfyUI with --reserve-vram 4..."
"${VENV_PYTHON}" -m pip install --no-cache-dir -r "${COMFYUI_DIR}/requirements.txt"

pkill -f "${COMFYUI_DIR}/main.py" || pkill -f "ComfyUI.*main.py" || true
mkdir -p "$(dirname "${EXTERNAL_LOG}")"
: > "${EXTERNAL_LOG}"

echo "EXEC: nohup ${VENV_PYTHON} ${COMFYUI_DIR}/main.py --listen 0.0.0.0 --port 8188 --reserve-vram 4 > ${EXTERNAL_LOG} 2>&1 &"
nohup "${VENV_PYTHON}" "${COMFYUI_DIR}/main.py" --listen 0.0.0.0 --port 8188 --reserve-vram 4 > "${EXTERNAL_LOG}" 2>&1 &

echo "INFO: Provisioning complete. ComfyUI is starting."
echo "INFO: Log: ${EXTERNAL_LOG}"
