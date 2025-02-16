#!/usr/bin/env bash
# E2E_qasr
# Copyright (C) 2020 ETS JHU  (AKRAM KHELFI)


. ./path.sh || exit 1;
. ./cmd.sh || exit 1;

# general configuration
backend=pytorch
stage=1   # start from -1 if you need to start from data download
stop_stage=100
ngpu=4        # number of gpus ("0" uses cpu, otherwise use gpu)
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

nj=20
process_xml="python"

datadir="/export/fs06/corpora8/QASR/qasr-speech-corpus-v1.0-release/mgb2.1/"
mgb2dir="/export/fs05/mkhelfi1/MGB-2/MGB-2/"
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
    local/qasr_data_prep.sh ${datadir} ${mgb2dir} ${process_xml} ${subset} ${mer}
fi

feat_tr_dir=${dumpdir}/${train_set}/delta${do_delta}; mkdir -p ${feat_tr_dir}
feat_dt_dir=${dumpdir}/${train_dev}/delta${do_delta}; mkdir -p ${feat_dt_dir}

if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    ### Task dependent. You have to design training and dev sets by yourself.
    ### But you can utilize Kaldi recipes in most cases
    echo "stage 1: Feature Generation"
    fbankdir=fbank
    # Generate the fbank features; by default 80-dimensional fbanks with pitch on each frame
    
    for x in test dev ${train}; do
        steps/make_fbank_pitch.sh --cmd "$train_cmd" --nj $nj --write_utt2num_frames true \
            data/${x} exp/make_fbank/${x} ${fbankdir}
        utils/fix_data_dir.sh data/${x}
    done

    # # remove_longshortdata.sh --maxframes x --maxchars y data/train data/${train_trim}
    # # remove utt having more than 3000 frames
    # # remove utt having more than 400 characters
    remove_longshortdata.sh --maxframes 3000 --maxchars 400 data/${train} data/train_trim
    remove_longshortdata.sh --maxframes 3000 --maxchars 400 data/dev data/${train_dev}

    utils/data/get_reco2dur.sh data/train_trim
    utils/data/get_reco2dur.sh data/dev_trim
    # speed perturbation
    utils/perturb_data_dir_speed.sh 0.9 data/train_trim data/temp1
    utils/perturb_data_dir_speed.sh 1.0 data/train_trim data/temp2
    utils/perturb_data_dir_speed.sh 1.1 data/train_trim data/temp3
    utils/combine_data.sh --extra-files utt2uniq data/${train_set} data/temp1 data/temp2 data/temp3
    rm -r data/temp1 data/temp2 data/temp3
    steps/make_fbank_pitch.sh --cmd "$train_cmd" --nj $nj --write_utt2num_frames true \
        data/${train_set} exp/make_fbank/${train_set} ${fbankdir}
    utils/fix_data_dir.sh data/${train_set}

    # compute global CMVN cepstral mean and variance normalization
    compute-cmvn-stats scp:data/${train_set}/feats.scp data/${train_set}/cmvn.ark

    # dump features for training
    dump.sh --cmd "$train_cmd" --nj $nj --do_delta ${do_delta} \
        data/${train_set}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/train ${feat_tr_dir}
    dump.sh --cmd "$train_cmd" --nj $nj --do_delta ${do_delta} \
        data/${train_dev}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/dev ${feat_dt_dir}
    for rtask in ${recog_set}; do
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}; mkdir -p ${feat_recog_dir}
        dump.sh --cmd "$train_cmd" --nj $nj --do_delta ${do_delta} \
            data/${rtask}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/recog/${rtask} \
            ${feat_recog_dir}
    done
fi


dict=data/lang_char/${train_set}_${bpemode}${nbpe}_units.txt
bpemodel=data/lang_char/${train_set}_${bpemode}${nbpe}

if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
    ### Task dependent. You have to check non-linguistic symbols used in the corpus.
    echo "stage 2: Dictionary and Json Data Preparation"
    mkdir -p data/lang_char/
    echo "<unk> 1" > ${dict} # <unk> must be 1, 0 will be used for "blank" in CTC
    cut -f 2- -d" " data/train/text > data/lang_char/input.txt

    # --model_type: model type. Choose from unigram (default), bpe, char, or word. The input sentence must be pretokenized when using word type.

    spm_train --input=data/lang_char/input.txt --vocab_size=${nbpe} --model_type=${bpemode} \
        --model_prefix=${bpemodel%%.*} --input_sentence_size=100000000
    spm_encode --model=${bpemodel}.model --output_format=piece < data/lang_char/input.txt | \
        tr ' ' '\n' | sort | uniq | awk '{print $0 " " NR+1}' >> ${dict}
    wc -l ${dict}

    # make json labels
    data2json.sh --feat ${feat_tr_dir}/feats.scp --bpecode ${bpemodel}.model \
         data/${train_set} ${dict} > ${feat_tr_dir}/data_${bpemode}${nbpe}.json
    data2json.sh --feat ${feat_dt_dir}/feats.scp --bpecode ${bpemodel}.model \
         data/${train_dev} ${dict} > ${feat_dt_dir}/data_${bpemode}${nbpe}.json
    for rtask in ${recog_set}; do
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}
        data2json.sh --feat ${feat_recog_dir}/feats.scp --bpecode ${bpemodel}.model \
            data/${rtask} ${dict} > ${feat_recog_dir}/data_${bpemode}${nbpe}.json
    done
fi
