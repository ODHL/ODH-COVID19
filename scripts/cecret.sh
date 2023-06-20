#########################################################
# ARGS
#########################################################
output_dir=$1
project_name_full=$2
pipeline_config=$3
cecret_config=$4
multiqc_config=$5
date_stamp=$6
pipeline_log=$7
flag_testing=${8}

#########################################################
# Pipeline controls
########################################################
# three options for testing 
## N = run full run
## T = run 2 batches, 4 samples
## U = run user generated manifest
flag_download="Y"
flag_batch="Y"
flag_cecret="Y"
flag_cleanup="N"
flag_reporting="Y"

##########################################################
# Eval, source
#########################################################
source $(dirname "$0")/functions.sh
eval $(parse_yaml ${pipeline_config} "config_")

#########################################################
# Set dirs, files, args
#########################################################
final_results=$analysis_dir/final_results_$date_stamp.csv
pangolin_id=$config_pangolin_version
nextclade_id=$config_nextclade_version
cecret_id=$config_cecret_version
primer_id=$config_primer_version
insert_id=$config_insert_version

# set dir
log_dir=$output_dir/logs
cecret_dir=$output_dir/cecret
fastq_dir=$output_dir/fastq

analysis_dir=$output_dir/analysis
intermed_dir=$analysis_dir/intermed
fasta_dir=$analysis_dir/fasta

qc_dir=$output_dir/qc
qcreport_dir=$qc_dir/covid19_qcreport

tmp_dir=$output_dir/tmp
fastqc_dir=$tmp_dir/fastqc

# set files
merged_samples=$log_dir/completed_samples.txt
merged_cecret=$intermed_dir/cecret_results.txt
merged_nextclade=$intermed_dir/nextclade_results.csv
merged_pangolin=$intermed_dir/lineage_report.csv
merged_summary=$intermed_dir/cecret_summary.csv
merged_fragment=$qc_dir/fragment.txt

sample_id_file=$log_dir/sample_ids.txt

fragement_plot=$qc_dir/fragment_plot.png
multiqc_log=$log_dir/multiqc_log.txt

final_nextclade=$intermed_dir/final_nextclade.txt
final_pangolin=$intermed_dir/final_pangolin.txt
final_results=$analysis_dir/final_results_$date_stamp.csv

# Convert user selected numbers to complete software names
pangolin_version=`cat config/software_versions.txt | awk '$1 ~ /pangolin/' | awk -v pid="$pangolin_id" '$2 ~ pid' | awk '{ print $3 }'`
nextclade_version=`cat config/software_versions.txt | awk '$1 ~ /nextclade/' | awk -v pid="$nextclade_id" '$2 ~ pid' | awk '{ print $3 }'`
cecret_version=`cat config/software_versions.txt | awk '$1 ~ /cecret/' | awk -v pid="$cecret_id" '$2 ~ pid' | awk '{ print $3 }'`
primer_version=`cat config/software_versions.txt | awk '$1 ~ /primer/' | awk -v pid="$primer_id" '$2 ~ pid' | awk '{ print $3 }'`
insert_version=`cat config/software_versions.txt | awk '$1 ~ /insert/' | awk -v pid="$insert_id" '$2 ~ pid' | awk '{ print $3 }'`
if [[ "$pangolin_version" == "" ]] | [[ "$nextclade_version" == "" ]]; then
    echo "Choose the correct version of PANGOLIN/NEXTCLADE in /project/logs/config_pipeline.yaml"
    echo "PANGOLIN: $pangolin_version"
    echo "NEXTCLADE: $nextclade_version"
    exit
fi

# set cmd
cecret_cmd=$config_cecret_cmd
fragment_plots_script=$config_frag_plot_script
#############################################################################################
# CECRET UPDATES
#############################################################################################
# Update CECRET config dependent on user input
## update corrected software versions cecret config
old_cmd="pangolin:latest'"
new_cmd="pangolin:$pangolin_version'"
sed -i "s/$old_cmd/$new_cmd/" $cecret_config

old_cmd="nextclade:latest'"
new_cmd="nextclade:$nextclade_version'"
sed -i "s/$old_cmd/$new_cmd/" $cecret_config

## check reference files exist in reference dir, update reference files
# for each reference file find matching output in config_pipeline
# remove refence file name and leave reference value
# create full path to reference value
# check file existence
# escape / with \/ for sed replacement
# replace the cecret config file with the reference selected
reference_list=("reference_genome" "gff_file")
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

