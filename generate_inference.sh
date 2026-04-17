#!/bin/bash
#SBATCH --output=logs/output.out #multi-domain-32bs-lr5e-6.out
#SBATCH --error=logs/output.err #multi-domain-32bs-lr5e-6.err
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
#SBATCH --time=24:00:00
#SBATCH --job-name=inference
#SBATCH --exclusive


########## ARRAY JOB ##########
# SBATCH --array=0-73               # 73 graph configs

########## OPTIONAL ##########
#SBATCH --exclusive
#SBATCH --switches=1

########################################
#        SET PATHS
########################################
DATASETS_TXT=/leonardo_work/DestE_340_26/users/sbuurman/multi-domain-training/anemoi-core/test_hectometric/hectometric_validation.txt #INSERT .txt files with all dataset paths
DATASET_BASE_FOLDER=/leonardo_work/DestE_340_26/users/mvangind/hecto_decumulation/hecto_decumulated/ # Base folder for all datasets, will be injected into config
TMP_CONFIG_DIR=/leonardo_work/DestE_340_26/users/sbuurman/auto-verification/config # Base folder for temporary configs, will be injected into config
BASE_CONFIG=/leonardo_work/DestE_340_26/users/sbuurman/auto-verification/config/multi_domain_inference_Hecto.yaml # Base config to copy from, should have placeholders null for dataset paths
OUTPUT_PATH=/leonardo_work/DestE_340_26/users/sbuurman/auto-verification/output/hectometric_final/ # Base output path for output graphs, will be injected into config

# REPLACE WITH YOUR OWN VIRTUAL ENVIRONMENT, CONTAINING ANEMOI-CORE FROM https://github.com/destination-earth-digital-twins/anemoi-core/tree/feature/hectometric
VENV=/leonardo_work/DestE_340_26/users/sbuurman/multi-domain-training/temp-torch-2.6.0-cu124/ #.venv
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

# Set up cleanup trap
trap "rm -f $TMP_CONFIG 2>/dev/null" EXIT

IDX=$1
if [ -z "$IDX" ]; then
    echo "Error: Job index not provided as argument"
    exit 1
fi
# Take the (IDX+1)-th line from paths.txt — this is JUST the path, not a tuple
DATASET_NAME=$(sed -n "$((IDX+1))p" ${DATASETS_TXT})
START_DATE_RAW=$(echo $DATASET_NAME | cut -d'_' -f2)
END_DATE_RAW=$(echo $DATASET_NAME | cut -d'_' -f3)
# Extract graph name key by removing .zarr suffix
GRAPH_LABEL=${DATASET_NAME%.zarr}

if [[ $DATASET_NAME == *"v2.zarr" ]]; then
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
END_DATE="${START_YEAR}-${START_MONTH}-${START_DAY}T06:00:00"
# END_YEAR=${END_DATE_RAW:0:4}
# END_MONTH=${END_DATE_RAW:4:2}
# END_DAY=${END_DATE_RAW:6:2}
# END_HOUR=${END_DATE_RAW:8:2}
# END_DATE="${END_YEAR}-${END_MONTH}-${END_DAY}T${END_HOUR}:00:00"


########################################
#     LOG START + HARDWARE INFO
########################################

echo "------------------------------------------------------------"
echo "Task $IDX starting"
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
DATA_DIR=${DATASET_BASE_FOLDER}/${DATASET_NAME}
echo DATA_DIR: $DATA_DIR
FULL_DATA_PATH=$DATA_DIR

echo $DATA_DIR
echo $ITEM
echo $FULL_DATA_PATH
echo START_DATE: $START_DATE
echo END_DATE: $END_DATE
echo GRAPH_LABEL: $GRAPH_LABEL
echo OUTPUT_PATH: $OUTPUT_PATH
echo BASE_CONFIG: $BASE_CONFIG
echo BASE_PATH: $BASE_PATH
sed -e "s|dataset: null|dataset: ${FULL_DATA_PATH}|" \
    -e "s|graph_label: null|graph_label: ${GRAPH_LABEL}|" \
    -e "s|start_date: null|start_date: ${START_DATE}|" \
    -e "s|end_date: null|end_date: ${END_DATE}|" \
    -e "s|output: null|output: ${OUTPUT_PATH}/${GRAPH_LABEL}.zarr|" $BASE_CONFIG > $TMP_CONFIG 
echo "Generated temporary config at $TMP_CONFIG"
source $VENV/bin/activate
srun bris --config=$TMP_CONFIG




########################################
#              FINISHED
########################################

echo "------------------------------------------------------------"
echo "Task $IDX finished"
trap "rm -f $TMP_CONFIG" EXIT
echo "End time: $(date)"
echo "------------------------------------------------------------"

# Submit next job with dependency
if [ $IDX -lt 72 ]; then
    NEXT_IDX=$(($IDX+1))
    echo "Submitting next job with index $NEXT_IDX"
    sbatch --dependency=afterok:$SLURM_JOB_ID generate_inference.sh $NEXT_IDX
fi
