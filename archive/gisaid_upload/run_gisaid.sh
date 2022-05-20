#!/bin/bash

##INFO
# Initialize
# - copies config file to the output dir

# batch
# - creates /output/dir/GISAID_logs/
# - creates /output/dir/GISAID_logs/timestamp/
# - creates /output/dir/fastas_GISAID_uploaded
# - creates /output/dir/fastas_GISAID_errors
# - copies /output/dir/config.yaml to /output/dir/GISAID_logs/timestamp/
# - copies /pipeline/scripts/gisaid.sh to /output/dir/GISAID_logs/timestamp/

# error
# - copies files from column1 of /output/dir/fastas_GISAID_errors/error_log.txt:
# /output/dir/fastas_GISAID_uploaded to /output/dir/fastas_GISAID_errors

#cd /Users/sevillas2/Desktop/APHL/ODH-COVID19/; sh run_gisaid.sh -p run -o /Users/sevillas2/Desktop/APHL/demo/OH-123
#cd "/l/Micro/Gen Micro/Whole Genome Sequencing/Coronavirus_WGS/COVID-19 Fastas/Sam/ODH-COVID19-main/gisaid_upload"; \
#sh run_gisaid.sh -p run -o "/l/Micro/Gen Micro/Whole Genome Sequencing/Coronavirus_WGS/COVID-19 Fastas/"

#########################################################
# Arguments
#########################################################

helpFunction()
{
   echo ""
   echo "Usage: $0 -p pipeline options"
   echo -e "\t-p options: initialize, batch, error"
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
#remove trailing / on directories
output_dir=$(echo $output_dir | sed 's:/*$::')

#########################################################  
# Set variables
#########################################################
log_time=`date +"%Y%m%d_%H%M"`
upload_time=`date +"%Y%m%d"`

#set dir
parent_log_dir="$output_dir/GISAID_logs"
run_dir="$parent_log_dir/$log_time"
fastas_dir="$output_dir/fastas_GISAID_uploaded"
error_dir="$output_dir/fastas_GISAID_errors"
error_log="$error_dir/error_log.txt"

#########################################################  
# Create dirs, logs
#########################################################
if [[ ! -d $parent_log_dir ]]; then mkdir -p "${parent_log_dir}" ; fi
if [[ ! -d $fastas_dir ]]; then mkdir -p "${fastas_dir}" ; fi
if [[ ! -d $error_dir ]]; then mkdir -p "${error_dir}" ; fi
if [[ ! -f $error_log ]]; then touch "$error_log"; fi

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
#Run batch pipeline locally
elif [[ $pipeline = "batch" ]]; then
	echo
	echo "*********Starting pipeline*********"

	####################### Preparation
	if [[ ! -d $run_dir ]]; then mkdir -p "${run_dir}"; fi

	echo "---------Preparing Configs"
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

	######################## run script
	echo "---------Running Script"
	sh scripts/gisaid.sh "${run_dir}" "${fastas_dir}" 2> "${run_dir}"/warnings.txt

	echo "*********Completed pipeline*********"
	echo
elif [[ $pipeline = "error" ]]; then
	echo
	echo "*********Starting error pipeline*********"

	####################### run process
	echo "---------handling errors"
	#read text file with errors, move fasta files to error dir
	for virus_name in $(cut -f1 "$error_log"); do
	
		#get id from virus name
		base_name=`echo $virus_name | grep -o -P '(?<=OH-).*(?=/)'`
		
		#create file name
		file_name="${base_name}_consensus.fasta"
		
		#move files
		mv "$fastas_dir"/$file_name "$error_dir" 2> "${error_dir}"/warnings.txt
	done
	
	echo "*********Completed pipeline*********"
	echo
fi