ref_file="primer_bed"
ref_path=`echo $config_reference_dir/${primer_version/"$ref_file": /} | tr -d '"'`
old_cmd="params.$ref_file = \"TBD\""
new_cmd="params.$ref_file = \"$ref_path\""
new_cmd=$(echo $new_cmd | sed 's/\//\\\//g')
sed -i "s/$old_cmd/$new_cmd/" $cecret_config

ref_file="amplicon_bed"
ref_path=`echo $config_reference_dir/${insert_version/"$ref_file": /} | tr -d '"'`
old_cmd="params.$ref_file = \"TBD\""
new_cmd="params.$ref_file = \"$ref_path\""
new_cmd=$(echo $new_cmd | sed 's/\//\\\//g')
sed -i "s/$old_cmd/$new_cmd/" $cecret_config

#############################################################################################
# LOG INFO TO CONFIG
#############################################################################################
message_cmd_log "------------------------------------------------------------------------"
message_cmd_log "--- CONFIG INFORMATION ---"
message_cmd_log "Cecret config: $cecret_config"
message_cmd_log "Sequence run date: $date_stamp"
message_cmd_log "Analysis date: `date`"
message_cmd_log "Pangolin version: $pangolin_version"
message_cmd_log "Nexclade version: $nextclade_version"
message_cmd_log "Cecret version: $cecret_version"
message_cmd_log "Amplicon version: $primer_version"
message_cmd_log "Insert version: $insert_version"

cat "$cecret_config" | grep "params.reference_genome" >> $pipeline_log
cat "$cecret_config" | grep "params.gff_file" >> $pipeline_log
cat "$cecret_config" | grep "params.primer_bed" >> $pipeline_log
cat "$cecret_config" | grep "params.amplicon_bed" >> $pipeline_log

message_cmd_log "------------------------------------------------------------------------"
message_cmd_log "--- STARTING CECRET ANALYSIS ---"

echo "Starting time: `date`" >> $pipeline_log
echo "Starting space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log

#############################################################################################
# Project Downloads
#############################################################################################	
if [[ $flag_download == "Y" ]]; then
	echo "--Downloading sample data"

	#get project id
	project_id=`$config_basespace_cmd list projects --filter-term="${project_name_full}" | sed -n '4 p' | awk '{split($0,a,"|"); print a[3]}' | sed 's/ //g'`
	
	# if the project name does not match completely with basespace an ID number will not be found
	# display all available ID's to re-run project	
	if [ -z "$project_id" ]; then
		echo "The project id was not found from $project_name_full. Review available project names below and try again"
		exit
	fi

	# output start message
	message_cmd_log "--Downloading analysis files (this may take a few minutes to begin)"
	echo "---Starting time: `date`" >> $pipeline_log
	
	# run basespace download command
	$config_basespace_cmd download project --quiet -i $project_id -o "$tmp_dir" --extension=zip
	echo $config_basespace_cmd list projects --filter-term="${project_name_full}" 

	# output end message
	echo "---Ending time: `date`" >> $pipeline_log
	echo "---Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	
	# remove scrubbed files, as they are zipped FASTQS and will be downloaded in batches later
	rm -rf $tmp_dir/Scrubbed*	
fi

