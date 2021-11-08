#!/bin/bash

#########################################################
# Arguments
#########################################################

helpFunction()
{
   echo ""
   echo "Usage: $0 -p pipeline options"
   echo -e "\t-p options: initialize, run, rerun"
   echo "Usage: $1 -o output_dir"
   echo -e "\t-o path to output directory"
   exit 1 # Exit script after printing help
}

while getopts "p:o:" opt
do
   case "$opt" in
      p ) pipeline="$OPTARG" ;;
      o ) output_dir="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$pipeline" ] || [ -z "$output_dir" ]; then
   echo "Some or all of the parameters are empty";
   helpFunction
fi

#########################################################
# functions
#########################################################

#handle yaml file
parse_yaml() {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

check_initialization(){
  if [[ ! -d $output_dir ]] || [[ ! -f "${output_dir}/gisaid_config.yaml" ]]; then 
    echo "ERROR: You must initalize the dir before beginning pipeline"
    exit 1
  fi
}

#########################################################  
# Formatting
#########################################################
log_time=`date +"%Y%m%d_%H%M"`

#remove trailing / on directories
output_dir=$(echo $output_dir | sed 's:/*$::')

#########################################################
# parse yaml
#########################################################
eval $(parse_yaml config/gisaid_config.yaml "config_")
percent_n="50"

#########################################################
# Code
#########################################################

####################### INITIALIZE #######################
if [[ $pipeline = "initialize" ]]; then
  echo
  echo "*********Initializing pipeline*********"
  
  # copy config inputs to edit if doesn't exit
  files_save=('config/gisaid_config.yaml')

  for f in ${files_save[@]}; do
    IFS='/' read -r -a strarr <<< "$f"
    if [[ ! -f "${output_dir}/${strarr[1]}" ]]; then cp $f "${output_dir}/${strarr[1]}"; fi
  done
  
  #output complete
  echo "-Config is ready to be edited:\n--${output_dir}/gisaid_config.yaml"
  echo

####################### RUN #######################
#Run check of pipeline OR run pipeline locally/cluster
elif [[ $pipeline = "run" ]]; then
  echo
  echo "*********Running pipeline*********"

  ####################### Preparation
  #run output, config check
  check_initialization
  
  #set dir
  run_dir="$output_dir/$log_time"
  merged_dir="$run_dir/merged_upload"
  failed_dir="$run_dir/failed_qc"

   rm -r /Users/sevillas2/Desktop/APHL/test_data/OH-123/202111*

  #create subdirectory structure
  if [[ ! -d "${run_dir}" ]]; then mkdir "${run_dir}"; fi
  if [[ ! -d "${merged_dir}" ]]; then mkdir "${merged_dir}"; fi
  if [[ ! -d "${failed_dir}" ]]; then mkdir "${failed_dir}"; fi

  # copy config inputs with time_stamp
  files_save=("${output_dir}/gisaid_config.yaml" "scripts/gisaid.sh")

  for f in ${files_save[@]}; do
    IFS='/' read -r -a strarr <<< "$f"
    cp $f "${run_dir}/${strarr[${#strarr[@]}-1]}"
  done

  #parse config
  eval $(parse_yaml ${output_dir}/gisaid_config.yaml "config_")

  #run script
  sh ${run_dir}/gisaid.sh \
  $output_dir \
  $run_dir \
  ${config_metadata_file} \
  ${config_percent_n}

fi
