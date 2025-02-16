#!/usr/bin/env python3
import sys
import os
from xml.sax.saxutils import unescape

if len(sys.argv) != 2:
    sys.exit("Usage: {} <outdir>".format(sys.argv[0]))

outdir = sys.argv[1]
os.makedirs(outdir, exist_ok=True)

# Output files
seg_path = os.path.join(outdir, "segments")
txt_path = os.path.join(outdir, "text")
utt2spk_path = os.path.join(outdir, "utt2spk")

with open(seg_path, "a") as seg_f, \
     open(txt_path, "a") as txt_f, \
     open(utt2spk_path, "a") as utt_f:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        # Expected input format:
        #   <basename> <annotator> <start> <end> <word1> <word2> ...
        parts = line.split()
        if len(parts) < 5:  # must have at least one word
            continue
        basename = parts[0]
        annotator = parts[1]
        start = float(parts[2])
        end = float(parts[3])
        words = parts[4:]
        
        # Convert times to centiseconds
        start_cs = int(round(start * 100))
        end_cs = int(round(end * 100))
        
        # Construct utterance ID in MGB2 style:
        # e.g., comedy_75_first_12min_Ali_seg-0000000:0008190
        seg_id = f"{basename}_{annotator}_seg-{start_cs:07d}:{end_cs:07d}"
        
        # Set speaker ID equal to the utterance ID (per Kaldi recommendation)
        spk_id = seg_id
        
        # Unescape and join transcription
        words_unescaped = [unescape(w) for w in words]
        text_str = " ".join(words_unescaped).strip()
        # (If text_str is empty, the line would have been skipped in the shell script.)
        
        # Write to files:
        # segments: <utterance-id> <recording-id> <start> <end>
        seg_f.write(f"{seg_id} {basename} {start:.2f} {end:.2f}\n")
        # text: <utterance-id> <transcription>
        txt_f.write(f"{seg_id} {text_str}\n")
        # utt2spk: <utterance-id> <utterance-id>
        utt_f.write(f"{seg_id} {spk_id}\n")
