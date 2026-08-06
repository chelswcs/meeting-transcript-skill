#!/usr/bin/env bash
# 安裝 meeting-transcript skill 需要的環境：獨立 conda 環境、mlx-whisper、
# pyannote.audio（語者辨識）。官方 Whisper 模型會在第一次轉錄時自動下載，
# 不用另外轉檔。
#
# 加 --cantonese 參數，會額外轉換一顆粵語/英文微調過的模型（給粵語為主的
# 會議用，見 README「模型選擇」一節）：
#     ./setup.sh --cantonese
#
# 只能在 Apple Silicon Mac（M1/M2/M3/M4）上跑，因為核心依賴 Apple 的 MLX 框架。
set -euo pipefail

WITH_CANTONESE=false
if [[ "${1:-}" == "--cantonese" ]]; then
  WITH_CANTONESE=true
fi

echo "== 檢查是否為 Apple Silicon =="
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "偵測到 $(uname -m)，這個 skill 需要 Apple Silicon Mac，無法繼續。" >&2
  exit 1
fi

echo "== 檢查 conda =="
if ! command -v conda &> /dev/null; then
  echo "找不到 conda。先裝 Miniconda：https://docs.conda.io/en/latest/miniconda.html" >&2
  exit 1
fi

echo "== 檢查 ffmpeg（mlx-whisper 解碼音檔需要）=="
if ! command -v ffmpeg &> /dev/null; then
  echo "找不到 ffmpeg。先跑：brew install ffmpeg" >&2
  exit 1
fi

echo "== 建立獨立 conda 環境 whisper（Python 3.11）=="
# 用 3.11 而不是最新版：mlx-whisper 的部分相依套件在 3.13 上還沒有現成的
# wheel，裝的時候可能失敗或退回原始碼編譯，用 3.11 比較穩。
if conda env list | grep -q "^whisper "; then
  echo "環境 whisper 已存在，略過建立"
else
  conda create -n whisper python=3.11 -y
fi

# shellcheck source=/dev/null
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate whisper

echo "== 安裝 mlx-whisper、opencc（簡轉繁）、pyannote.audio（語者辨識）=="
pip install --upgrade mlx-whisper opencc-python-reimplemented pyannote.audio

if [[ "$WITH_CANTONESE" == true ]]; then
  echo "== 下載模型轉換腳本（Apple 官方 mlx-examples repo）=="
  TMP_DIR="$(mktemp -d)"
  curl -fsSL https://raw.githubusercontent.com/ml-explore/mlx-examples/main/whisper/convert.py \
    -o "$TMP_DIR/convert.py"

  echo "== 轉換粵語/英文微調模型成 MLX 格式（約 1.6GB，第一次跑要花幾分鐘）=="
  MODEL_DIR="$HOME/.cache/mlx-whisper-models/cantonese-yue-english"
  mkdir -p "$MODEL_DIR"
  python "$TMP_DIR/convert.py" \
    --torch-name-or-path JackyHoCL/whisper-large-v3-turbo-cantonese-yue-english \
    --mlx-path "$MODEL_DIR" \
    --dtype float16

  echo "== 修正檔名 =="
  # convert.py 把權重存成 model.safetensors，但 mlx-whisper 讀取時找的是
  # weights.safetensors，不重新命名的話轉錄會直接找不到模型檔報錯。
  if [[ -f "$MODEL_DIR/model.safetensors" ]]; then
    mv "$MODEL_DIR/model.safetensors" "$MODEL_DIR/weights.safetensors"
  fi

  echo "== 修回 numpy>=2 =="
  # 上一步轉檔會用到 torch，它的相依有時會把 numpy 降到 1.x，而 mlx 需要
  # numpy>=2 才能正常運作，轉完檔要修回來。
  pip install "numpy>=2" --upgrade

  rm -rf "$TMP_DIR"
  echo "粵語模型存在：$MODEL_DIR"
else
  echo "== 略過粵語微調模型（預設用官方模型，會議以粵語為主才需要，見 README）=="
  echo "需要的話之後可以重跑：./setup.sh --cantonese"
fi

echo
echo "完成。官方模型會在第一次執行 mlx_whisper 時自動下載，不用另外處理。"
echo
echo "== 語者辨識還需要你自己做兩件事（無法用腳本代勞）=="
echo "1. 到 https://huggingface.co/pyannote/speaker-diarization-community-1"
echo "   按一次 Agree and access repository 同意使用條款"
echo "2. 到 https://huggingface.co/settings/tokens 建立一個新 token，"
echo "   Token type 選 Custom，只勾 'Read contents of public gated repos"
echo "   you can access'（不要勾 Read-Only preset，那個只涵蓋你自己的 repo，"
echo "   涵蓋不到 pyannote 這種別人帳號的公開模型）"
echo "3. 把 token 存成環境變數，注意是 ~/.zshenv 不是 ~/.zshrc"
echo "   （.zshrc 只有互動式終端機才會載入，Claude Code 背景執行指令時讀不到）："
echo "     echo 'export HF_TOKEN=\"你的 token\"' >> ~/.zshenv"
echo
echo "接下來把 .claude/skills/meeting-transcript/SKILL.md 和 scripts/ 資料夾"
echo "複製到你專案的 .claude/skills/meeting-transcript/ 底下，Claude Code 就能用了。"
