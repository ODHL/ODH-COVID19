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
# functions
#############################################################################################

helpFunction()
{
   echo ""
   echo "Usage: $1 -m [REQUIRED]pipeline mode options"
   echo -e "\t-m options: init, run, gisaid, ncbi, stat, update"
   echo "Usage: $2 -n [REQUIRED] project_id"
   echo -e "\t-n project id"
   echo "Usage: $3 -q [OPTIONAL] qc_flag"
   echo -e "\t-q Y,N option to run QC analysis (default Y)"
   echo "Usage: $4 -t [OPTIONAL] testing_flag"
   echo -e "\t-t Y,N option to run test settings (default N)"   
   echo "Usage: $5 -p [OPTIONAL] partial_run"
   echo -e "\t-p Y,N option to run partial run settings (default N)"
   echo "Usage: $6 -r [OPTIONAL] reject_flag"
   echo -e "\t-r Y,N option to run GISAID rejected sample processing (default N)"
   exit 1 # Exit script after printing help
}

check_initialization(){
  if [[ ! -d $log_dir ]] || [[ ! -f "$pipeline_config" ]]; then
    echo "ERROR: You must initalize the dir before beginning pipeline"
    exit 1
  fi
}

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

#############################################################################################
# helper function
#############################################################################################
while getopts "m:n:q:t:p:r:" opt
do
   case "$opt" in
        m ) pipeline="$OPTARG" ;;
        n ) project_id="$OPTARG" ;;
        q ) qc_flag="$OPTARG" ;;
        t ) testing_flag="$OPTARG" ;;
        p ) partial_flag="$OPTARG" ;;
       	r ) reject_flag="$OPTARG" ;;
	? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$pipeline" ] || [ -z "$project_id" ]; then
   echo "Some or all of the parameters are empty";
   helpFunction
fi

#############################################################################################
# args
#############################################################################################
# Remove trailing / to project_name if it exists
# some projects may have additional information (IE OH-1234 SARS ONLY) in the name
# To avoid issues within project naming schema remove all information after spaces
project_name_full=$(echo $project_id | sed 's:/*$::')
project_name=$(echo $project_id | cut -f1 -d "_" | cut -f1 -d " ")
output_dir="../$project_name"

#set defaults for optional args
if [ -z "$qc_flag" ]; then qc_flag="Y"; fi
if [ -z "$testing_flag" ]; then testing_flag="N"; fi
if [ -z "$partial_flag" ]; then partial_flag="N"; fi
if [ -z "$reject_flag" ]; then reject_flag="N"; fi

#############################################################################################
# Dir, Configs
#############################################################################################
# set dirs
log_dir=$output_dir/logs

qc_dir=$output_dir/qc

tmp_dir=$output_dir/tmp

analysis_dir=$output_dir/analysis

fasta_dir=$analysis_dir/fasta
intermed_dir=$analysis_dir/intermed

ncbi_hold="../ncbi_hold/$project_id"

#set log files
pipeline_log=$log_dir/pipeline_log.txt

#set configs
multiqc_config="$log_dir/config_multiqc.yaml"
pipeline_config="$log_dir/config_pipeline.yaml"
cecret_config="$log_dir/config_cecret.config"

# set date
date_stamp=`echo 20$project_name | sed 's/OH-[A-Z]*[0-9]*-//'`

# set final file
final_results=$analysis_dir/final_results_$date_stamp.csv

#############################################################################################
# Run CECRET
#############################################################################################
if [[ "$pipeline" == "init" ]]; then
	
	echo
	echo "*** INITIALIZING PIPELINE ***"

	#make directories, logs
        if [[ ! -d $output_dir ]]; then mkdir $output_dir; fi

        ##parent
        dir_list=(logs fastq cecret qc tmp analysis)
        for pd in "${dir_list[@]}"; do if [[ ! -d $output_dir/$pd ]]; then mkdir -p $output_dir/$pd; fi; done

        ##qc
        dir_list=(covid19_qcreport)
        for pd in "${dir_list[@]}"; do if [[ ! -d $qc_dir/$pd ]]; then mkdir -p $qc_dir/$pd; fi; done

        ##tmp
        dir_list=(fastqc unzipped)
        for pd in "${dir_list[@]}"; do if [[ ! -d $tmp_dir/$pd ]]; then mkdir -p $tmp_dir/$pd; fi; done

        ##analysis
        dir_list=(fasta intermed)
        for pd in "${dir_list[@]}"; do if [[ ! -d $analysis_dir/$pd ]]; then mkdir -p $analysis_dir/$pd; fi; done

	##gisaid/ncbi
	dir_list=(not_uploaded upload_complete upload_partial upload_failed)
        for pd in "${dir_list[@]}"; do if [[ ! -d $fasta_dir/$pd ]]; then mkdir -p $fasta_dir/$pd; fi; done

        ##make files
        touch $pipeline_log

	# copy config inputs to edit if doesn't exit
	files_save=("config/config_pipeline.yaml" "config/config_cecret.config" "config/config_multiqc.yaml")
  	for f in ${files_save[@]}; do
        	IFS='/' read -r -a strarr <<< "$f"
        	if [[ ! -f "${log_dir}/${strarr[1]}" ]]; then
                	cp $f "${log_dir}/${strarr[1]}"
		fi
	done

	#update metadata name
	sed -i "s/merged_complete.csv/metadata_${project_name}.csv/" "${log_dir}/config_pipeline.yaml" 

  	#output
	echo -e "Configs are ready to be edited:\n${log_dir}"
	echo "*** INITIALIZATION COMPLETE ***"
	echo

