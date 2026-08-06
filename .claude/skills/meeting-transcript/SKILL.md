---
name: meeting-transcript
description: 把會議錄音轉成逐字稿（含語者辨識）並整理成會議紀錄分析。使用者說「分析會議紀錄」、「把這段錄音轉成會議紀錄」或給一段錄音檔要求整理重點時使用。全程本機執行（mlx-whisper + pyannote），不上傳雲端，適合含敏感內容的會議。國語/英文/粵語混雜場景準確度較高。
---

# 會議錄音 → 逐字稿（含語者標籤）→ 會議紀錄分析

本機用 Apple MLX 跑 Whisper（粵語/國語/英文微調模型）+ pyannote.audio 做語者
辨識，錄音不會上傳到任何雲端服務。整套流程分三階段：**轉逐字稿**（機械式、
不可省略驗證）→**語者辨識並合併**（機械式，用 `scripts/diarize_and_label.py`）
→**讀逐字稿產出分析**（LLM 讀懂內容後整理）。

## 前置需求

**只能在 Apple Silicon Mac（M1/M2/M3/M4）上跑**——核心依賴 Apple 的 MLX 框架。

第一次使用前，先跑這個 repo 根目錄的 `setup.sh`，並照 README 完成語者辨識需要
的 HuggingFace token 設定（腳本裝得完套件，但同意條款、建立 token 這兩步需要
使用者自己在瀏覽器上做）。

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
2. 先轉成乾淨的 16kHz mono wav（避開 m4a/mp3 容器格式偶爾造成的解碼誤差，
   語者辨識尤其容易因此直接報錯）：

```bash
mkdir -p meetings/transcripts
ffmpeg -y -i "<音檔路徑>" -ar 16000 -ac 1 meetings/transcripts/<檔名>.wav
```

3. 執行轉錄。**`--condition-on-previous-text False` 這個參數不能省**——
   長錄音沒加這個參數容易觸發 Whisper 的「幻覺迴圈」，同一個詞連續重複幾百次、
   後面整段內容直接消失不轉，而且看起來像是「有輸出」不容易發現：

```bash
source "$(conda info --base)/etc/profile.d/conda.sh" && conda activate whisper
mlx_whisper meetings/transcripts/<檔名>.wav \
  --model ~/.cache/mlx-whisper-models/cantonese-yue-english \
  --condition-on-previous-text False \
  -f json -o meetings/transcripts
```

用 `-f json`（不是 txt）才會保留每段的時間戳，語者辨識合併需要用到。

4. **轉出來的中文一律轉繁體**（模型的國語訓練資料是簡體、粵語訓練資料是
   繁體，同一份逐字稿可能簡繁混雜）：

```bash
source "$(conda info --base)/etc/profile.d/conda.sh" && conda activate whisper
python3 -c "
import json
from opencc import OpenCC
cc = OpenCC('s2t')
path = 'meetings/transcripts/<檔名>.json'
d = json.load(open(path, encoding='utf-8'))
d['text'] = cc.convert(d['text'])
for seg in d['segments']:
    seg['text'] = cc.convert(seg['text'])
json.dump(d, open(path, 'w', encoding='utf-8'), ensure_ascii=False)
"
```

5. **驗證**：實際打開這個 json 檔，讀完整份的 `segments[].text`，逐段確認
   ——特別注意有沒有同一句話連續重複幾十次的段落（幻覺迴圈殘留，代表哪裡
   還是漏轉了），不能只看指令碼 exit code 就當作成功。

## 步驟 2：語者辨識並跟逐字稿合併

用這個 repo 附的腳本（`scripts/diarize_and_label.py`），一次做完語者辨識 +
跟逐字稿合併：

```bash
source "$(conda info --base)/etc/profile.d/conda.sh" && conda activate whisper
python3 scripts/diarize_and_label.py \
  meetings/transcripts/<檔名>.wav \
  meetings/transcripts/<檔名>.json \
  meetings/transcripts/<檔名>-labeled.txt
```

需要環境變數 `HF_TOKEN`（見 README 的設定步驟）。如果 `HF_TOKEN` 沒設好，這
一步會直接報錯並說明原因，不會默默失敗。

**驗證**：打開 `<檔名>-labeled.txt` 讀一遍，語者切換的地方是否符合對話常理
（例如不會一句話中間莫名切換語者）；`SPEAKER_00`/`SPEAKER_01` 只是編號，不知道
對應到誰時如實寫「語者 1/2」，不要自己猜名字。

## 步驟 3：讀逐字稿，產出會議紀錄分析

1. 讀 `<檔名>-labeled.txt` 全文
2. 整理成會議紀錄，內容至少包含：
   - 背景（哪個專案、跟誰開的會）
   - 重點決策 / 結論
   - 待辦事項（誰要做什麼）
   - 有疑義或需要使用者後續確認的地方
3. 如果專案內已經有既有的會議筆記格式（例如固定的 frontmatter），沿用那個
   格式；沒有的話用簡單的標題 + 條列即可
4. 語者標籤是機器分出來的（`SPEAKER_00`/`SPEAKER_01`），不代表一定對應到
   「誰」——內容能明確判斷是誰講的才寫名字，不確定就寫「語者 1/2」，不要
   自己瞎猜

## 已知限制

- **短插話容易被吞併**：一兩秒的回應（「嗯」、「OK」、笑聲）常常被合併進
  旁邊那段較長發言的語者標籤裡，因為 whisper 的段落切分沒有細到能單獨框出
  這種插話——語者標籤是「大致對」，不是逐字精準
- 兩人以上同時講話、背景吵雜會影響準確度
- 長錄音（1 小時以上）轉錄 + 語者辨識合計要等幾分鐘到十幾分鐘，跑之前跟
  使用者說一下要等
- 只能在 Apple Silicon Mac 上跑
- `HF_TOKEN` 沒有正確權限（要「Read contents of public gated repos you can
  access」）會在語者辨識那步報錯，見 README 的 token 建立步驟
