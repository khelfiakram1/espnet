#!/usr/bin/env bash

# Copyright (C) 2020 Kanari AI
# Copyright (C) 2025 JHU-ETS
# (Amir Hussein)
# (Mohammed Akram Khelfi)

if [ $# -ne 4 ]; then
  echo "Usage: $0 <DB-dir> <process-xml> <data-subset> <mer>"
  exit 1;
fi


db_dir=$1
process_xml=$2
subset=$3  # subset of training data
mer=$4
test_dir=data/test
train_dir=data/train
dev_dir=data/dev

for x in $train_dir $dev_dir $test_dir; do
  mkdir -p $x
  if [ -f ${x}/wav.scp ]; then
    mkdir -p ${x}/.backup
    mv $x/{wav.scp,utt2spk,spk2utt,segments,text} ${x}/.backup
  fi
done