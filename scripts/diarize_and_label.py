#!/usr/bin/env python3
"""
把 mlx-whisper 轉出的逐字稿（json，含每段時間戳）跟 pyannote 語者辨識的結果
合併，輸出成帶語者標籤的文字稿。

用法：
    python3 diarize_and_label.py <音檔.wav> <逐字稿.json> <輸出.txt>

需要環境變數 HF_TOKEN（Hugging Face token，權限要包含
"Read contents of public gated repos you can access"）。
"""
import json
import os
import sys


def clean_diarization(raw_segments, merge_gap=0.5, min_duration=0.3):
    """合併同語者、間隔在 merge_gap 秒內的段落，濾掉合併後仍過短的碎片。"""
    merged = []
    for start, end, speaker in sorted(raw_segments):
        if merged and merged[-1][2] == speaker and start - merged[-1][1] <= merge_gap:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end), speaker)
        else:
            merged.append((start, end, speaker))
    return [seg for seg in merged if seg[1] - seg[0] >= min_duration]


def overlap(a_start, a_end, b_start, b_end):
    return max(0, min(a_end, b_end) - max(a_start, b_start))


def label_transcript(whisper_segments, diar_segments):
    """把逐字稿每一段標上重疊最多的語者，再合併連續同語者的段落。"""
    labeled = []
    for seg in whisper_segments:
        s, e, text = seg["start"], seg["end"], seg["text"].strip()
        best_speaker, best_overlap = "未知語者", 0
        for ds, de, speaker in diar_segments:
            ov = overlap(s, e, ds, de)
            if ov > best_overlap:
                best_overlap, best_speaker = ov, speaker
        labeled.append((s, e, best_speaker, text))

    blocks = []
    for s, e, speaker, text in labeled:
        if blocks and blocks[-1][2] == speaker:
            blocks[-1] = (blocks[-1][0], e, speaker, blocks[-1][3] + text)
        else:
            blocks.append((s, e, speaker, text))
    return blocks


def run_diarization(audio_path):
    import torch
    from pyannote.audio import Pipeline

    token = os.environ.get("HF_TOKEN")
    if not token:
        print(
            "找不到 HF_TOKEN 環境變數。需要一個 Hugging Face token，權限要包含"
            ' "Read contents of public gated repos you can access"，並先到'
            " https://huggingface.co/pyannote/speaker-diarization-community-1"
            " 同意使用條款。",
            file=sys.stderr,
        )
        sys.exit(1)

    pipeline = Pipeline.from_pretrained(
        "pyannote/speaker-diarization-community-1", token=token
    )
    if torch.backends.mps.is_available():
        pipeline.to(torch.device("mps"))

    result = pipeline(audio_path)
    diar = result.speaker_diarization
    raw = [(t.start, t.end, spk) for t, _, spk in diar.itertracks(yield_label=True)]
    return clean_diarization(raw)


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)

    audio_path, transcript_json_path, output_path = sys.argv[1:4]

    whisper = json.load(open(transcript_json_path, encoding="utf-8"))
    diar_segments = run_diarization(audio_path)
    speaker_count = len(set(s[2] for s in diar_segments))
    print(f"偵測到 {speaker_count} 位語者，{len(diar_segments)} 個發言段落")

    blocks = label_transcript(whisper["segments"], diar_segments)

    lines = []
    for s, _e, speaker, text in blocks:
        mm, ss = int(s // 60), int(s % 60)
        lines.append(f"[{mm:02d}:{ss:02d}] {speaker}\n{text}")

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n\n".join(lines))

    print(f"寫出 {len(blocks)} 個發言區塊到 {output_path}")


if __name__ == "__main__":
    main()
