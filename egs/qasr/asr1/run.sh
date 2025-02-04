#!/usr/bin/env bash
# E2E_qasr
# Copyright (C) 2020 ETS JHU  (AKRAM KHELFI)







. ./path.sh || exit 1;
. ./cmd.sh || exit 1;

# general configuration
backend=pytorch
stage=1   # start from -1 if you need to start from data download
stop_stage=100
ngpu=1         # number of gpus ("0" uses cpu, otherwise use gpu)
debugmode=1
dumpdir=dump   # directory to dump full features
N=0            # number of minibatches to be used (mainly for debugging). "0" uses all minibatches.
verbose=0      # verbose option
resume=      # Resume the training from snapshot
subset=1100  # in case we want to use subset of training data
# feature configuration
do_delta=false

#FILTER OUT SEGMENTS BASED ON MER (Match Error Rate)
mer=80

# rnnlm related
lm_resume=        # specify a snapshot file to resume LM training
lmtag= 

nj=200
process_xml="python"

datadir="/export/fs06/corpora8/QASR/qasr-speech-corpus-v1.0-release/mgb2.1/"

n_average=5                  # the number of ASR models to be averaged
use_valbest_average=true     # if true, the validation `n_average`-best ASR models will be averaged.
                             # if false, the last `n_average` ASR models will be averaged.
lm_n_average=0               # the number of languge models to be averaged
use_lm_valbest_average=false # if true, the validation `lm_n_average`-best language models will be averaged.
                             # if false, the last `lm_n_average` language models will be averaged.



# rnnlm related
lm_resume= # specify a snapshot file to resume LM training
lmtag=     # tag for managing LMs

# decoding parameter
recog_model=model.acc.best  # set a model to be used for decoding: 'model.acc.best' or 'model.loss.best'
lang_model=rnnlm.model.best # set a language model to be used for decoding

# bpemode (unigram or bpe)
nbpe=5000
bpemode=unigram

# exp tag
tag="" # tag for managing experiments.

# configuration files during training
preprocess_config=conf/specaug.yaml
train_config=conf/train.yaml # current default recipe requires 4 gpus.
                             # if you do not have 4 gpus, please reconfigure the `batch-bins` and `accum-grad` parameters in config.
lm_config=conf/lm_transformer.yaml
decode_config=conf/decode.yaml


. utils/parse_options.sh || exit 1;

# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
set -e
set -u
set -o pipefail


train_set=train_trim_sp
train_dev=dev_trim
recog_set="dev test"
train=train


if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    ### Task dependent. You have to make data the following preparation part by yourself.
    ### But you can utilize Kaldi recipes in most cases
    ### This data preparation for qasr dataset
    echo "stage 0: Data preparation"
    local/qasr_data_prep.sh ${datadir} ${process_xml} ${subset} ${mer}
fi
