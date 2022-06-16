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
fastq_dir=$output_dir/fastq
cecret_dir=$output_dir/cecret

qc_dir=$output_dir/qc
qcreport_dir=$qc_dir/covid19_qcreport

tmp_dir=$output_dir/tmp
fastqc_dir=$tmp_dir/fastqc

analysis_dir=$output_dir/analysis

fasta_dir=$analysis_dir/fasta
intermed_dir=$analysis_dir/intermed

#set log files
sample_id_file=$log_dir/sample_ids.txt
pipeline_log=$log_dir/pipeline_log.txt
fragement_plot=$qc_dir/fragment_plot.png

#set configs
multiqc_config="$log_dir/config_multiqc.yaml"
pipeline_config="$log_dir/config_pipeline.yaml"
cecret_config="$log_dir/config_cecret.config"

#set basespace
basespace_cmd=$HOME/analysis_workflow/bin/basespace

# set date
date_stamp=`echo 20$project_name | sed 's/OH-[A-Z]*[0-9]*-//'`

# set merged, output files
merged_samples=$log_dir/completed_samples.txt
merged_cecret=$intermed_dir/cecret_results.txt
merged_nextclade=$intermed_dir/nextclade_results.csv
merged_pangolin=$intermed_dir/lineage_report.csv
merged_summary=$intermed_dir/cecret_summary.csv
merged_fragment=$qc_dir/fragment.txt

final_nextclade=$intermed_dir/final_nextclade.txt
final_pangolin=$intermed_dir/final_pangolin.txt
final_cecret=$intermed_dir/final_cecret.txt
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

