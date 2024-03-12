#########################################################
# ARGS
#########################################################
output_dir=$1
project_name_full=$2
pipeline_config=$3
cecret_config=$4
multiqc_config=$5
proj_date=$6
pipeline_log=$7
subworkflow=$8
resume=$9
testing=${10}

#########################################################
# Pipeline controls
########################################################
# three options for testing 
## N = run full run
## T = run 2 batches, 4 samples
## U = run user generated manifest
flag_download="N"
flag_batch="N"
flag_analysis="N"
flag_cleanup="N"
flag_report="N"
if [[ $subworkflow == "BATCH" ]]; then
    flag_batch="Y"
elif [[ $subworkflow == "DOWNLOAD" ]]; then
	flag_download="Y"
elif [[ $subworkflow == "ANALYZE" ]]; then
    flag_analysis="Y"
elif [[ $subworkflow == "REPORT" ]]; then
    flag_report="Y"
elif [[ $subworkflow == "CLEAN" ]]; then
    flag_cleanup="Y"
elif [[ $subworkflow == "ALL" ]]; then
	flag_download="Y"
    flag_batch="Y"
    flag_analysis="Y"
    flag_report="Y"
    flag_cleanup="Y"
elif [[ $subworkflow == "TESTING" ]]; then
	echo "testing"
else
	echo "CHOOSE CORRECT FLAG -s: DOWNLOAD BATCH ANALYZE REPORT CLEAN ALL"
	echo "YOU CHOOSE: $subworkflow"
	EXIT
fi

##########################################################
# Eval, source
#########################################################
source $(dirname "$0")/functions.sh
eval $(parse_yaml ${pipeline_config} "config_")

# date
today_date=$(date '+%Y-%m-%d')
today_date=`echo $today_date | sed "s/-//g"`
#########################################################
# Set dirs, files, args
#########################################################
# set dir
log_dir=$output_dir/logs
manifest_dir=$log_dir/manifests

tmp_dir=$output_dir/tmp
tmp_qc_dir=$tmp_dir/qc

analysis_dir=$output_dir/analysis
qc_dir=$analysis_dir/qc
fasta_dir=$analysis_dir/fasta
report_dir=$analysis_dir/reports
intermed_dir=$analysis_dir/intermed

# set files
merged_cecret=$intermed_dir/cecret_results.txt
merged_nextclade=$intermed_dir/nextclade_results.csv
merged_pangolin=$intermed_dir/lineage_report.csv
merged_fragment=$intermed_dir/fragment.txt
multiqc_log=$log_dir/multiqc_log.txt
fragement_plot=$intermed_dir/fragment_plot.png
final_nextclade=$intermed_dir/final_nextclade.txt
final_pangolin=$intermed_dir/final_pangolin.txt
final_results=$intermed_dir/final_cecret.csv
sample_id_file=$manifest_dir/sample_ids.txt

#########################################################
# handle versioning
#########################################################
# pull versions from config
pangolin_version=$(get_config_info $config_pangolin_version pangolin)
nextclade_version=$(get_config_info $config_nextclade_version nextclade)
cecret_version=$(get_config_info $config_cecret_version cecret)
primer_version=$(get_config_info $config_primer_version primer)
insert_version=$(get_config_info $config_insert_version insert)

if [[ "$pangolin_version" == "" ]] | [[ "$nextclade_version" == "" ]]; then
    echo "Choose the correct version of PANGOLIN/NEXTCLADE in $log_dir/config/config_pipeline.yaml"
    echo "PANGOLIN: $pangolin_version"
    echo "NEXTCLADE: $nextclade_version"
    exit
fi

# Update CECRET config dependent on user input
## update corrected software versions cecret config
update_config "pangolin:latest" "pangolin:$pangolin_version" $cecret_config
update_config "nextclade:latest" "nextclade:$nextclade_version" $cecret_config

## check reference files exist in reference dir, update reference files
# for each reference file find matching output in config_pipeline
# remove refence file name and leave reference value
# create full path to reference value
# check file existence
# escape / with \/ for sed replacement
# replace the cecret config file with the reference selected
reference_list=("reference_genome" "reference_gff")
for ref_file in ${reference_list[@]}; do
    ref_line=$(cat "${pipeline_config}" | grep $ref_file)
    ref_path=`echo $config_reference_dir/${ref_line/"$ref_file": /} | tr -d '"'`
	update_config_refs $ref_file $ref_path $cecret_config
done

