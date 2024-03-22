#!/bin/bash


#############################################################################################
# Background documentation
#############################################################################################
# Basespace
# https://developer.basespace.illumina.com/docs/content/documentation/cli/cli-examples#Downloadallrundata

#Docker location
# https://hub.docker.com/u/staphb

#CECRET GitHub location
# https://github.com/UPHL-BioNGS/Cecret

#############################################################################################
# helper functions
#############################################################################################

helpFunction()
{
   echo ""
   echo "Usage: $1 -p [REQUIRED] pipeline runmode"
   echo -e "\t-p options: init, sarscov2, gisaid, ncbi, stat, update"
   echo "Usage: $2 -n [REQUIRED] project_id"
   echo -e "\t-n project id"
   echo "Usage: $3 -s [REQUIRED] subworkflow options"
   echo -e "\t-s DOWNLOAD, BATCH, ANALYZE REPORT CLEAN ALL | PREP UPLOAD QC"
   echo "Usage: $4 -r [OPTIONAL] resume options"
   echo -e "\t-r Y,N option to resume -p GISAID workflow in progress"
   echo "Usage: $5 -t [OPTIONAL] testing options"
   echo -e "\t-r Y,N option to run test"
   exit 1 # Exit script after printing help
}

while getopts "p:n:s:r:t:" opt
do
   case "$opt" in
        p ) pipeline="$OPTARG" ;;
        n ) project_id="$OPTARG" ;;
        s ) subworkflow="$OPTARG" ;;
       	r ) resume="$OPTARG" ;;
       	t ) testing="$OPTARG" ;;		
	? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$pipeline" ] || [ -z "$project_id" ]; then
   echo "Some or all of the parameters are empty";
   helpFunction
fi
if [ -z "$resume" ]; then resume="N";fi
if [ -z "$testing" ]; then testing="N";fi
#############################################################################################
# other functions
#############################################################################################
check_initialization(){
  if [[ ! -d $log_dir ]] || [[ ! -f "$pipeline_config" ]]; then
    echo "ERROR: You must initalize the dir before beginning pipeline"
	echo "$log_dir"
	echo "$pipeline_config"
    exit 1
  fi
}

# source global functions
source $(dirname "$0")/scripts/functions.sh

#############################################################################################
# args
#############################################################################################
# Remove trailing / to project_name if it exists
# some projects may have additional information (IE OH-1234 SARS ONLY) in the name
# To avoid issues within project naming schema remove all information after spaces
# To ensure consistency in all projects, remove all information after _
project_name_full=$(echo $project_id | sed 's:/*$::')
project_name=$(echo $project_id | cut -f1 -d "_" | cut -f1 -d " ")

# set date
proj_date=`echo 20$project_name | sed 's/OH-[A-Z]*[0-9]*-//' | sed "s/_SARS//g"`
today_date=$(date '+%Y-%m-%d'); today_date=`echo $today_date | sed "s/-//g"`
#############################################################################################
# Dir, Configs
#############################################################################################
# set dirs
output_dir="/home/ubuntu/output/$project_name"
log_dir=$output_dir/logs
tmp_dir=$output_dir/tmp
analysis_dir=$output_dir/analysis

# set files
final_results=$analysis_dir/reports/final_results_$today_date.csv
pipeline_log=$log_dir/pipeline_log.txt
multiqc_config="$log_dir/config/config_multiqc.yaml"
pipeline_config="$log_dir/config/config_pipeline.yaml"
cecret_config="$log_dir/config/config_cecret.config"

#############################################################################################
# Runmodes
#############################################################################################
if [[ "$pipeline" == "phase1" ]]; then
	bash run_analysis_pipeline.sh -n $project_id -p init

	bash run_analysis_pipeline.sh -n $project_id -p analysis -s ALL

	bash run_analysis_pipeline.sh -n $project_id -p gisaid -s ALL

