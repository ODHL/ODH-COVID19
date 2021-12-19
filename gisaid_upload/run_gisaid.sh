#!/bin/bash

##INFO
# Initialize
# - copies config file to the output dir

# run
# - creates /output/dir/GISAID_Complete/
# - creates /output/dir/GISAID_Complete/timestamp/
# - copies /output/dir/config.yaml to /output/dir/GISAID_Complete/timestamp/
# - copies /pipeline/scripts/gisaid.sh to /output/dir/GISAID_Complete/timestamp/

#cd /Users/sevillas2/Desktop/APHL/ODH-COVID19/; sh run_gisaid.sh -p run -o /Users/sevillas2/Desktop/APHL/demo/OH-123

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
check_initialization(){
  if [[ ! -d $output_dir ]] || [[ ! -f "${output_dir}/gisaid_config.yaml" ]]; then 
    echo "ERROR: You must initalize the dir before beginning pipeline"
    exit 1
  fi
}


#########################################################  
# Format Directories
#########################################################
#add backslash if spaces are in directory
#output_dir=$(echo $output_dir | awk ' { gsub(" ","\\ "); print $0 }')

#remove trailing / on directories
output_dir=$(echo $output_dir | sed 's:/*$::')

#########################################################  
# Set variables
#########################################################
log_time=`date +"%Y%m%d_%H%M"`
upload_time=`date +"%Y%m%d"`

#set dir
complete_dir="$output_dir/GISAID_Complete"
run_dir="$complete_dir/$log_time"

#########################################################  
# Create dirs
#########################################################
if [[ ! -d $complete_dir ]]; then mkdir -p "${complete_dir}" ; fi
if [[ ! -d $run_dir ]]; then mkdir -p "${run_dir}"; fi

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
	if [[ ! -f "${output_dir}/${strarr[1]}" ]]; then \
		cp $f "${output_dir}/${strarr[1]}"
	else
		echo "-Config already in output dir"
	fi
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

	#copy config inputs with time_stamp
	files_save=("scripts/gisaid.sh")

	for f in ${files_save[@]}; do
		IFS='/' read -r -a strarr <<< "$f"
		cp $f "${run_dir}/${strarr[${#strarr[@]}-1]}"
	done

	cp "${output_dir}"/gisaid_config.yaml "${run_dir}"/gisaid_config.yaml 

	#required file name schema: YYYYMMDD_a_descriptive_name_metadata.xls
	IFS='/' read -r -a strarr <<< ""${output_dir}""
	project_name="${strarr[${#strarr[@]}-1]}"
	cp "config/20210222_Template.xls" "${run_dir}"/${upload_time}_${project_name}_metadata.xls

	#run script
	sh ${run_dir}/gisaid.sh $run_dir

	echo "*********Completed pipeline*********"
	echo
fi