elif [[ "$pipeline" == "run" ]]; then
	
        #############################################################################################
        # Prep
        #############################################################################################
	# check initialization was completed
	check_initialization

	# Eval YAML args
        eval $(parse_yaml ${pipeline_config} "config_")
	date_stamp=`echo 20$project_name | sed 's/OH-[A-Z]*[0-9]*-//'`
        final_results=$analysis_dir/final_results_$date_stamp.csv

	pangolin_id=$config_pangolin_version
        nextclade_id=$config_nextclade_version

	# Convert user selected numbers to complete software names
        pangolin_version=`cat config/software_versions.txt | awk '$1 ~ /pangolin/' | awk -v pid="$pangolin_id" '$2 ~ pid' | awk '{ print $3 }'`
        nextclade_version=`cat config/software_versions.txt | awk '$1 ~ /nextclade/' | awk -v pid="$nextclade_id" '$2 ~ pid' | awk '{ print $3 }'`
        if [[ "$pangolin_version" == "" ]] | [[ "$nextclade_version" == "" ]]; then
                echo "Choose the correct version of PANGOLIN/NEXTCLADE in /project/logs/config_pipeline.yaml"
                echo "PANGOLIN: $pangolin_version"
                echo "NEXTCLADE: $nextclade_version"
                exit
        fi

        #############################################################################################
        # CECRET UPDATES
        #############################################################################################
       	# Update CECRET config dependent on user input
	## update corrected software versions cecret config
        old_cmd="pangolin_container = 'staphb\/pangolin:latest'"
        new_cmd="pangolin_container = 'staphb\/pangolin:$pangolin_version'"
        sed -i "s/$old_cmd/$new_cmd/" $cecret_config

        old_cmd="nextclade_container = 'nextstrain\/nextclade:latest'"
        new_cmd="nextclade_container = 'nextstrain\/nextclade:$nextclade_version'"
        sed -i "s/$old_cmd/$new_cmd/" $cecret_config

	## update config if QC is not needed
	if [[ "$qc_flag" == "N" ]]; then
		old_cmd="params.samtools_stats = true"
        	new_cmd="params.samtools_stats = false"
		sed -i "s/$old_cmd/$new_cmd/" $cecret_config

		old_cmd="params.fastqc = true"
		new_cmd="params.fastqc = false"
        	sed -i "s/$old_cmd/$new_cmd/" $cecret_config
	fi

	## check reference files exist in reference dir, update reference files
        # for each reference file find matching output in config_pipeline
        # remove refence file name and leave reference value
        # create full path to reference value
        # check file existence
        # escape / with \/ for sed replacement
        # replace the cecret config file with the reference selected
        reference_list=("reference_genome" "gff_file" "primer_bed" "amplicon_bed")
        for ref_file in ${reference_list[@]}; do
                ref_line=$(cat "${pipeline_config}" | grep $ref_file)
                ref_path=`echo $config_reference_dir/${ref_line/"$ref_file": /} | tr -d '"'`
                if [[ -f $ref_path ]]; then
                        old_cmd="params.$ref_file = \"TBD\""
                        new_cmd="params.$ref_file = \"$ref_path\""
                        new_cmd=$(echo $new_cmd | sed 's/\//\\\//g')
                        sed -i "s/$old_cmd/$new_cmd/" $cecret_config

                else
                        echo "Reference file ($ref_file) is missing from $ref_path. Please update $pipeline_config"
                        exit 1
                fi
        done

        # replace the primer set used
        old_cmd="params.primer_set = 'TBD'"
        new_cmd="params.primer_set = \'$config_primer_set\'"
        sed -i "s/$old_cmd/$new_cmd/" $cecret_config

        #############################################################################################
        # CONFIG UPDATES
        #############################################################################################
	echo "------------------------------------------------------------------------"
	echo "------------------------------------------------------------------------" >> $pipeline_log
        echo "*** CONFIG INFORMATION ***"
	echo "*** CONFIG INFORMATION ***" >> $pipeline_log
        echo "Cecret config: $cecret_config" >> $pipeline_log
        echo "Sequence run date: $date_stamp" >> $pipeline_log
        echo "Analysis date:" `date` >> $pipeline_log
        echo "Pangolin version: $pangolin_version" >> $pipeline_log
        echo "Pangolin version: $pangolin_version"
        echo "Nexclade version: $nextclade_version" >> $pipeline_log
        echo "Nexclade version: $nextclade_version"
        cat "$cecret_config" | grep "params.reference_genome" >> $pipeline_log
        cat "$cecret_config" | grep "params.gff_file" >> $pipeline_log
        cat "$cecret_config" | grep "params.primer_bed" >> $pipeline_log
        cat "$cecret_config" | grep "params.amplicon_bed" >> $pipeline_log
        echo "------------------------------------------------------------------------" >> $pipeline_log

	#Pipeline starts
        echo "------------------------------------------------------------------------"
	echo "------------------------------------------------------------------------" >> $pipeline_log
	echo "*** STARTING CECRET PIPELINE ***"
	echo "*** STARTING CECRET PIPELINE ***" >> $pipeline_log
	echo "Starting time: `date`" >> $pipeline_log
	echo "Starting space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log

	#############################################################################################
	# Project Downloads
	#############################################################################################	
	#get project id
	project_id=`$basespace_cmd list projects --filter-term="${project_name_full}" | sed -n '4 p' | awk '{split($0,a,"|"); print a[3]}' | sed 's/ //g'`
	
	# if the project name does not match completely with basespace an ID number will not be found
	# display all available ID's to re-run project
	if [ -z "$project_id" ] && [ "$partial_flag" != "Y" ]; then
		echo "The project id was not found from $project_name_full. Review available project names below and try again"
		exit
	fi

	# if a QC report is to be created (qc_flag=Y) then download the necessary project analysis files
	# if it is not needed, and a full run is being completed
	# then download smaller json files to determine all sample ids in project
	if [[ "$qc_flag" == "Y" ]]; then
		echo "--Downloading analysis files (this may take a few minutes to begin)"
		echo "--Downloading analysis files" >> $pipeline_log
		echo "---Starting time: `date`" >> $pipeline_log
		$basespace_cmd download project --quiet -i $project_id -o "$tmp_dir" --extension=zip
		echo "---Ending time: `date`" >> $pipeline_log
                echo "---Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	elif [[ "$partial_flag" == "N" ]]; then
		echo "--Downloading sample list (this may take a few minutes to begin)"
		echo "--Downloading sample list" >> $pipeline_log
		echo "---Starting time: `date`" >> $pipeline_log
		$basespace_cmd download project --quiet -i $project_id -o "$tmp_dir" --extension=json
                echo "---Ending time: `date`" >> $pipeline_log
                echo "---Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	fi

	# remove scrubbed files, as they are zipped FASTQS and will be downloaded in batches later
	rm -r $tmp_dir/Scrubbed*	

	#############################################################################################
	# Batching
	#############################################################################################
	#break project into batches of N = batch_limit set above, create manifests for each
	sample_count=1
	batch_count=0

	# All project ID's download from BASESPACE will be processed into batches
	# Batch count depends on user input from pipeline_config.yaml
	# If a partial run is being performed, a batch file is required as user input
	echo "--Creating batch files"
	if [[ "$partial_flag" == "N" ]]; then
	        #create sample_id file - grab all files in dir, split by _, exclude noro- file names
        	ls $tmp_dir | cut -f1 -d "_" | grep "202[0-9]." | grep -v "noro.*" > $sample_id_file

        	#read in text file with all project id's
        	IFS=$'\n' read -d '' -r -a sample_list < $sample_id_file
		
		for sample_id in ${sample_list[@]}; do
			#if the sample count is 1 then create new batch
			if [[ "$sample_count" -eq 1 ]]; then
				batch_count=$((batch_count+1))
			
				#remove previous versions of batch log
				if [[ "$batch_count" -gt 9 ]]; then batch_name=$batch_count; else batch_name=0${batch_count}; fi
				
				#remove previous versions of batch log
				batch_manifest=$log_dir/batch_${batch_name}.txt
				if [[ -f $batch_manifest ]]; then rm $batch_manifest; fi
				
				#create batch manifest
				touch $log_dir/batch_${batch_name}.txt
			fi
		
			#set batch manifest
			batch_manifest=$log_dir/batch_${batch_name}.txt
		
			#echo sample id to the batch
			echo ${sample_id} >> $batch_manifest
		
			#increase sample counter
			((sample_count+=1))
		
			#reset counter when equal to batch_limit
			if [[ "$sample_count" -gt "$config_batch_limit" ]]; then
				sample_count=1
			fi
		done
	
		#gather final count
		sample_count=${#sample_list[@]}
		batch_min=1
	else
		# Partial runs allow the user to submit pre-defined batch files with samples
		# Determine how many batch files are to be used and total number of samples within files
		batch_min=`ls $log_dir/batch* | cut -f2 -d"_" | cut -f1 -d "." | sed "s/$0//" | sort | head -n1`
		batch_count=`ls $log_dir/batch* | cut -f2 -d"_" | cut -f1 -d "." | sed "s/$0//" | sort | tail -n1`
		tmp_count=0

		for (( batch_id=$batch_min; batch_id<=$batch_count; batch_id++ )); do
			if [[ "$batch_id" -gt 9 ]]; then batch_name=$batch_id; else batch_name=0${batch_id}; fi
			
			tmp_count=`wc -l < ${log_dir}/batch_${batch_name}.txt`
                        sample_count=`expr $tmp_count + $sample_count`
		done

		if [[ "$sample_count" -eq 0 ]]; then
			echo "At least one batch file is required for partial runs. Please create $log_dir/batch_01.txt"
			exit
		fi
	fi
	
	# For testing scenarios two batches of two samples will be run
	# Take the first four samples and remove all other batches
	if [[ "$testing_flag" == "Y" ]]; then
		
		for (( batch_id=1; batch_id<=$batch_count; batch_id++ )); do
			
			batch_manifest=$log_dir/batch_0$batch_id.txt
			
			if [[ "$batch_id" == 1 ]] || [[ "$batch_id" == 2 ]]; then
				head -2 $batch_manifest > tmp.txt
				mv tmp.txt $batch_manifest
			else
				rm $batch_manifest
			fi
		done
		
		# set new batch count
		batch_count=2
		sample_count=4
	fi
       
	#log
        echo "--A total of $sample_count samples will be processed in $batch_count batches, with a maximum of $config_batch_limit samples per batch"
        echo "--A total of $sample_count samples will be processed in $batch_count batches, with a maximum of $config_batch_limit samples per batch" >> $pipeline_log

	#merge all batched outputs
	touch $merged_samples
        touch $merged_cecret
        touch $merged_nextclade
        touch $merged_pangolin
        touch $merged_summary
	touch $merged_fragment

	#############################################################################################
	# Analysis
	#############################################################################################
	#log
	echo "--Processing batches:"
	echo "--Processing batches:" >> $pipeline_log

	#for each batch
	for (( batch_id=$batch_min; batch_id<=$batch_count; batch_id++ )); do

		# set batch name
		if [[ "$batch_id" -gt 9 ]]; then batch_name=$batch_id; else batch_name=0${batch_id}; fi
		
		#set manifest
		batch_manifest=$log_dir/batch_${batch_name}.txt

		fastq_batch_dir=$fastq_dir/batch_$batch_id
		cecret_batch_dir=$cecret_dir/batch_$batch_id
		if [[ ! -d $fastq_batch_dir ]]; then mkdir $fastq_batch_dir; fi
		if [[ ! -d $cecret_batch_dir ]]; then mkdir $cecret_batch_dir; fi

		#read text file
		IFS=$'\n' read -d '' -r -a sample_list < $batch_manifest

		#log
		# print number of lines in file without file name "<"
		n_samples=`wc -l < $batch_manifest`
		echo "----Batch_$batch_id ($n_samples samples)"
		echo "----Batch_$batch_id ($n_samples samples)" >> $pipeline_log


		#run per sample
		for sample_id in ${sample_list[@]}; do
		
			# download fastq files
			$basespace_cmd download biosample --quiet -n "${sample_id}" -o $fastq_dir

        	        # move files to batch fasta dir
                        #rm -r $fastq_dir/*L001*
			mv $fastq_dir/*${sample_id}*/*fastq.gz $fastq_batch_dir
                        
			# If generating a QC report, BASESPACE files need to be unzipped
			# and selected files moved for downstream analysis
			if [[ "$qc_flag" == "Y" ]]; then
				
                        	#make sample tmp_dir: tmp_dir/sample_id
                        	if [[ ! -d "$tmp_dir/${sample_id}" ]]; then mkdir $tmp_dir/${sample_id}; fi

				#unzip analysis file downloaded from DRAGEN to sample tmp dir - used in QC
                		unzip -o -q $tmp_dir/${sample_id}_[0-9]*/*_all_output_files.zip -d $tmp_dir/${sample_id}

                		#move needed files to general tmp dir
				mv $tmp_dir/${sample_id}/ma/* $tmp_dir/unzipped
                        	
				#remove sample tmp dir, downloaded proj dir
                        	rm -r --force $tmp_dir/${sample_id}
			fi

			# remove downloaded tmp dir
			rm -r --force $tmp_dir/${sample_id}_[0-9]*/
        	done

		#log
		echo "------CECRET"
		echo "------CECRET" >> $pipeline_log
		echo "-------Starting time: `date`" >> $pipeline_log
	        echo "-------Starting space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	
		#run cecret
		staphb-wf cecret $fastq_batch_dir --reads_type paired --config $cecret_config --output $cecret_batch_dir

                echo "-------Ending time: `date`" >> $pipeline_log
		echo "-------Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log

		#############################################################################################
		# Clean-up
		#############################################################################################
		#add to master sample log
		cat $log_dir/batch_${batch_name}.txt >> $merged_samples
		
		#add to  master cecret results
		cat $cecret_batch_dir/cecret_results.txt >> $merged_cecret

		#add to master nextclade results
		cat $cecret_batch_dir/nextclade/nextclade.csv >> $merged_nextclade

		#add to master pangolin results
		cat $cecret_batch_dir/pangolin/lineage_report.csv >> $merged_pangolin

		#add to master cecret summary
		cat $cecret_batch_dir/summary/combined_summary.csv >> $merged_summary

		# If QC report is being created, generate stats on fragment length
                if [[ "$qc_flag" == "Y" ]]; then
			for f in $cecret_batch_dir/samtools_stats/aligned/*.stats.txt; do
                		frag_length=`cat $f | grep "average length" | awk '{print $4}'`
				file_name=`echo $f | rev | cut -f1 -d "/" | rev`
				file_name=${file_name%.stats*}
				echo -e "${file_name}\t${frag_length}\t${batch_id}" >> $merged_fragment
			done
		fi

		# move FASTQC files
		if [[ "$qc_flag" == "Y" ]]; then mv $cecret_batch_dir/fastqc/* $fastqc_dir; fi
		
		# move FASTA files
		mv $cecret_batch_dir/consensus/* $fasta_dir/not_uploaded

		#remove intermediate files
		sudo rm -r --force work
		sudo rm -r --force $cecret_batch_dir
		sudo rm -r --force $fastq_batch_dir

	        # changes in software adds project name to some sample_ids. In order to ensure consistency throughout naming and for downstream
        	# uploading, project name should be removed.
		## remove from the fasta files header, names
		for f in $fasta_dir/not_uploaded/*; do
			# remove projectid from header
			sed -i "s/$project_id//g" $f

			# rename files
			new_id=`echo $f | awk -v p_id=$project_id '{ gsub(p_id,"",$1) ; print }'`
			if [[ $f != $new_id ]]; then mv $f $new_id; fi
		done
		
		## remove from intermediate output files
		for f in $intermed_dir/*; do
			# remove projectid
			sed -i "s/$project_id//g" $f
		done

		## remove from FASTQC,unzipped file names
                for f in $fastqc_dir/*; do
                        # rename files
                        new_id=`echo $f | awk -v p_id=$project_id '{ gsub(p_id,"",$1) ; print }'`
                        if [[ $f != $new_id ]]; then mv $f $new_id; fi
		done
		
                for f in $tmp_dir/unzipped/*; do
                        # rename files
                        new_id=`echo $f | awk -v p_id=$project_id '{ gsub(p_id,"",$1) ; print }'`
                        if [[ $f != $new_id ]]; then mv $f $new_id; fi
		done
	done

	#############################################################################################
	# Create reports
	#############################################################################################
	if [[ "$qc_flag" == "Y" ]]; then
		#log
		echo "--Creating QC Report"
		echo "--Creating QC Report" >> $pipeline_log
		echo "---Starting time: `date`" >> $pipeline_log
        	echo "---Starting space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log

		#-d -dd 1 adds dir name to sample name
		multiqc -f -v \
        		-c $multiqc_config \
        		$fastqc_dir \
        		$tmp_dir/unzipped \
        		-o $qcreport_dir
	
        	#create fragment plot
	        python scripts/fragment_plots.py $merged_fragment $fragement_plot
	else
		rm -r $qc_dir
	fi 
	
	# merge batch outputs into intermediate files
	# join contents of cecret and nextclade into final output table	
	# from nextclade: sampleid, AAsubstitutions
	cat $merged_nextclade | sort | uniq -u | awk -F';' '{print $1,$27}' | \
		awk '{ gsub(/Consensus_/,"",$1) gsub(/\.consensus_[a-z0-9._]*/,"",$1); print }'| awk -v q="\"" '{ print $1","q $2 q }' | awk '{ gsub(/"/,"",$2); print }' > $final_nextclade
	# from pangloin: sampleid, pangolin_status, lineage
	cat $merged_pangolin | sort | uniq -u |  awk -F',' '{print $1,$12,$2}'| \
		awk '{ gsub(/Consensus_/,"",$1) gsub(/\.consensus_[a-z0-9._]*/,"",$1); print }' | awk '{print $1","$2","$3}' > $final_pangolin
	
	# from cecret: sample_id,pangolin_status,nextclade_clade,pangolin_lineage,pangolin_scorpio
        cat $merged_cecret | sort | uniq | awk -F"\t" '{ print $1","$25","$4","$3","$20 }' | head -n -1 >> $final_cecret

	# create final results
        echo "sample_id,pango_qc,nextclade_clade,pangolin_lineage,pangolin_scorpio,aa_substitutions" > $final_results
	join <(sort $final_cecret) <(sort $final_nextclade) -t $',' >> $final_results


	#remove all proj files
	rm -r --force $tmp_dir
	rm -r --force $cecret_dir
	rm -r --force $fastq_dir
	rm -r --force $fastqc_dir

	echo "Ending time: `date`" >> $pipeline_log
	echo "Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	echo "*** CECRET PIPELINE COMPLETE ***"
	echo "*** CECRET PIPELINE COMPLETE ***" >> $pipeline_log
        echo "------------------------------------------------------------------------"
        echo "------------------------------------------------------------------------" >> $pipeline_log

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

	date_stamp=`echo 20$project_name | sed 's/OH-[A-Z]*[0-9]*-//'`
	ncbi_metadata=$log_dir/${project_id}_${date_stamp}.tsv

        # Eval YAML args
	eval $(parse_yaml ${pipeline_config} "config_")
	metadata_file="$log_dir/$config_metadata_file"

        # determine number of samples
	fasta_number=`ls "$fasta_dir/upload_partial"/ | wc -l`
	

	if [[ $fasta_number -gt 1 ]]; then
		bash scripts/ncbi_upload.sh ncbi_metadata
	else
		echo "No samples for upload"
	fi

elif [[ "$pipeline" == "stats" ]]; then
	echo "*** RUNNING PIPELINE STATS ***"
	
	echo "-- GISAID STATS"
	# number failed pipeline qC
	val=`cat $final_results | grep "gisaid_fail" | wc -l`
	echo "Number failed pipeline QC: $val"

	# number uploaded success
	val=`cat $final_results | grep "gisaid_pass" | wc -l`
	echo "Number uploaded successfully: $val"

	# number failed upload QC
        val=`cat $final_results | grep "gisaid_rejected" | wc -l`
	echo "Number uploaded and rejected: $val"

	# number of samples with missing metadata
        val=`cat $final_results | grep "missing" | wc -l`
        echo "Number missing metadata: $val"
	if [[ $val -gt 0 ]]; then 
		cat $intermed_dir/gisaid_results.csv | grep "missing" >> ../missing_metadata.csv
		sed -i "s/gisaid_fail/$project_id/g" ../missing_metadata.csv
		cat $intermed_dir/gisaid_results.csv | uniq > tmp.csv
		mv tmp.csv > ../missing_metadata.csv
		rm tmp.csv
	fi

	# number of samples with errors
        fasta_number=`ls "$fasta_dir/not_uploaded"/ | wc -l`
	echo "Number not processed: $val"
	
else
	echo "Pipeline options (-p) must be init, run, gisaid stats, or update"
fi

