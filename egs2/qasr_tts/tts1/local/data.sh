#!/bin/bash

set -e
set -u
set -o pipefail

log() {
    local fname=${BASH_SOURCE[1]##*/}
    echo -e "$(date '+%Y-%m-%dT%H:%M:%S') (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $*"
}
SECONDS=0
mer=80
stage=-1
stop_stage=2

log "$0 $*"
. utils/parse_options.sh

if [ $# -ne 0 ]; then
    log "Error: No positional arguments are required."
    exit 2
fi

. ./path.sh || exit 1;
. ./cmd.sh || exit 1;
. ./db.sh || exit 1;

if [ -z "${QASR_TTS}" ]; then
   log "Fill the value of 'QASR_TTS' of db.sh"
   exit 1
fi
db_dir=${QASR_TTS}
qasr_xmldir=$db_dir/release/train_20210109/xml
train_set=tr_no_dev
train_dev=dev
eval_set=eval1
train_dir=train

# if [ ${stage} -le -1 ] && [ ${stop_stage} -ge -1 ]; then
#     log "stage -1: Data Download"
#     bash -x local/data_download.sh "${db_root}"
# fi


if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    for x in $train_dir $train_set $train_dev $eval_set; do
        mkdir -p data/$x
        if [ -f ${x}/wav.scp ]; then
            mkdir -p ${x}/.backup
            mv $x/{wav.scp,utt2spk,spk2utt,segments,text} ${x}/.backup
        fi
    done
    log "stage 0: Data Preparation"
    # set filenames
    scp=data/train/wav.scp
    utt2spk=data/train/utt2spk
    spk2utt=data/train/spk2utt
    text=data/train/text

    # check file existence
    [ ! -e data/train ] && mkdir -p data/train
    [ -e ${scp} ] && rm ${scp}
    [ -e ${utt2spk} ] && rm ${utt2spk}
    [ -e ${spk2utt} ] && rm ${spk2utt}
    [ -e ${text} ] && rm ${text}

    # make scp, utt2spk, and spk2utt
    # find ${db_root}/qasr_tts-1.0/wavs -follow -name "*.wav" | sort | while read -r filename;do
    #     id=$(basename ${filename} | sed -e "s/\.[^\.]*$//g")
    #     echo "${id} ${filename}" >> ${scp}
    #     echo "${id} qsr" >> ${utt2spk}
    # done
    find $db_dir/wav -type f -name "*.wav" | \
        awk -F/ '{print $NF}' | perl -pe 's/\.wav//g' > \
        data/$train_dir/wav_list
    
    for x in $(cat $train_dir/wav_list); do
        echo $x $db_dir/train/wav/$x.wav >> $train_dir/wav.scp
    done

    echo "using python to process xml file"
    # check if bs4 and lxml are installin in python
    local/check_tools.sh
    # process xml file using python
    cat data/$train_dir/wav_list | while read basename; do
        [ ! -e $qasr_xmldir/$basename.xml ] && echo "Missing $qasr_xmldir/$basename.xml" && exit 1
        local/process_xml.py $qasr_xmldir/$basename.xml - | local/add_to_datadir.py $basename data/$train_dir $mer
    done

    awk '{print $1" "$1" A"}' data/$train_dir/wav.scp > data/$train_dir/reco2file_and_channel

    if [ ! -f data/$train_dir/spk2utt ]; then
        utils/utt2spk_to_spk2utt.pl data/$train_dir/utt2spk > data/$train_dir/spk2utt
    fi


    # make text usign the original text
    # cleaning and phoneme conversion are performed on-the-fly during the training
    # paste -d " " \
    #     <(cut -d "|" -f 1 < ${db_root}/qasr_tts-1.0/metadata.csv) \
    #     <(cut -d "|" -f 2 < ${db_root}/qasr_tts-1.0/metadata.csv) \
    #     > ${text}

    utils/validate_data_dir.sh --no-feats data/train
fi

if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    log "stage 2: utils/subset_data_dir.sg"
    # make evaluation and devlopment sets
    utils/subset_data_dir.sh --last data/train 50 data/deveval
    utils/subset_data_dir.sh --last data/deveval 25 data/${eval_set}
    utils/subset_data_dir.sh --first data/deveval 25 data/${train_dev}
    n=$(( $(wc -l < data/train/wav.scp) - 50 ))
    utils/subset_data_dir.sh --first data/train ${n} data/${train_set}
fi

log "Successfully finished. [elapsed=${SECONDS}s]"
