#!/usr/bin/env bash

DBc=$1

if [[ ! -e "$DBc/train.tar.gz" || ! -e "$DBc/dev.tar.gz" ]]; then
  echo "You need to download the MGB-2 first and copy dev.tar.gz and train.tar.gz to DB directory"
  echo "check: https://arabicspeech.org/mgb2"
  exit 1
fi

(cd $DBc; rm -fr train dev test; for x in *; do tar -xvf $x; done)