elif [[ "$pipeline" == "update" ]]; then

        #update the staphb toolkit
        staphb-wf --auto_update

elif [[ "$pipeline" == "cecret" ]]; then
	
	#############################################################################################
    # Run CECRET pipeline
    #############################################################################################
    echo "------------------------------------------------------------------------"
    echo "------------------------------------------------------------------------" >> $pipeline_log
   	echo "*** STARTING CECRET PIPELINE ***" >> $pipeline_log
    echo "*** STARTING CECRET PIPELINE ***"

	# check initialization was completed
	check_initialization
	
    # Eval YAML args
	eval $(parse_yaml ${pipeline_config} "config_")
	metadata_file="$log_dir/$config_metadata_file"
	date_stamp=`echo 20$project_name | sed 's/OH-[A-Z]*[0-9]*-//'`

    # run pipelien
	bash scripts/ncbi.sh \
		"${output_dir}" \
		"${project_name_full}" \
		"${pipeline_config}" \
		"${cecret_config}" \
		"${multiqc_config}" \
		"${date_stamp}" \
		"${pipeline_log}" \
		"${qc_flag}" \
		"${partial_flag}"
		
	# run QC
	## TODO decouple gisaid QC

elif [[ "$pipeline" == "gisaid" ]]; then
        #############################################################################################
        # Run GISAID UPLOAD
        #############################################################################################
	if [[ $reject_flag == "N" ]]; then
		echo "------------------------------------------------------------------------"
	        echo "------------------------------------------------------------------------" >> $pipeline_log
        	echo "*** STARTING GISAID PIPELINE ***" >> $pipeline_log
        	echo "*** STARTING GISAID PIPELINE ***"

        	# Eval YAML args
	        eval $(parse_yaml ${pipeline_config} "config_")
        	metadata_file="$log_dir/$config_metadata_file"

		# determine number of samples
		fasta_number=`ls "$fasta_dir/not_uploaded"/ | wc -l`
		
		# run QC on fasta samples
		if [[ "$fasta_number" -gt 0 ]]; then 
			echo "----Processing $fasta_number samples"
	        
			# check metadata file exists
        		if [[ ! -f $metadata_file ]]; then
                		echo "----Missing metadata file $metadata_file. File must be located in $log_dir. Review config_pipeline to update file name."
                		exit
        		fi
		else
			echo "----Missing fasta files"
			exit
		fi
		
		# log
		echo "--uploading samples" >> $pipeline_log
        	
		# run gisaid script
        	bash scripts/gisaid.sh "${output_dir}" "${project_id}" "${pipeline_config}" "${final_results}" "${reject_flag}" 2>> "$pipeline_log"
        
	        # run stats
	        bash run_analysis_pipeline.sh -m stats -n $project_id
	else
		# determine number of samples
		sample_number=`cat reject_search.csv | wc -l`
                echo "--Processing rejected $sample_number samples"
	
		# find the samples that were rejected	
		if [[ -f reject_find.csv ]]; then rm reject_find.csv; fi
		while read search_id; do search_num=`echo $search_id | cut -f1 -d"," | cut -f4 -d"-" | cut -f1 -d"/" | \
		cut -f2 -d"C"`; file_name=`ls ../*/analysis/fasta/*/*$search_num.*`; echo "$search_id+$file_name"; done < reject_search.csv >> reject_find.csv
		
		file_number=`cat reject_find.csv | wc -l`

		# check one:to:one sample to file find
		if [[ $sample_number == $file_number ]]; then
			
			# for each rejected sample, run reject GISAID pipeline
			while read search_id; do
					
				# set new variables
				project_id=`echo $search_id | cut -f2 -d"+" | cut -f2 -d"/"` 
				date_stamp=`echo 20$project_id | sed 's/OH-[A-Z]*[0-9]*-//'`
				output_dir="../$project_id"
				pipeline_config="$output_dir/logs/config_pipeline.yaml"
				final_results="$output_dir/analysis/final_results_$date_stamp.csv"
				pipeline_log="$output_dir/logs/pipeline_log.txt"
				sample_id=`echo $search_id | cut -f1 -d","`

				# create rejected file
				reject_master="$output_dir/analysis/intermed/gisaid_rejected.csv"
				reject_tmp="$output_dir/analysis/intermed/gisaid_rejected_tmp.csv"
			
				echo $search_id | cut -f1 -d"+" > $reject_tmp
				
				if [[ -f $rejected_master ]]; then
					cat $reject_tmp >> $reject_master
				else
					cp $reject_tmp $reject_master
				fi
				
				echo "----$sample_id"

				# process sample
				bash scripts/gisaid.sh "${output_dir}" "${project_id}" "${pipeline_config}" "${final_results}" "${reject_flag}" 2>> "$pipeline_log"
			done < reject_find.csv

			#log 
	                echo "--analyzing rejected samples" >> $pipeline_log
			rm $reject_tmp
		else
			echo "Number of files does not match samples. Review log"
			exit
		fi

	fi

	echo "*** GISAID PIPELINE COMPLETE ***"
	echo "*** GISAID PIPELINE COMPLETE ***" >> $pipeline_log
	echo "------------------------------------------------------------------------"
       	echo "------------------------------------------------------------------------" >> $pipeline_log
