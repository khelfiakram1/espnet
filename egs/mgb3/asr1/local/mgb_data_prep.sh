#!/usr/bin/env bash
set -e -o pipefail

# ----------------------------------------------------------------------
# 1) Check command-line argument and define directories
# ----------------------------------------------------------------------
if [ $# -ne 1 ]; then
  echo "Usage: $0 <MGB3-db-dir>"
  echo "  e.g.: $0 /path/to/MGB3"
  exit 1
fi

db_dir=$1    # e.g., /path/to/MGB3
train_dir=data/train
dev_dir=data/dev
test_dir=data/test

# List of annotator folder names
annotators=("Ali" "Alaa" "Mohamed" "Omar")

# Backup or clear old data directories (for train, dev, and test)
for x in "$train_dir" "$dev_dir" "$test_dir"; do
  mkdir -p "$x"
  if [ -f "$x/wav.scp" ]; then
    echo "Backing up old data in $x/.backup"
    mkdir -p "$x/.backup"
    mv "$x"/{wav.scp,segments,text,utt2spk,spk2utt,reco2file_and_channel} "$x/.backup/" 2>/dev/null || true
  fi
done

# ----------------------------------------------------------------------
# 2) Set path to the Python helper
# ----------------------------------------------------------------------
py_helper="local/add_to_datadir.py"
if [ ! -f "$py_helper" ]; then
  echo "Error: Python helper script not found at $py_helper"
  exit 1
fi

# ----------------------------------------------------------------------
# 3) Function to prepare a data split (train, dev, test)
# ----------------------------------------------------------------------
prepare_data() {
  data_split=$1   # "train", "dev", or "test"
  out_dir=$2      # e.g., data/train

  echo "==> Preparing $data_split -> $out_dir"
  mkdir -p "$out_dir"
  # Initialize output files
  > "$out_dir/segments"
  > "$out_dir/text"
  > "$out_dir/utt2spk"

  # Process each annotator
  for ann in "${annotators[@]}"; do
    seg_file="$db_dir/$data_split/$ann/segments"
    txt_file="$db_dir/$data_split/$ann/text_noverlap.bw"
    echo "Processing files for annotator $ann:"
    echo "  Segments: $seg_file"
    echo "  Text:     $txt_file"
    if [ ! -f "$seg_file" ] || [ ! -f "$txt_file" ]; then
      echo "Warning: missing segments or text for $ann in $data_split"
      continue
    fi

    # Create temporary files for joining based on the original utterance ID
    seg_temp=$(mktemp)
    txt_temp=$(mktemp)
    final_temp=$(mktemp)

    # The segments file is expected to have:
    #    <old_utt_id> <basename> <start> <end>
    awk '{print $1, $2, $3, $4}' "$seg_file" > "$seg_temp"
    # The text file is expected to have:
    #    <old_utt_id> <word1> <word2> ...
    cp "$txt_file" "$txt_temp"

    # Left join the two files on the first field (old_utt_id)
    # Using -a 1 ensures we keep all segments; missing text fields become empty.
    join -a 1 -e "" -o auto -1 1 -2 1 <(sort -k1,1 "$seg_temp") <(sort -k1,1 "$txt_temp") > "$final_temp" || true

    # Process joined lines to produce:
    #    <basename> <annotator> <start> <end> <words...>
    to_python=$(mktemp)
    while read -r line; do
      # Split line into array
      arr=($line)
      # arr[0]: old_utt_id, arr[1]: basename, arr[2]: start, arr[3]: end.
      # If there is no transcript, array length will be 4.
      if [ ${#arr[@]} -le 4 ]; then
        # Skip lines with no matching text
        continue
      fi
      basename="${arr[1]}"
      start="${arr[2]}"
      end="${arr[3]}"
      words=""
      for ((i=4; i<${#arr[@]}; i++)); do
        words="$words ${arr[$i]}"
      done
      # Write line for Python helper: "<basename> <annotator> <start> <end> <words...>"
      echo "$basename $ann $start $end$words" >> "$to_python"
    done < "$final_temp"

    # Pass the processed lines to the Python helper
    cat "$to_python" | "$py_helper" "$out_dir"

    rm -f "$seg_temp" "$txt_temp" "$final_temp" "$to_python"
  done

  # Create wav.scp from unique recording IDs (the second field in segments)
  awk '{print $2}' "$out_dir/segments" | sort -u > "$out_dir/recording_ids"
  > "$out_dir/wav.scp"
  while read -r recid; do
    wav_path="$db_dir/wav/${recid}.wav"
    if [ -f "$wav_path" ]; then
      echo "$recid $wav_path" >> "$out_dir/wav.scp"
    else
      echo "Warning: WAV not found for $recid ($wav_path)."
    fi
  done < "$out_dir/recording_ids"

  # Generate spk2utt from utt2spk
  utils/utt2spk_to_spk2utt.pl "$out_dir/utt2spk" > "$out_dir/spk2utt"

  # Create reco2file_and_channel (assumes single channel "A")
  awk '{print $1" "$1" A"}' "$out_dir/wav.scp" > "$out_dir/reco2file_and_channel"

  # Fix and validate the data directory
  utils/fix_data_dir.sh "$out_dir"
  utils/validate_data_dir.sh --no-feats "$out_dir" || true

  echo "Finished preparing $data_split -> $out_dir"
}

# ----------------------------------------------------------------------
# 4) Run the preparation for train, dev, and test splits
# ----------------------------------------------------------------------
prepare_data adapt "$train_dir"
prepare_data dev   "$dev_dir"
prepare_data test  "$test_dir"

echo "Data preparation completed (each annotator's transcript is a separate utterance, with speaker IDs set equal to utterance IDs)."
