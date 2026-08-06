# meeting-transcript

本機、不上傳雲端的會議錄音轉逐字稿工具，給 [Claude Code](https://claude.com/claude-code) 用的 skill。用 Apple 的 MLX 框架跑 Whisper，特別針對粵語/國語/英文混雜場景做過模型挑選。

## ⚠️ 前提：只能在 Apple Silicon Mac 上跑

核心依賴 Apple 的 MLX 框架，只支援 M1/M2/M3/M4 系列晶片。Intel Mac、Windows、Linux 都無法使用。

## 這個 skill 做什麼

跟 Claude Code 說「分析會議紀錄」，附上錄音檔，它會：

1. 本機跑 Whisper 轉出逐字稿——**不上傳任何雲端服務**，適合含敏感內容的會議
2. 統一轉成繁體中文（模型輸出簡繁混雜，會自動用 OpenCC 轉繁體）
3. 讀逐字稿，整理成會議紀錄（背景、決策、待辦）

## 為什麼不用官方 Whisper 模型

官方 `whisper-large-v3-turbo` 在粵語上表現明顯偏弱（第三方測試字元錯誤率可達 45%），常把粵語自動轉寫成書面中文而非口語，還會認錯字。這個 skill 預設改用 [`JackyHoCL/whisper-large-v3-turbo-cantonese-yue-english`](https://huggingface.co/JackyHoCL/whisper-large-v3-turbo-cantonese-yue-english)（MIT 授權），一顆針對粵語/英文微調過的版本。實測（合成語音樣本比較）粵語辨識大幅提升，國語、英文不受影響。

如果你的使用情境不涉及粵語，可以在 `SKILL.md` 裡把模型換成官方 `mlx-community/whisper-large-v3-turbo`，不用跑轉檔那一步。

## 安裝

```bash
git clone <這個 repo 的網址>
cd meeting-transcript-skill
./setup.sh
```

`setup.sh` 會自動：

- 建立獨立的 conda 環境 `whisper`（Python 3.11，避開新版 Python 相依套件缺 wheel 的問題）
- 安裝 `mlx-whisper`、`opencc-python-reimplemented`
- 下載並轉換粵語微調模型成 MLX 格式（約 1.6GB，第一次跑要花幾分鐘）

裝完之後，把 `.claude/skills/meeting-transcript/` 整個資料夾複製到你自己專案的 `.claude/skills/` 底下。

## 使用

在 Claude Code 裡：「分析會議紀錄」+ 給錄音檔路徑。

## 已知限制

- 沒有語者辨識（speaker diarization）——分不出是誰在講話
- 長錄音（1 小時以上）轉錄要等幾分鐘
- 多人同時講話、背景吵雜會影響準確度

## 授權與致謝

這個 repo（README、SKILL.md、setup.sh）採 MIT 授權。

依賴：
- [mlx-whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper)（Apache 2.0，Apple）
- [JackyHoCL/whisper-large-v3-turbo-cantonese-yue-english](https://huggingface.co/JackyHoCL/whisper-large-v3-turbo-cantonese-yue-english)（MIT）——發布前建議自行確認原始授權聲明