ref_file="primer_bed"
ref_path=`echo $config_reference_dir/${primer_version/"$ref_file": /} | tr -d '"'`
update_config_refs $ref_file $ref_path $cecret_config

ref_file="amplicon_bed"
ref_path=`echo $config_reference_dir/${insert_version/"$ref_file": /} | tr -d '"'`
update_config_refs $ref_file $ref_path $cecret_config

#########################################################
# project variables
#########################################################
# set project shorthand
project_name=$(echo $project_name_full | cut -f1 -d "_" | cut -f1 -d " ")

# read in sample list
IFS=$'\n' read -d '' -r -a sample_list < $sample_id_file	

# create proj tmp dir to enable multiple projects to be run simultaneously
project_number=`$config_basespace_cmd list projects --filter-term="${project_name_full}" | sed -n '4 p' | awk '{split($0,a,"|"); print a[3]}' | sed 's/ //g'`

# set command 
if [[ $resume == "Y" ]]; then
	analysis_cmd=`echo $config_cecret_cmd -resume`
else
	analysis_cmd=`echo $config_cecret_cmd`
fi

#############################################################################################
# LOG INFO TO CONFIG
#############################################################################################

message_cmd_log "------------------------------------------------------------------------"
message_cmd_log "--- STARTING ANALYSIS ---"

message_cmd_log "Starting time: `date`"
message_cmd_log "Starting space: `df . | sed -n '2 p' | awk '{print $5}'`"

#############################################################################################
# Batching
#############################################################################################
# All project ID's download from BASESPACE will be processed into batches
# Batch count depends on user input from pipeline_config.yaml
if [[ $flag_batch == "Y" ]]; then
	message_cmd_log "------------------------------------------------------------------------"
	message_cmd_log "--BATCHING"
	message_cmd_log "------------------------------------------------------------------------"

	#read in text file with all project id's
	IFS=$'\n' read -d '' -r -a raw_list < config/sample_ids.txt
	if [[ -f $sample_id_file ]];then rm $sample_id_file; fi
	for f in ${raw_list[@]}; do
		# if [[ $f != "specimen_id" ]]; then 	echo $f-$project_name >> $sample_id_file; fi
		if [[ $f != "specimen_id" ]]; then 	echo $f >> $sample_id_file; fi
	done
	IFS=$'\n' read -d '' -r -a sample_list < $sample_id_file

	# break project into batches of N = batch_limit create manifests for each
	sample_count=1
	batch_count=0
	for sample_id in ${sample_list[@]}; do
        
		#if the sample count is 1 then create new batch
	    if [[ "$sample_count" -eq 1 ]]; then
        	batch_count=$((batch_count+1))
	
        	#remove previous versions of batch log
        	if [[ "$batch_count" -gt 9 ]]; then batch_name=$batch_count; else batch_name=0${batch_count}; fi
			
			#remove previous versions of batch log
			batch_manifest=$log_dir/manifests/batch_${batch_name}.txt
            if [[ -f $batch_manifest ]]; then rm $batch_manifest; fi

	        # remove previous versions of samplesheet
			samplesheet=$log_dir/manifests/samplesheet_${batch_name}.csv	
			if [[ -f $samplesheet ]]; then rm $samplesheet; fi
        		
			# create samplesheet
			echo "sample,fastq_1,fastq_2" > $log_dir/manifests/samplesheet_${batch_name}.csv
			
			# create batch dirs
			fastq_batch_dir=$tmp_dir/batch_$batch_name/rawdata
			tmp_batch_dir=$tmp_dir/batch_$batch_name/download
			pipeline_batch_dir=$tmp_dir/batch_$batch_name/pipeline
			makeDirs $fastq_batch_dir
			makeDirs $tmp_batch_dir
			makeDirs $pipeline_batch_dir
			makeDirs $pipeline_batch_dir/$project_number
        fi
            
		#echo sample id to the batch
	   	echo ${sample_id} >> $batch_manifest                
		
		# prepare samplesheet
        echo "${sample_id},$fastq_batch_dir/$sample_id.R1.fastq.gz,$fastq_batch_dir/$sample_id.R2.fastq.gz">>$samplesheet

    	#increase sample counter
    	((sample_count+=1))
            
    	#reset counter when equal to batch_limit
    	if [[ "$sample_count" -gt "$config_batch_limit" ]]; then sample_count=1; fi

		# set final count
		sample_final=`cat $sample_id_file | wc -l`
	done

	if [[ "$testing" == "Y" ]]; then
		echo "----creating testing batch file"

		# create save dir for old manifests
		mkdir -p $log_dir/manifests/save
		mv $log_dir/manifests/b*.txt $log_dir/manifests/save
		batch_manifest=$log_dir/manifests/save/batch_01.txt

		# grab the first two samples and last two samples, save as new batches
		head -2 $batch_manifest > $log_dir/manifests/batch_01.txt
		tail -2 $batch_manifest > $log_dir/manifests/batch_02.txt

		# fix samplesheet
		mv $log_dir/manifests/samplesheet* $log_dir/manifests/save
		samplesheet=$log_dir/manifests/save/samplesheet_01.csv
		head -3 $samplesheet > $log_dir/manifests/samplesheet_01.csv
		head -1 $samplesheet > $log_dir/manifests/samplesheet_02.csv
		tail -2 $samplesheet >> $log_dir/manifests/samplesheet_02.csv
		sed -i "s/batch_1/batch_2/g" $log_dir/manifests/samplesheet_02.csv

		# set new batch count
		batch_count=2
		sample_final=4
	fi

	#log
	message_cmd_log "----A total of $sample_final samples will be processed in $batch_count batches, with a maximum of $config_batch_limit samples per batch"