#############################################################################################
# Batching
#############################################################################################
if [[ $flag_batch == "Y" ]]; then
	#break project into batches of N = batch_limit set above, create manifests for each
	sample_count=1
	batch_count=0

	# All project ID's download from BASESPACE will be processed into batches
	# Batch count depends on user input from pipeline_config.yaml
	# If a partial run is being performed, a batch file is required as user input
	echo "--Creating batch files"
	if [[ "$flag_testing" != "U" ]]; then
		echo "----without user input"

		# create sample_id file - grab all files in dir, split by _, exclude noro- file names
		## pulls name after _
		# ls $tmp_dir | grep "ds"| cut -f2 -d "_" | grep -v "noro.*" > $sample_id_file
		## pulls name before _
		ls $tmp_dir | grep "ds"| cut -f1 -d "_" | grep -v "noro.*" > $sample_id_file

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
    		if [[ "$sample_count" -gt "$config_batch_limit" ]]; then sample_count=1; fi
		done
	
		#gather final count
		sample_count=${#sample_list[@]}
    	batch_min=1
	elif [[ "$flag_testing" == "U" ]]; then
		echo "----with user input"

		# Partial runs allow the user to submit pre-defined batch files with samples
		# Determine how many batch files are to be used and total number of samples within files
		batch_min=`ls $log_dir/batch* | cut -f2 -d"_" | cut -f1 -d "." | sort | head -n1`
		batch_count=`ls $log_dir/batch* | cut -f2 -d"_" | cut -f1 -d "." | sort | tail -n1`
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

	if [[ "$flag_testing" == "T" ]]; then
		echo "----creating testing batch file"

		# create save dir for new batches
		mkdir -p $log_dir/save
		batch_manifest=$log_dir/batch_01.txt

		# grab the first two samples and last two samples, save as new batches
		head -2 $batch_manifest > $log_dir/save/batch_01.txt
		tail -2 $batch_manifest > $log_dir/save/batch_02.txt

		# remove old  manifests
		rm $log_dir/batch_*

		# replace update manifests and cleanup
		mv $log_dir/save/* $log_dir
		sudo rm -r $log_dir/save

		# set new batch count
		batch_count=2
		sample_count=4
	fi

	#log
	message_cmd_log "--A total of $sample_count samples will be processed in $batch_count batches, with a maximum of $config_batch_limit samples per batch"

	#merge all batched outputs
	touch $merged_samples
	touch $merged_cecret
	touch $merged_nextclade
	touch $merged_pangolin
	touch $merged_summary
	touch $merged_fragment
fi

#############################################################################################
# Analysis
#############################################################################################
if [[ $flag_cecret == "Y" ]]; then
	#log
	message_cmd_log "--Processing batches:"

	# determine number of batches
	batch_count=`ls $log_dir/batch* | wc -l`
	batch_min=1

	#for each batch
	for (( batch_id=$batch_min; batch_id<=$batch_count; batch_id++ )); do

		# set batch name
		if [[ "$batch_id" -gt 9 ]]; then batch_name=$batch_id; else batch_name=0${batch_id}; fi
		
		#set batch manifest, dirs
		batch_manifest=$log_dir/batch_${batch_name}.txt
		fastq_batch_dir=$fastq_dir/batch_$batch_id
		cecret_batch_dir=$cecret_dir/batch_$batch_id
		if [[ ! -d $fastq_batch_dir ]]; then mkdir $fastq_batch_dir; fi
		if [[ ! -d $cecret_batch_dir ]]; then mkdir $cecret_batch_dir; fi

		#read text file
		IFS=$'\n' read -d '' -r -a sample_list < $batch_manifest

		# print number of lines in file without file name "<"
		n_samples=`wc -l < $batch_manifest`
		echo "----Batch_$batch_id ($n_samples samples)"
		echo "----Batch_$batch_id ($n_samples samples)" >> $pipeline_log

		#run per sample, download files
		for sample_id in ${sample_list[@]}; do
			$config_basespace_cmd download biosample --quiet -n "${sample_id}" -o $fastq_dir

	    	# move files to batch fasta dir
        	#rm -r $fastq_dir/*L001*
    		mv $fastq_dir/*${sample_id}*/*fastq.gz $fastq_batch_dir
    
    		# If generating a QC report, BASESPACE files need to be unzipped
        	# and selected files moved for downstream analysis
        	# make sample tmp_dir: tmp_dir/sample_id
    		if [[ ! -d "$tmp_dir/${sample_id}" ]]; then mkdir $tmp_dir/${sample_id}; fi
			
			#unzip analysis file downloaded from DRAGEN to sample tmp dir - used in QC
			unzip -o -q $tmp_dir/${sample_id}_[0-9]*/*_all_output_files.zip -d $tmp_dir/${sample_id}

	    	#move needed files to general tmp dir
			mv $tmp_dir/${sample_id}/ma/* $tmp_dir/unzipped
    	
            #remove sample tmp dir, downloaded proj dir
        	rm -r --force $tmp_dir/${sample_id}
    
    		# remove downloaded tmp dir
	        rm -r --force $tmp_dir/${sample_id}_[0-9]*/
		done

		#log
		message_cmd_log "------CECRET"
		echo "-------Starting time: `date`" >> $pipeline_log
    	echo "-------Starting space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	
		# changes in software adds project name to some sample_ids. In order to ensure consistency throughout naming and for downstream
        # uploading, project name should be removed.
    	dir_list=($fastq_batch_dir/*)
    	for dir_id in ${dir_list[@]}; do
            for f in "$dir_id"; do
                # remove projectid from header
            	sed -i "s/-$project_name_full//g" $f

                # rename files
            	new_id=`echo $f | awk -v p_id=-$project_name_full '{ gsub(p_id,"",$1) ; print }'`
                if [[ $f != $new_id ]]; then mv $f $new_id; fi
        	done
    	done

		#create proj tmp dir to enable multiple projects to be run simultaneously
		if [[ ! -d $project_id ]]; then mkdir $project_id; fi
		cd $project_id
		
		cecret_cmd_line="$cecret_cmd --reads $fastq_batch_dir --reads_type paired -c $cecret_config --outdir $cecret_batch_dir"
		echo $cecret_cmd_line
		$cecret_cmd_line

		# log
    	echo "-------Ending time: `date`" >> $pipeline_log
		echo "-------Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log

		#############################################################################################
		# Reporting
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
		cat $cecret_batch_dir/combined_summary.csv >> $merged_summary

		# If QC report is being created, generate stats on fragment length
        for f in $cecret_batch_dir/samtools_stats/*.stats.txt; do
    		frag_length=`cat $f | grep "average length" | awk '{print $4}'`
        	file_name=`echo $f | rev | cut -f1 -d "/" | rev`
        	file_name=${file_name%.stats*}
	        echo -e "${file_name}\t${frag_length}\t${batch_id}" >> $merged_fragment
    	done

		# move FASTQC files
		mv $cecret_batch_dir/fastqc/* $fastqc_dir
		
		# move FASTA files
		mv $cecret_batch_dir/consensus/* $fasta_dir/not_uploaded

		#remove intermediate files
		if [[ $flag_cleanup == "Y" ]]; then
			sudo rm -r --force work
			sudo rm -r --force $cecret_batch_dir
			sudo rm -r --force $fastq_batch_dir
			cd ..
			sudo rm -r $project_id
		fi
	done
fi

#############################################################################################
# Create final reports
#############################################################################################
if [[ $flag_reporting == "Y" ]]; then
	#log
	message_cmd_log "--Creating QC Report"
	echo "---Starting time: `date`" >> $pipeline_log
	echo "---Starting space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log

    # uploading, project name should be removed.
    dir_list=($tmp_dir/unzipped/*)
    for dir_id in ${dir_list[@]}; do
        for f in "$dir_id"; do
            # remove projectid from header
            sed -i "s/-$project_name_full//g" $f

            # rename files
            new_id=`echo $f | awk -v p_id=-$project_name_full '{ gsub(p_id,"",$1) ; print }'`
            if [[ $f != $new_id ]]; then mv $f $new_id; fi
        done
    done

	#-d -dd 1 adds dir name to sample name
	multiqc -f -v \
	-c $multiqc_config \
	$fastqc_dir \
	$tmp_dir/unzipped \
	-o $qcreport_dir 2>&1 | tee -a $multiqc_log
	
	#cleanup
	mv $qcreport_dir/*html $qc_dir
	rm -r $qcreport_dir

	#create fragment plot
	echo "python3 $fragment_plots_script $merged_fragment $fragement_plot"
	
	# merge batch outputs into intermediate files
	# join contents of nextclade and pangolin into final output table	
	awk -F';' -vcols=seqName,clade,aaSubstitutions '(NR==1){n=split(cols,cs,",");for(c=1;c<=n;c++){for(i=1;i<=NF;i++)if($(i)==cs[c])ci[c]=i}}{for(i=1;i<=n;i++)printf "%s" FS,$(ci[i]);printf "\n"}' $merged_nextclade | sed -s "s/Consensus_//g" | sed -s "s/.consensus_threshold_0.6_quality_20//g"  | grep -v "seqName" | awk -F";" -v q="\"" '{print $1","$2","q$3q }' | grep -v "seqName" >> $final_nextclade

	# from pangloin: sampleid, lineage, qc_status
	awk -F',' -vcols=taxon,qc_status,lineage,scorpio_call,pangolin_version '(NR==1){n=split(cols,cs,",");for(c=1;c<=n;c++){for(i=1;i<=NF;i++)if($(i)==cs[c])ci[c]=i}}{for(i=1;i<=n;i++)printf "%s" FS,$(ci[i]);printf "\n"}' $merged_pangolin | sed -s "s/Consensus_//g" | sed -s "s/.consensus_threshold_0.6_quality_20//g" | sed 's/.$//' | grep -v "taxon" >> $final_pangolin	
	
	# create final results
	echo "sample_id,pango_status,pangolin_lineage,pangolin_scorpio,pangolin_version,nextclade_clade,aa_substitutions" > $final_results
	join <(sort $final_pangolin) <(sort $final_nextclade) -t $',' >> $final_results

	if [[ $flag_cleanup == "Y" ]]; then
		#remove all proj files
		rm -r --force $tmp_dir
		rm -r --force $cecret_dir
		rm -r --force $fastq_dir
		rm -r --force $fastqc_dir
		rm $fasta_dir/*/*txt
	fi

	echo "Ending time: `date`" >> $pipeline_log
	echo "Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	message_cmd_log "--- CECRET PIPELINE COMPLETE ---"
	message_cmd_log "------------------------------------------------------------------------"
fi