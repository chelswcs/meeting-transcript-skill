---
name: meeting-transcript
description: 把會議錄音轉成逐字稿並整理成會議紀錄分析。使用者說「分析會議紀錄」、「把這段錄音轉成會議紀錄」或給一段錄音檔要求整理重點時使用。全程本機執行（mlx-whisper），不上傳雲端，適合含敏感內容的會議。國語/英文/粵語混雜場景準確度較高。
---

# 會議錄音 → 逐字稿 → 會議紀錄分析

本機用 Apple MLX 跑 Whisper（粵語/國語/英文微調模型），錄音不會上傳到任何雲端
服務。整套流程分兩階段：**轉逐字稿**（機械式、不可省略驗證）→**讀逐字稿產出
分析**（LLM 讀懂內容後整理）。

## 前置需求

**只能在 Apple Silicon Mac（M1/M2/M3/M4）上跑**——核心依賴 Apple 的 MLX 框架，
Intel Mac / Windows / Linux 都不支援。

第一次使用前，先跑這個 repo 根目錄的 `setup.sh`：

```bash
./setup.sh
```

會自動建立獨立 conda 環境 `whisper`（Python 3.11）、裝 `mlx-whisper` 和
`opencc-python-reimplemented`、下載並轉換一顆粵語/英文微調過的模型成 MLX 格式
（存在 `~/.cache/mlx-whisper-models/cantonese-yue-english`，約 1.6GB，第一次
跑要花幾分鐘）。裝好之後這個步驟不用重跑。

## 為什麼不用官方 Whisper 模型

官方 `whisper-large-v3-turbo` 在粵語上表現明顯偏弱（第三方測試字元錯誤率可達
45%），常把粵語自動轉寫成書面中文而非口語，還會認錯字。這裡預設用
[`JackyHoCL/whisper-large-v3-turbo-cantonese-yue-english`](https://huggingface.co/JackyHoCL/whisper-large-v3-turbo-cantonese-yue-english)
（MIT 授權），實測粵語辨識大幅提升，國語、英文不受影響。如果你的會議不涉及
粵語，也可以把下面指令裡的 `--model` 換成官方
`mlx-community/whisper-large-v3-turbo`，不用額外轉檔。

## 步驟 1：轉逐字稿

1. 跟使用者確認錄音檔路徑（不要猜路徑，音檔可能在錄音 App 匯出的資料夾，
   或使用者直接把檔案路徑貼過來）
2. 執行轉錄：

```bash
source "$(conda info --base)/etc/profile.d/conda.sh" && conda activate whisper
mkdir -p meetings/transcripts
mlx_whisper "<音檔路徑>" \
  --model ~/.cache/mlx-whisper-models/cantonese-yue-english \
  -f txt -o meetings/transcripts
```

輸出檔名跟音檔同名（副檔名換成 .txt），存在 `meetings/transcripts/`（沒有這個
資料夾就依專案慣例改存到別處，重點是不要進 git，逐字稿常含敏感內容）。

3. **轉出來的中文一律轉繁體**（模型的國語訓練資料是簡體、粵語訓練資料是繁體，
   同一份逐字稿可能簡繁混雜）：

```bash
python3 -c "
from opencc import OpenCC
cc = OpenCC('s2t')
path = 'meetings/transcripts/<檔名>.txt'
text = open(path, encoding='utf-8').read()
open(path, 'w', encoding='utf-8').write(cc.convert(text))
"
```

4. **驗證**：實際打開這個 txt 檔讀一遍前幾行，確認真的有轉出文字、不是空檔或
   亂碼，再往下一步——不能只看指令碼 exit code 就當作成功。

## 步驟 2：讀逐字稿，產出會議紀錄分析

1. 讀剛產出的逐字稿全文
2. 整理成會議紀錄，內容至少包含：
   - 背景（哪個專案、跟誰開的會）
   - 重點決策 / 結論
   - 待辦事項（誰要做什麼）
   - 有疑義或需要使用者後續確認的地方
3. 如果專案內已經有既有的會議筆記格式（例如固定的 frontmatter），沿用那個
   格式；沒有的話用簡單的標題 + 條列即可
4. 逐字稿本身沒有語者分離（whisper 不做 diarization，分不出是誰在講話），
   分析時如果內容明顯是對話，要在文字裡自行推斷語氣轉折、不要假裝分得出
   說話者——不確定是誰講的就別瞎猜

## 已知限制

- 沒有語者辨識（speaker diarization）——逐字稿是連續文字，不會標示「誰說的」
- 長錄音（1 小時以上）轉錄需要幾分鐘，跑之前跟使用者說一下要等
- 只支援單一語者清楚說話的情況；多人同時講話、背景吵雜會影響準確度
- 只能在 Apple Silicon Mac 上跑
