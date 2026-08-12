# 進階：背景自動化（丟檔案 → 自動轉錄 → 自動分析）

基本用法是「跟 Claude Code 說話、附上錄音檔」。如果想再進一步：丟一個錄音檔進
資料夾，不用開 Claude Code 對話，背景就自動跑完轉錄、語者辨識，再用 headless
Claude Code 產出會議紀錄——這份文件記錄怎麼做，和幾個只有實測才會踩到的坑。

這不是這個 repo 直接提供的一鍵安裝工具，是一份**做法記錄**：架構、坑、一份可以
照著改的骨架腳本。要接上你自己的筆記系統/資料夾結構，自己調整路徑。

## 架構

```
<你的筆記/會議資料夾>/inbox/<專案>/   ← 錄音檔丟這裡
        │
        ▼（launchd 監控這個資料夾，偵測到新檔案就觸發）
1. ffmpeg 轉成 16kHz mono wav
2. mlx_whisper 轉錄（--condition-on-previous-text False 不能省，見下面「坑」）
3. OpenCC 簡轉繁
4. pyannote 語者辨識 + 合併標籤
5. headless 呼叫 claude -p，讀這個 skill 的邏輯，驗證+整理成會議紀錄
        │
        ▼
會議紀錄寫進你的筆記資料夾，同時跳 macOS 系統通知
```

失敗（任何一步）就把音檔連同錯誤訊息移到 `inbox/_failed/`，不動原始檔，不要
默默重試或默默丟失——尤其最後 headless 呼叫那步，**不能只看 exit code 判斷
成功**，見下面第 2 個坑。

## 實測踩過的坑

### 1. `~/Documents` 底下的專案，launchd 會被 macOS TCC 擋下

macOS 把 `~/Documents`、`~/Desktop`、`~/Downloads` 這類資料夾視為隱私保護
範圍，launchd 觸發時生出來的是全新行程，**沒有繼承 Terminal 已經被授權的
存取權**，連讀腳本檔案本身都會被拒絕（`Operation not permitted`）。手動用
Terminal 跑不會踩到，只有 launchd 自己生出來的行程才會撞牆。

**解法：把要被 launchd 觸發的腳本放在 `~/Documents` 之外**（例如直接
`$HOME` 底下的資料夾），不要因為習慣把程式碼放 Documents 就沿用同一個地方。

### 2. headless `-p` 模式預設不會自動放行寫檔，會靜默失敗

沒有明確給 `--allowedTools`，Claude 會把分析內容都想好，但寫入筆記檔案那步
被權限機制擋下，**`exit code` 還是 0**——只看 exit code 完全抓不到這個情況。
要嘛给 `--allowedTools`，跑完之後還要另外確認「有沒有真的多出一個新檔案」，
不能只信 process 的回傳值。

### 3. `--allowedTools` 用空白分隔多個工具名，會被貪婪解析吃掉 prompt

```bash
# 錯誤示範：--allowedTools 後面的引號字串被貪婪解析，
# 連後面的 prompt 都被當成工具名吃掉，導致 -p 收不到 prompt，直接報錯
claude -p --allowedTools "Read Write Edit" "分析這份逐字稿..."

# 正確：prompt 放前面，工具名用逗號分隔（單一 token，不會被貪婪吃掉）
claude -p "分析這份逐字稿..." --allowedTools "Read,Write,Edit"
```

### 4. launchd 給的 `PATH` 很陽春

只有 `/usr/bin:/bin:/usr/sbin:/sbin`，Homebrew 裝的 conda／ffmpeg／Claude
Code CLI 全部找不到。腳本一開頭要自己補：

```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
```

### 5. macOS 沒有內建 `flock(1)`

那是 Linux util-linux 的工具，BSD/macOS 預設沒有。用來避免 launchd 短時間
內重複觸發時兩份腳本互相干擾，改用 `mkdir` 做原子鎖（不需要額外裝套件）：

```bash
LOCK_DIR="/tmp/your-project.lock.d"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "已經有一份在跑，這次觸發略過"
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT
```

## 骨架腳本

`watcher.plist`（放 `~/Library/LaunchAgents/`，路徑用你自己的實際路徑替換）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.yourname.meeting-transcript-automation</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/absolute/path/to/pipeline.sh</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>/absolute/path/to/your-notes/inbox</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StandardOutPath</key>
  <string>/absolute/path/to/logs/watcher.out.log</string>
  <key>StandardErrorPath</key>
  <string>/absolute/path/to/logs/watcher.err.log</string>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
```

`pipeline.sh` 骨架（省略掉語者辨識/合併標籤的 python 細節，直接照 SKILL.md
步驟一、二的邏輯寫成腳本即可）：

```bash
#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTES_DIR="/absolute/path/to/your-notes"   # 換成你自己放會議紀錄的地方
INBOX="$NOTES_DIR/inbox"
LOCK_DIR="/tmp/meeting-transcript-automation.lock.d"

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
[ -f "$SCRIPT_DIR/.env" ] && set -a && source "$SCRIPT_DIR/.env" && set +a  # HF_TOKEN 放這裡

mkdir "$LOCK_DIR" 2>/dev/null || { echo "已經有一份在跑"; exit 0; }
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

for project_dir in "$INBOX"/*/; do
  project="$(basename "$project_dir")"
  [ "$project" = "_failed" ] && continue

  shopt -s nullglob
  for audio in "$project_dir"*.m4a "$project_dir"*.mp3 "$project_dir"*.wav; do
    slug="$(basename "${audio%.*}")"

    # 1. 轉檔 → 2. mlx_whisper（--condition-on-previous-text False）
    #    → 3. OpenCC 簡轉繁 → 4. pyannote 語者辨識 + 合併標籤
    #    （照 SKILL.md 步驟一、二寫，失敗就搬進 _failed/ 並 return/continue）

    # 5. headless 呼叫 claude -p，注意上面「坑 2、3」
    marker="$SCRIPT_DIR/logs/.marker-$slug"
    touch "$marker"
    ( cd "$NOTES_DIR" && claude -p \
        "有一份新的會議逐字稿在 <逐字稿路徑>，請照 meeting-transcript skill 的邏輯驗證並整理成會議紀錄。" \
        --allowedTools "Read,Write,Edit,Glob" ) \
      >>"$SCRIPT_DIR/logs/$slug.log" 2>&1

    new_note="$(find "$NOTES_DIR" -maxdepth 1 -name "*.md" -newer "$marker" | head -1)"
    rm -f "$marker"
    if [ -z "$new_note" ]; then
      osascript -e 'display notification "可能被權限擋下，檢查 log" with title "分析失敗"'
    else
      osascript -e "display notification \"$(basename "$new_note")\" with title \"會議紀錄好了\""
    fi
  done
  shopt -u nullglob
done
```

## 這樣做值得嗎

先問自己：這個自動化解決的是「不想每次都手動開 Claude Code 講一次」，如果你
本來就是偶爾轉一兩場會議，手動跑可能比花時間裝一套背景自動化更划算。真的常態
性需要（例如固定每週幾場會議）才值得投入。
