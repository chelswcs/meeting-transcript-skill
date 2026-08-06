# meeting-transcript

本機、不上傳雲端的會議錄音轉逐字稿工具，給 [Claude Code](https://claude.com/claude-code) 用的 skill。用 Apple 的 MLX 框架跑 Whisper + pyannote 做語者辨識，特別針對粵語/國語/英文混雜場景做過模型挑選。

## ⚠️ 前提：只能在 Apple Silicon Mac 上跑

核心依賴 Apple 的 MLX 框架，只支援 M1/M2/M3/M4 系列晶片。Intel Mac、Windows、Linux 都無法使用。

## 這個 skill 做什麼

跟 Claude Code 說「分析會議紀錄」，附上錄音檔，它會：

1. 本機跑 Whisper 轉出逐字稿——**不上傳任何雲端服務**，適合含敏感內容的會議
2. 統一轉成繁體中文（模型輸出簡繁混雜，會自動用 OpenCC 轉繁體）
3. 跑語者辨識（pyannote），標出「大概是誰在講話」，跟逐字稿的時間對起來
4. 讀逐字稿，整理成會議紀錄（背景、決策、待辦）

## 為什麼不用官方 Whisper 模型

官方 `whisper-large-v3-turbo` 在粵語上表現明顯偏弱（第三方測試字元錯誤率可達 45%），常把粵語自動轉寫成書面中文而非口語，還會認錯字。這個 skill 預設改用 [`JackyHoCL/whisper-large-v3-turbo-cantonese-yue-english`](https://huggingface.co/JackyHoCL/whisper-large-v3-turbo-cantonese-yue-english)（MIT 授權），一顆針對粵語/英文微調過的版本。實測粵語辨識大幅提升，國語、英文不受影響。

如果你的使用情境不涉及粵語，可以在 `SKILL.md` 裡把模型換成官方 `mlx-community/whisper-large-v3-turbo`，不用跑轉檔那一步。

## 安裝

```bash
git clone <這個 repo 的網址>
cd meeting-transcript-skill
./setup.sh
```

`setup.sh` 會自動：

- 建立獨立的 conda 環境 `whisper`（Python 3.11，避開新版 Python 相依套件缺 wheel 的問題）
- 安裝 `mlx-whisper`、`opencc-python-reimplemented`、`pyannote.audio`
- 下載並轉換粵語微調模型成 MLX 格式（約 1.6GB，第一次跑要花幾分鐘）

裝完之後，把 `.claude/skills/meeting-transcript/` 和 `scripts/` 整個複製到你自己專案底下（`scripts/` 放在專案根目錄，或跟著 SKILL.md 走都可以，SKILL.md 裡是用相對路徑 `scripts/diarize_and_label.py` 呼叫）。

### 語者辨識要多做兩件事（腳本無法代勞）

語者辨識用的模型放在 HuggingFace 上，是「需要同意條款」的 gated repo：

1. 到 [pyannote/speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1) 按一次「Agree and access repository」
2. 到 [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens) 建立一個新 token，**Token type 選 Custom**，只勾 **「Read contents of public gated repos you can access」**（不要用 Read-Only 預設，那個只涵蓋你自己帳號底下的 repo，涵蓋不到 pyannote 這種別人帳號的公開模型，會抓不到檔案）
3. 把 token 存到 `~/.zshenv`（**不是** `~/.zshrc`——`.zshrc` 只有互動式終端機才會載入，Claude Code 背景執行指令時讀不到）：
   ```bash
   echo 'export HF_TOKEN="你的 token"' >> ~/.zshenv
   ```

沒設定 `HF_TOKEN` 不影響單純轉逐字稿，只有語者辨識那步會需要它。

## 使用

在 Claude Code 裡：「分析會議紀錄」+ 給錄音檔路徑。

## 已知限制

- **短插話容易被吞併**：一兩秒的回應（「嗯」、「OK」、笑聲）常被合併進旁邊那段較長發言的語者標籤裡，語者標籤是「大致對」，不是逐字精準
- 兩人以上同時講話、背景吵雜會影響準確度
- 長錄音（1 小時以上）轉錄 + 語者辨識合計要等幾分鐘到十幾分鐘
- 長錄音容易觸發 Whisper 的「幻覺迴圈」bug（同一個詞卡住重複輸出、後面內容消失），已經用 `--condition-on-previous-text False` 參數處理，SKILL.md 的指令範例已內建這個參數，不要拿掉

## 授權與致謝

這個 repo（README、SKILL.md、setup.sh、scripts/）採 MIT 授權。

依賴：
- [mlx-whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper)（Apache 2.0，Apple）
- [JackyHoCL/whisper-large-v3-turbo-cantonese-yue-english](https://huggingface.co/JackyHoCL/whisper-large-v3-turbo-cantonese-yue-english)（MIT）——發布前建議自行確認原始授權聲明
- [pyannote.audio](https://github.com/pyannote/pyannote-audio) + [pyannote/speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1)（CC-BY-4.0）