elif [[ "$pipeline" == "ncbi" ]]; then
	
	#############################################################################################
        # Run NCBI UPLOAD
        #############################################################################################
       	echo "------------------------------------------------------------------------"
        echo "------------------------------------------------------------------------" >> $pipeline_log
       	echo "*** STARTING NCBI PIPELINE ***" >> $pipeline_log
        echo "*** STARTING NCBI PIPELINE ***"

	# set args
	date_stamp=`echo 20$project_name | sed 's/OH-[A-Z]*[0-9]*-//'`
	ncbi_mput=$log_dir/${project_id}_${date_stamp}_mput.txt
	gisaid_results=$analysis_dir/intermed/gisaid_results.csv

        # Eval YAML args
	eval $(parse_yaml ${pipeline_config} "config_")
	metadata_file="$log_dir/$config_metadata_file"

        # run inital upload or merge results
	if [[ $reject_flag == "N" ]]; then	
		# determine number of samples
		fasta_number=`ls "$fasta_dir/upload_partial"/ | wc -l`
		
		if [[ $fasta_number -gt 1 ]]; then
			# run batch command
			bash scripts/ncbi.sh "${output_dir}" "${project_id}" "${pipeline_config}" "${gisaid_results}" "${reject_flag}" "${final_results}"
			
		else
			echo "No samples for upload"
		fi
	else
		# check metadata return file is in dir
		ncbi_sra=`ls $ncbi_hold/complete/metadata-*`
		
		# run batch command
		if [[ -f $ncbi_sra ]]; then
			bash scripts/ncbi.sh "${output_dir}" "${project_id}" "${pipeline_config}" "${gisaid_results}" "${reject_flag}" "${final_results}"
		
			# run stats
                	bash run_analysis_pipeline.sh -m stats -n $project_id
		else
			echo "MISSING metadata output file"
		fi
	fi

elif [[ "$pipeline" == "stats" ]]; then
	echo "*** RUNNING PIPELINE STATS ***"
        # total number
        val=`ls ${output_dir}/analysis/fasta/*/*.fa | wc -l`
        echo "--Total number of samples $val"

	# number failed pipeline qC
	val=`cat $final_results | grep "qc_fail" | wc -l`
	echo "----Number failed pipeline QC: $val"

	echo "-- GISAID STATS"
	# number uploaded success
	val=`cat $final_results | grep "gisaid_pass" | wc -l`
	echo "---- Number GISAID uploaded successfully: $val"

	# number failed upload QC
        val=`cat $final_results | grep "gisaid_rejected" | wc -l`
	echo "---- Number GISAID uploaded and rejected: $val"

	# number of samples with missing metadata
        val=`cat $final_results | grep "missing" | wc -l`
        echo "---- Number missing metadata: $val"
	if [[ $val -gt 0 ]]; then 
		cat $intermed_dir/gisaid_results.csv | grep "missing" >> ../missing_metadata.csv
		sed -i "s/gisaid_fail/$project_id/g" ../missing_metadata.csv
		cat $intermed_dir/gisaid_results.csv | uniq > tmp.csv
		mv tmp.csv > ../missing_metadata.csv
		rm tmp.csv
	fi

	echo "-- NCBI Results"
        # number passed upload
        val=`cat $final_results | grep "ncbi_pass" | wc -l`
        echo "---- Number NCBI uploaded: $val"

	
else
	echo "Pipeline options (-p) must be init, run, gisaid, ncbi, stats, or update"
fi

