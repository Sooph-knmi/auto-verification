#!/bin/bash
#SBATCH --output=logs/mxalign.out #multi-domain-32bs-lr5e-6.out
#SBATCH --error=logs/mxalign.err #multi-domain-32bs-lr5e-6.err
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH --account=DestE_340_26
#SBATCH --cpus-per-task=8
#SBATCH --gpus-per-node=4
#SBATCH --mem=0 # ALLOCATE FULL RAM
#SBATCH --partition=boost_usr_prod
#SBATCH --qos=normal
#SBATCH --switches=1
#SBATCH --exclude=lrdn[0153,1902,2051,0189,0163,1781,0388,0399,0407,1308,1309,1953,1984,2151,2094,2792,2371,1748]
#SBATCH --time=04:00:00
#SBATCH --job-name=mxalign
#SBATCH --exclusive

########## ARRAY JOB ##########
#SBATCH --array=0-72               # 73 graph configs

########## OPTIONAL ##########
#SBATCH --exclusive
#SBATCH --switches=1

########################################
#        SET PATHS
########################################
INFERENCE_DIR=/leonardo_work/DestE_340_26/users/sbuurman/auto-verification/output/hectometric_tp
DATASET_BASE_FOLDER=/leonardo_work/DestE_340_26/users/mvangind/hecto_decumulation/hecto_decumulated # Base folder for all datasets, will be injected into config
TMP_CONFIG_DIR=/leonardo_work/DestE_340_26/users/sbuurman/auto-verification/mxalign_config # Base folder for temporary configs, will be injected into config
BASE_CONFIG=/leonardo_work/DestE_340_26/users/sbuurman/auto-verification/mxalign_config/Hecto_obs.yaml # Base config to copy from, should have placeholders null for dataset paths
OUTPUT_PATH=/leonardo_work/DestE_340_26/users/sbuurman/auto-verification/output/mxalign_tp # Base output path for output graphs, will be injected into config

# REPLACE WITH YOUR OWN VIRTUAL ENVIRONMENT, CONTAINING ANEMOI-CORE FROM https://github.com/destination-earth-digital-twins/anemoi-core/tree/feature/hectometric
VENV=/leonardo_work/DestE_340_26/users/sbuurman/verification/mxalign/.mxalign/ #.venv
########################################
#        ENVIRONMENT SETUP
########################################

module load gcc/12.2.0

export PYTHON_HOME=/leonardo_work/DestE_330_25/users/asalihi0/compiled-libraries/python/python-3.11.7-gcc-12.2.0-cmake-3.27.9
export SQLITE3_HOME=/leonardo_work/DestE_330_25/users/asalihi0/compiled-libraries/python/sqlite-3.45-gcc-12.2.0

export PATH=$PYTHON_HOME/bin:$SQLITE3_HOME/bin:$PATH
export LD_LIBRARY_PATH=$PYTHON_HOME/lib:$SQLITE3_HOME/lib:$LD_LIBRARY_PATH


source $VENV/bin/activate
export VIRTUAL_ENV=$VENV
export PYTHONUSERBASE=$VIRTUAL_ENV
export PATH=$PATH:$VIRTUAL_ENV/bin

IDX=${SLURM_ARRAY_TASK_ID}
echo IDX: $IDX
FOLDER_NAME=$(ls -1 "$INFERENCE_DIR" | sed -n "$((IDX+1))p")
# Take the (IDX+1)-th line from the folder
echo FOLDER_NAME: $FOLDER_NAME
START_DATE_RAW=$(echo $FOLDER_NAME | cut -d'_' -f2)
END_DATE_RAW=$(echo $FOLDER_NAME | cut -d'_' -f3)

if [[ $FOLDER_NAME == *"v2.zarr" ]]; then
    ITEM=$(ls -1 /leonardo_work/DestE_330_25/anemoi/datasets/DEODE/${DATASET_NAME} | head -n 1)
    DATASET_NAME=$ITEM
fi

# Extract start and end dates from dataset name (format: de330_start_end...)

START_YEAR=${START_DATE_RAW:0:4}
START_MONTH=${START_DATE_RAW:4:2}
START_DAY=${START_DATE_RAW:6:2}
START_HOUR=${START_DATE_RAW:8:2}
START_DATE="${START_YEAR}-${START_MONTH}-${START_DAY}T${START_HOUR}:00:00"
#%Y-%m-%dT%H:%M:%S
FILE_NAME=pred_${START_YEAR}${START_MONTH}${START_DAY}T06Z.nc
echo FILE_NAME: $FILE_NAME
END_YEAR=${END_DATE_RAW:0:4}
END_MONTH=${END_DATE_RAW:4:2}
END_DAY=${END_DATE_RAW:6:2}
END_HOUR=${END_DATE_RAW:8:2}
END_DATE="${END_YEAR}-${END_MONTH}-${END_DAY}T${END_HOUR}:00:00"

# Extract name key by removing .zarr suffix


########################################
#     LOG START + HARDWARE INFO
########################################

echo "------------------------------------------------------------"
echo "Task $SLURM_ARRAY_TASK_ID starting"
echo "Node:        $(hostname)"
echo "GPU:         $CUDA_VISIBLE_DEVICES"
echo "Start time:  $(date)"
echo "Graph path:  $GRAPH_PATH"
echo "------------------------------------------------------------"

########################################
#        RUN PYTHON WITH INJECTED PATH
########################################

# Inject path from paths.txt into config.yaml WITHOUT modifying the file
TMP_CONFIG=$(mktemp --tmpdir=$TMP_CONFIG_DIR config_XXXX.yaml)
echo $TMP_CONFIG
# DATA_DIR=${DATASET_BASE_FOLDER}/${DATASET_NAME}
# echo DATA_DIR: $DATA_DIR
# FULL_DATA_PATH=$DATA_DIR
FULL_DATA_PATH=${INFERENCE_DIR}/${FOLDER_NAME}/${FILE_NAME}
echo $FULL_DATA_PATH
echo START_DATE: $START_DATE
echo END_DATE: $END_DATE
echo OUTPUT_PATH: $OUTPUT_PATH
echo BASE_CONFIG: $BASE_CONFIG
sed -e "s|files: null|files: ${FULL_DATA_PATH}|" \
    -e "s|start: null|start: ${START_DATE}|" \
    -e "s|end: null|end: ${START_YEAR}-${START_MONTH}-${START_DAY}T06:00:00|" \
    -e "s|start_date: null|start_date: ${START_DATE}|" \
    -e "s|end_date: null|end_date: ${END_DATE}|" \
    -e "s|path: null|path: ${OUTPUT_PATH}/${FOLDER_NAME}.nc|" $BASE_CONFIG > $TMP_CONFIG 
echo "Generated temporary config at $TMP_CONFIG"
source $VENV/bin/activate
# mxalign slurm --queue boost_usr_prod --account DestE_340_26 --cores 4 --memory 500GB $TMP_CONFIG

mxalign slurm --queue lrd_all_serial --account DestE_340_26 --cores 4 --memory 10GB $TMP_CONFIG 





########################################
#              FINISHED
########################################

echo "------------------------------------------------------------"
echo "Task $SLURM_ARRAY_TASK_ID finished"
trap "rm -f $TMP_CONFIG" EXIT
echo "End time: $(date)"
echo "------------------------------------------------------------"