fi

#############################################################################################
# Project Downloads
#############################################################################################	
if [[ $flag_download == "Y" ]]; then
	message_cmd_log "------------------------------------------------------------------------"
	message_cmd_log "--DOWNLOADING"
	message_cmd_log "------------------------------------------------------------------------"

	# determine number of batches
	batch_count=`ls $log_dir/manifests/batch* | rev | cut -d'/' -f 1 | rev | tail -1 | cut -f2 -d"0" | cut -f1 -d"."`
	batch_min=`ls $log_dir/manifests/batch* | rev | cut -d'/' -f 1 | rev | head -1 | cut -f2 -d"0" | cut -f1 -d"."`

	# check that access to the projectID is available before attempting to download
	if [ -z "$project_number" ]; then
		echo "The project id was not found from $project_name_full. Review available project names below and try again"
		$config_basespace_cmd list projects --filter-term="${project_name_full}"
		exit
	fi

	# output start message
	message_cmd_log "--This may take a few minutes to begin)"
	message_cmd_log "---Starting time: `date`"
	
	# download full zips
	$config_basespace_cmd download project --quiet -i $project_number -o $tmp_dir --extension=zip
	echo $config_basespace_cmd download project --quiet -i $project_number -o $tmp_dir --extension=zip

	# for each batch
	for (( batch_id=$batch_min; batch_id<=$batch_count; batch_id++ )); do

        # set batch name
		if [[ "$batch_id" -gt 9 ]]; then batch_name=$batch_id; else batch_name=0${batch_id}; fi
		
		# set batch manifest, dirs
		batch_manifest=$manifest_dir/batch_${batch_name}.txt
		fastq_batch_dir=$tmp_dir/batch_$batch_name/rawdata
		tmp_batch_dir=$tmp_dir/batch_$batch_name/download
		samplesheet=$manifest_dir/samplesheet_${batch_name}.csv	
		
		# read text file
		IFS=$'\n' read -d '' -r -a batch_list < $batch_manifest

		for sample_id in ${batch_list[@]}; do
			$config_basespace_cmd download biosample --quiet -n "${sample_id}" -o $tmp_batch_dir
			
			# unzip analysis file downloaded from DRAGEN to sample tmp dir - used in QC
			# move needed files to general tmp dir
			zip=`ls $tmp_dir/${sample_id}*/*.zip | head -1 | sed "s/_SARS//g"`
			if [[ ! -d $tmp_dir/${sample_id} ]]; then mkdir -p $tmp_dir/${sample_id}; fi
			if [[ $zip != "" ]]; then 
				unzip -o -q ${zip} -d $tmp_dir/${sample_id}
				mv $tmp_dir/${sample_id}/ma/* $tmp_qc_dir/			
			fi
		done

		#move to final dir, clean
		mv $tmp_batch_dir/*/*gz $fastq_batch_dir
		for f in $fastq_batch_dir/*gz; do
			new=$(clean_file_names $f)
			if [[ $f != $new ]]; then mv $f $new; fi
		done
		rm $tmp_qc_dir/dragen* $tmp_qc_dir/st*
		for f in $tmp_qc_dir/*; do
			new=$(clean_file_names $f)
			if [[ $f != $new ]]; then mv $f $new; fi
		done
		clean_file_insides $samplesheet
		clean_file_insides $batch_manifest
		rm -rf $tmp_batch_dir
	done

	# clean dirs
	rm -rf $tmp_dir/2* $tmp_dir/S* $tmp_dir/O*
	
	# output end message
	message_cmd_log "---Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
fi

#############################################################################################
# Analysis
#############################################################################################
if [[ $flag_analysis == "Y" ]]; then
	message_cmd_log "------------------------------------------------------------------------"
	message_cmd_log "--- CONFIG INFORMATION ---"
	message_cmd_log "Cecret config: $cecret_config"
	message_cmd_log "Sequence run date: $proj_date"
	message_cmd_log "Analysis date: `date`"
	message_cmd_log "Pangolin version: $pangolin_version"
	message_cmd_log "Nexclade version: $nextclade_version"
	message_cmd_log "Cecret version: $cecret_version"
	message_cmd_log "Amplicon version: $primer_version"
	message_cmd_log "Insert version: $insert_version"
	message_cmd_log "------------------------------------------------------------------------"

	# determine number of batches
	batch_count=`ls $log_dir/manifests/batch* | rev | cut -d'/' -f 1 | rev | tail -1 | cut -f2 -d"0" | cut -f1 -d"."`
	batch_min=`ls $log_dir/manifests/batch* | rev | cut -d'/' -f 1 | rev | head -1 | cut -f2 -d"0" | cut -f1 -d"."`


	#for each batch
	for (( batch_id=$batch_min; batch_id<=$batch_count; batch_id++ )); do

        # set batch name
		if [[ "$batch_id" -gt 9 ]]; then batch_name=$batch_id; else batch_name=0${batch_id}; fi
		
		# set batch manifest, dirs
		batch_manifest=$log_dir/manifests/batch_${batch_name}.txt
		fastq_batch_dir=$tmp_dir/batch_$batch_name/rawdata
		pipeline_batch_dir=$tmp_dir/batch_$batch_name/pipeline
		samplesheet=$manifest_dir/samplesheet_$batch_name.csv

		# move to project dir
		cd $pipeline_batch_dir/$project_number
		
		# read text file
		IFS=$'\n' read -d '' -r -a sample_list < $batch_manifest
		n_samples=`wc -l < $batch_manifest`
		message_cmd_log "----Batch_$batch_id ($n_samples samples)"

		# cecret command
		config_cecret_cmd_line="$analysis_cmd --sample_sheet $samplesheet --reads_type paired --outdir $pipeline_batch_dir"
		echo $config_cecret_cmd_line

		if [[ $resume == "Y" ]]; then
			message_cmd_log "------------------------------------------------------------------------"
			message_cmd_log "--RESUMING"
			message_cmd_log "------------------------------------------------------------------------"


			# deploy cecret
			$config_cecret_cmd_line
		else
			message_cmd_log "------------------------------------------------------------------------"
			message_cmd_log "--CECRET"
			message_cmd_log "------------------------------------------------------------------------"
			message_cmd_log "-------Starting time: `date`"
			message_cmd_log "-------Starting space: `df . | sed -n '2 p' | awk '{print $5}'`"
		
			# copy config
			cp $cecret_config $pipeline_batch_dir

			# deploy cecret
			$config_cecret_cmd_line
		fi
		
		#############################################################################################
		# Reporting
		#############################################################################################	
		if [[ -f $pipeline_batch_dir/cecret_results.txt ]]; then
			message_cmd_log "---- The pipeline completed batch #$batch_name at `date` "
			message_cmd_log "--------------------------------------------------------"

			# add to  master cecret results
			cat $pipeline_batch_dir/cecret_results.txt >> $merged_cecret

			# add to master nextclade results
			cat $pipeline_batch_dir/nextclade/nextclade.csv >> $merged_nextclade

			# add to master pangolin results
			cat $pipeline_batch_dir/pangolin/lineage_report.csv >> $merged_pangolin

			# If QC report is being created, generate stats on fragment length
			for f in $pipeline_batch_dir/samtools_stats/*.stats.txt; do
				frag_length=`cat $f | grep "average length" | awk '{print $4}'`
				sampleid=`echo $f | rev | cut -f1 -d "/" | rev | cut -f1 -d "."`
				echo -e "${sampleid}\t${frag_length}\t${batch_id}" >> $merged_fragment
			done

			# move FASTQC files
			mv $pipeline_batch_dir/fastqc/* $tmp_qc_dir
			
			# move FASTA files
			mv $pipeline_batch_dir/consensus/*fa $fasta_dir
			for f in $fasta_dir/*; do
				new=`echo $f | sed "s/.consensus//g"`
				if [[ $f != $new ]]; then mv $f $new; fi
			done

			# move logs
			cp $pipeline_batch_dir/$project_number/* $log_dir/pipeline/
			mv $batch_manifest $manifest_dir/complete

			#remove intermediate files
			if [[ $flag_cleanup == "Y" ]]; then
				sudo rm -r --force $tmp_dir/batch_$batch_name
			fi
		else
			message_cmd_log "---- The pipeline failed `date`"
			message_cmd_log "------Missing file: $pipeline_batch_dir/cecret_results.txt"
			message_cmd_log "--------------------------------------------------------"
			exit
		fi
	done
fi

#############################################################################################
# Create final reports
#############################################################################################
if [[ $flag_report == "Y" ]]; then
	# log
	message_cmd_log "------------------------------------------------------------------------"
	message_cmd_log "--REPORT"
	message_cmd_log "------------------------------------------------------------------------"
	message_cmd_log "---Starting time: `date`"
	message_cmd_log "---Starting space: `df . | sed -n '2 p' | awk '{print $5}'`"

	# run multiQC
	## -d -dd 1 adds dir name to sample name
	multiqc -f -v \
	-c $multiqc_config \
	$tmp_qc_dir \
	--no-ansi \
	-o $tmp_dir 2>&1 | tee -a $multiqc_log
	mv $tmp_dir/multiqc_report.html $report_dir

	# create fragment plot
	python_cmd=`python3 $config_frag_plot_script $merged_fragment $fragement_plot`
	$python_cmd
	
	# merge batch outputs into intermediate files
	# join contents of nextclade and pangolin into final output table	
	awk -F';' -vcols=seqName,clade,aaSubstitutions '(NR==1){n=split(cols,cs,",");for(c=1;c<=n;c++){for(i=1;i<=NF;i++)if($(i)==cs[c])ci[c]=i}}{for(i=1;i<=n;i++)printf "%s" FS,$(ci[i]);printf "\n"}' $merged_nextclade | sed -s "s/Consensus_//g" | sed -s "s/.consensus_threshold_0.6_quality_20//g"  | grep -v "seqName" | awk -F";" -v q="\"" '{print $1","$2","q$3q }' | grep -v "seqName" >> $final_nextclade

	# from pangloin: sampleid, lineage, qc_status
	awk -F',' -vcols=taxon,qc_status,lineage,scorpio_call,pangolin_version '(NR==1){n=split(cols,cs,",");for(c=1;c<=n;c++){for(i=1;i<=NF;i++)if($(i)==cs[c])ci[c]=i}}{for(i=1;i<=n;i++)printf "%s" FS,$(ci[i]);printf "\n"}' $merged_pangolin | sed -s "s/Consensus_//g" | sed -s "s/.consensus_threshold_0.6_quality_20//g" | sed 's/.$//' | grep -v "taxon" >> $final_pangolin	
	
	# create final results
	echo "sample_id,pango_status,pangolin_lineage,pangolin_scorpio,pangolin_version,nextclade_clade,aa_substitutions" > $final_results
	join <(sort $final_pangolin) <(sort $final_nextclade) -t $',' >> $final_results

	# create R reports
	script_list=( $report_dir/COVID_Report_nofails.Rmd $report_dir/COVID_Report.Rmd )
	for f in ${script_list[@]}; do
		sed -i "s/REP_TODAY/$today_date/g" $f
		sed -i "s/REP_ID/$project_name/g" $f
		sed -i "s/REP_DATE/$proj_date/g" $f
		sed -i "s/REP_ADATE/$today_date/g" $f
		sed -i "s/REP_PANGO/$pangolin_version/g" $f
		sed -i "s/REP_NC/$nextclade_version/g" $f
		sed -i "s/REP_CECRET/$cecret_version/g" $f
		sed -i "s/REP_PRIME/$primer_version/g" $f
		sed -i "s/REP_INSERT/$insert_version/g" $f
	done

	# complete pipeline
	if [[ -f $final_results ]]; then
		if [[ $flag_cleanup == "Y" ]]; then sudo rm -r --force $tmp_dir; fi

		message_cmd_log "Ending time: `date`"
		message_cmd_log "Ending space: `df . | sed -n '2 p' | awk '{print $5}'`"
		message_cmd_log "--- CECRET PIPELINE COMPLETE ---"
		message_cmd_log "------------------------------------------------------------------------"
	else
		echo "FAIL: Missing $final_results"
	fi
fi