elif [[ "$pipeline" == "init" ]]; then
	
	# print message
	echo
	echo "*** INITIALIZING PIPELINE ***"

	# make directories, logs
    ## parent
	dir_list=(logs tmp analysis ncbi)
    for pd in "${dir_list[@]}"; do makeDirs $output_dir/$pd; done
    
	## logs
	dir_list=(config manifests/complete pipeline gisaid ncbi)
    for pd in "${dir_list[@]}"; do makeDirs $log_dir/$pd; done
	touch $log_dir/manifests/sample_ids.txt
	
	## tmp
    dir_list=(qc)
    for pd in "${dir_list[@]}"; do makeDirs $tmp_dir/$pd; done
	
    ## analysis
    dir_list=(fasta intermed reports)
    for pd in "${dir_list[@]}"; do makeDirs $analysis_dir/$pd; done

    ##log file
    touch $pipeline_log

	# copy config inputs to edit if doesn't exit
	files_save=("config/config_pipeline.yaml" "config/config_cecret.config" "config/config_multiqc.yaml")
  	for f in ${files_save[@]}; do
        IFS='/' read -r -a strarr <<< "$f"
    	if [[ ! -f "${log_dir}/config/${strarr[1]}" ]]; then
            cp $f "${log_dir}/config/${strarr[1]}"
		fi
	done

	#update metadata name
	sed -i "s~metadata.csv~${log_dir}/manifests/metadata-${project_name}.csv~" "${log_dir}/config/config_pipeline.yaml" 

	# copy report scripts
	cp scripts/COVID* $analysis_dir/reports

  	#output
	echo -e "Configs are ready to be edited:\n${log_dir}/config"
	echo "*** INITIALIZATION COMPLETE ***"
	echo

elif [[ "$pipeline" == "analysis" ]]; then
	
	#############################################################################################
    # Run CECRET pipeline
	#############################################################################################
	# check initialization was completed
	check_initialization

    # run SARS-COV2 pipeline
	bash scripts/core_analysis.sh \
		"${output_dir}" \
		"${project_name_full}" \
		"${pipeline_config}" \
		"${cecret_config}" \
		"${multiqc_config}" \
		"${proj_date}" \
		"${pipeline_log}" \
		"${subworkflow}" \
		"${resume}" \
		"${testing}"

elif [[ "$pipeline" == "gisaid" ]]; then
	############################################################################################
    # Run GISAID UPLOAD
    #############################################################################################
	# run gisaid script
    bash scripts/core_gisaid.sh \
		"${output_dir}" \
		"${project_id}" \
		"${pipeline_config}" \
		"${final_results}" \
		"${subworkflow}"  \
		"${proj_date}"
elif [[ "$pipeline" == "ncbi" ]]; then
	
    ##########################################################
    # Eval, source
    #########################################################
	eval $(parse_yaml ${pipeline_config} "config_")

	#############################################################################################
    # Run NCBI UPLOAD
    #############################################################################################
	message_cmd_log "------------------------------------------------------------------------"
	message_cmd_log "--- STARTING NCBI PIPELINE ---"

	# set args
	proj_date=`echo 20$project_name | sed 's/OH-[A-Z]*[0-9]*-//'`
	ncbi_mput=$log_dir/${project_id}_${proj_date}_mput.txt
	gisaid_results=$analysis_dir/intermed/gisaid_results.csv

    # Eval YAML args
	metadata_file="$log_dir/$config_metadata_file"

    # run inital upload or merge results
	if [[ $reject_flag == "N" ]]; then	
		# determine number of samples
		fasta_number=`ls "$analysis_dir/fasta/upload_partial"/ | wc -l`
		
		if [[ $fasta_number -gt 1 ]]; then
			# run batch command
			bash scripts/ncbi.sh "${output_dir}" "${project_id}" "${pipeline_config}" "${gisaid_results}" "${reject_flag}" "${final_results}"
			
		else
			echo "No samples for upload"
		fi
	else
		# merge multiple NCBI outputs
		header="header.txt"
		joined="joined.txt"
		cleaned="cleaned.txt"
		final="metadata-processed-ok.tsv"
		for f in $ncbi_hold/complete/metadata*ok*; do
			if [[ ! -f $header ]]; then head -n1 $f > $header; fi
    		if [[ ! -f $joined ]]; then touch $joined; fi
    		cat $f >> $joined
			
			# rename the file
			new_name=`echo $f | sed "s/-processed-ok//g"`
    		mv $f $new_name
		done

		cat $header > $ncbi_hold/complete/$final
		grep -v "accession" $joined > $cleaned
		cat $cleaned | sort | uniq >> $ncbi_hold/complete/$final
		rm $header $joined $cleaned

   		# check metadata return file is in dir
		ncbi_sra=`ls $ncbi_hold/complete/*ok*`
		
		# run batch command
		if [[ -f $ncbi_sra ]]; then
			bash scripts/ncbi.sh "${output_dir}" "${project_id}" "${pipeline_config}" "${gisaid_results}" "${reject_flag}" "${final_results}"
		
			# run stats
            bash run_analysis_pipeline.sh -m stats -n $project_id
		else
			echo "MISSING metadata output file"
		fi
	fi

	# complete
	message_cmd_log "--- COMPLETED NCBI PIPELINE ---"
else
	echo "Pipeline options (-p) must be init, analysis, gisaid, ncbi, stats, update"
fi