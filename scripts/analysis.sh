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
environment=${11}

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
if [[ $subworkflow == "DOWNLOAD" ]]; then
	flag_download="Y"
elif [[ $subworkflow == "BATCH" ]]; then
    flag_batch="Y"
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
    flag_cleanup="N"
elif [[ $subworkflow == "lala" ]]; then
	flag_download="N"
    flag_batch="N"
    flag_analysis="N"
    flag_report="N"
    flag_cleanup="N"
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

# set command
var="config_cecret_cmd_$environment"; cecret_cmd=${!var}

# set scripts
var="config_frag_plot_script_$environment"; fragment_plots_script=${!var}

# date
today_date=$(date '+%Y-%m-%d')
#########################################################
# Set dirs, files, args
#########################################################
# set dir
log_dir=$output_dir/logs
pipeline_dir=$output_dir/pipeline
rawdata_dir=$output_dir/rawdata

analysis_dir=$output_dir/analysis
intermed_dir=$analysis_dir/intermed
fasta_dir=$analysis_dir/fasta
qc_dir=$analysis_dir/qc
qcreport_dir=$qc_dir/covid19_qcreport

tmp_dir=$output_dir/tmp
fastqc_dir=$tmp_dir/fastqc

# set files
merged_cecret=$intermed_dir/cecret_results.txt
merged_nextclade=$intermed_dir/nextclade_results.csv
merged_pangolin=$intermed_dir/lineage_report.csv
merged_fragment=$qc_dir/fragment.txt

sample_id_file=$log_dir/manifests/sample_ids.txt

fragement_plot=$qc_dir/fragment_plot.png
multiqc_log=$log_dir/multiqc_log.txt

final_nextclade=$intermed_dir/final_nextclade.txt
final_pangolin=$intermed_dir/final_pangolin.txt
final_results=$intermed_dir/final_cecret.csv

# set project shorthand
project_name=$(echo $project_name_full | cut -f1 -d "_" | cut -f1 -d " ")
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
    echo "Choose the correct version of PANGOLIN/NEXTCLADE in /logs/config/config_pipeline.yaml"
    echo "PANGOLIN: $pangolin_version"
    echo "NEXTCLADE: $nextclade_version"
    exit
fi

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
var="config_reference_dir_$environment"; config_reference_dir=${!var}
reference_list=("reference_genome" "reference_gff")
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
message_cmd_log "Sequence run date: $proj_date"
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
message_cmd_log "--- STARTING ANALYSIS ---"

echo "Starting time: `date`" >> $pipeline_log
echo "Starting space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log

#############################################################################################
# Project Downloads
#############################################################################################	
var="config_basespace_cmd_$environment"; config_basespace_cmd=${!var}
if [[ $flag_download == "Y" ]]; then
	echo "--Downloading sample data"

	#get project id
	project_number=`$config_basespace_cmd list projects --filter-term="${project_name_full}" | sed -n '4 p' | awk '{split($0,a,"|"); print a[3]}' | sed 's/ //g'`
	echo $config_basespace_cmd list projects --filter-term="${project_name_full}"

	# if the project name does not match completely with basespace an ID number will not be found
	# display all available ID's to re-run project	
	if [ -z "$project_number" ]; then
		echo "The project id was not found from $project_name_full. Review available project names below and try again"
		exit
	fi

	# output start message
	message_cmd_log "--Downloading analysis files (this may take a few minutes to begin)"
	echo "---Starting time: `date`" >> $pipeline_log
	
	# run basespace download command
	echo $config_basespace_cmd download project --quiet -i $project_number -o "$tmp_dir" --extension=zip
	$config_basespace_cmd download project --quiet -i $project_number -o "$tmp_dir" --extension=zip

	# output end message
	echo "---Ending time: `date`" >> $pipeline_log
	echo "---Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	
	# remove scrubbed files, as they are zipped FASTQS and will be downloaded in batches later
	rm -rf $tmp_dir/Scrubbed*	
fi

#############################################################################################
# Batching
#############################################################################################
# All project ID's download from BASESPACE will be processed into batches
# Batch count depends on user input from pipeline_config.yaml
if [[ $flag_batch == "Y" ]]; then
	echo "--Creating batch files"

	# create sampleID file
	cd $tmp_dir
	if [[ -f tmp.txt ]]; then rm tmp.txt; fi
	for f in *ds*/*; do
		new=`echo $f  | sed "s/_[0-9].*//g"`
		echo "$new" | cut -f2 -d"/" >> tmp.txt
	done
	cat tmp.txt | uniq > $sample_id_file

    #read in text file with all project id's
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
			fastq_batch_dir=$rawdata_dir/batch_$batch_count
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
# Analysis
#############################################################################################
if [[ $flag_analysis == "Y" ]]; then
	#log
	message_cmd_log "--Processing batches:"

	# determine number of batches
	batch_count=`ls $log_dir/manifests/batch* | rev | cut -d'/' -f 1 | rev | tail -1 | cut -f2 -d"0" | cut -f1 -d"."`
	batch_min=`ls $log_dir/manifests/batch* | rev | cut -d'/' -f 1 | rev | head -1 | cut -f2 -d"0" | cut -f1 -d"."`

	#for each batch
	for (( batch_id=$batch_min; batch_id<=$batch_count; batch_id++ )); do

		# set batch name
		if [[ "$batch_id" -gt 9 ]]; then batch_name=$batch_id; else batch_name=0${batch_id}; fi
		
		# set batch manifest, dirs
		batch_manifest=$log_dir/manifests/batch_${batch_name}.txt
		fastq_batch_dir=$rawdata_dir/batch_$batch_id
		pipeline_batch_dir=$pipeline_dir/batch_$batch_id
		samplesheet=$log_dir/manifests/samplesheet_0$batch_id.csv
		if [[ ! -d $fastq_batch_dir ]]; then mkdir $fastq_batch_dir; fi
		if [[ ! -d $pipeline_batch_dir ]]; then mkdir $pipeline_batch_dir; fi

		#create proj tmp dir to enable multiple projects to be run simultaneously
		project_number=`$config_basespace_cmd list projects --filter-term="${project_name_full}" | sed -n '4 p' | awk '{split($0,a,"|"); print a[3]}' | sed 's/ //g'`
		if [[ ! -d $project_number ]]; then mkdir $project_number; fi
		
		if [[ $resume == "Y" ]]; then
			cd $project_number
			message_cmd_log "----Resuming pipeline"

			# deploy cecret
			cecret_cmd_line="$cecret_cmd -resume --sample_sheet $samplesheet --reads_type paired --outdir $pipeline_batch_dir"
			echo $cecret_cmd_line
			$cecret_cmd_line
		else
			# read text file
			IFS=$'\n' read -d '' -r -a sample_list < $batch_manifest

			# print number of lines in file without file name "<"
			n_samples=`wc -l < $batch_manifest`
			echo "----Batch_$batch_id ($n_samples samples)"
			echo "----Batch_$batch_id ($n_samples samples)" >> $pipeline_log

			# run per sample, download files
			for sample_id in ${sample_list[@]}; do

				# download from basespace
				$config_basespace_cmd download biosample --quiet -n "${sample_id}" -o $rawdata_dir

				# move files to batch fasta dir
				## using head to only move the first file - when re-runs happen more than one file
				## may be associated to the project
				mv `ls $rawdata_dir/*${sample_id}*/*R1*fastq.gz | head -1` $fastq_batch_dir
				mv `ls $rawdata_dir/*${sample_id}*/*R2*fastq.gz | head -1` $fastq_batch_dir
		
				# If generating a QC report, BASESPACE files need to be unzipped
				# and selected files moved for downstream analysis
				if [[ ! -d "$tmp_dir/${sample_id}" ]]; then mkdir -p $tmp_dir/${sample_id}/hold; fi
				mv `ls $tmp_dir/${sample_id}*/*.zip | head -1` $tmp_dir/${sample_id}/hold

				# unzip analysis file downloaded from DRAGEN to sample tmp dir - used in QC
				unzip -o -q $tmp_dir/${sample_id}*/hold/*.zip -d $tmp_dir/${sample_id}

				# move needed files to general tmp dir
				mv $tmp_dir/${sample_id}/ma/* $tmp_dir/unzipped
			
				# remove sample tmp dir, downloaded proj dir
				rm -r --force $tmp_dir/${sample_id}
		
				# remove downloaded tmp dir
				rm -r --force $tmp_dir/${sample_id}_[0-9]*/
			done
			
			# remove the "_S39_L001" and "_001" from the file name
			for f in $fastq_batch_dir/*; do
				new=`echo $f | sed "s/_S[0-9].*_L001//g" | sed "s/_001//g" | sed "s/[_-]SARS//g" | sed "s/-$project_name_full//g" | sed "s/-$project_name//g" | sed "s/_R/.R/g"`
				if [[ $new != $f ]]; then mv $f $new; fi
			done

			# rename all ID files
			## batch manifests
			cleanmanifests $batch_manifest
			cleanmanifests $samplesheet
			
			## qc files renamed
			for f in $tmp_dir/unzipped/*; do
				new=`echo $f | sed "s/[_-]SARS//g" | sed "s/-$project_name_full//g" | sed "s/-$project_name//g"`
				if [[ $new != $f ]]; then mv $f $new; fi
			done

			#log
			message_cmd_log "------CECRET"
			echo "-------Starting time: `date`" >> $pipeline_log
			echo "-------Starting space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
		
			# copy config
			cp $cecret_config $pipeline_batch_dir

			# deploy cecret
			cd $project_number
			cecret_cmd_line="$cecret_cmd --sample_sheet $samplesheet --reads_type paired --outdir $pipeline_batch_dir"
			echo $cecret_cmd_line
			$cecret_cmd_line
		fi
		
		# log
    	echo "-------Ending time: `date`" >> $pipeline_log
		echo "-------Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log

		#############################################################################################
		# Reporting
		#############################################################################################	
		if [[ -f $pipeline_batch_dir/cecret_results.txt ]]; then
			message_cmd_log "---- The pipeline completed batch #$batch_id at `date` "
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
			mv $pipeline_batch_dir/fastqc/* $fastqc_dir
			
			# move FASTA files
			mv $pipeline_batch_dir/consensus/*fa $fasta_dir
			for f in $fasta_dir/*; do
				new=`echo $f | sed "s/.consensus//g"`
				mv $f $new
			done

			#remove intermediate files
			if [[ $flag_cleanup == "Y" ]]; then
				sudo rm -r --force work
				sudo rm -r --force */work
				sudo rm -r --force $pipeline_batch_dir
				sudo rm -r --force $fastq_batch_dir
				mv $batch_manifest $log_dir/manifests/complete
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
	message_cmd_log "--Creating QC Report"
	echo "---Starting time: `date`" >> $pipeline_log
	echo "---Starting space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log

	# run multiQC
	## -d -dd 1 adds dir name to sample name
	multiqc -f -v \
	-c $multiqc_config \
	$fastqc_dir \
	$tmp_dir/unzipped \
	-o $qcreport_dir 2>&1 | tee -a $multiqc_log

	# create fragment plot
	python_cmd=`python3 $fragment_plots_script $merged_fragment $fragement_plot`
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
	script_list=( $analysis_dir/reports/COVID_Report_nofails.Rmd $analysis_dir/reports/COVID_Report.Rmd )
	for f in ${script_list[@]}; do
		sed -i "s/REP_TODAY/$today_date/g" $f
		sed -i "s/REP_ID/$project_name/g" $f
		sed -i "s/REP_DATE/$proj_date/g" $f
		sed -i "s/REP_PANGO/$pangolin_version/g" $f
		sed -i "s/REP_NC/$nextclade_version/g" $f
		sed -i "s/REP_CECRET/$cecret_version/g" $f
		sed -i "s/REP_AMP/$primer_version/g" $f
		sed -i "s/REP_INSERT/$insert_version/g" $f
	done

	echo "Ending time: `date`" >> $pipeline_log
	echo "Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	message_cmd_log "--- CECRET PIPELINE COMPLETE ---"
	message_cmd_log "------------------------------------------------------------------------"
fi

if [[ $flag_cleanup == "Y" ]]; then
	project_number=`$config_basespace_cmd list projects --filter-term="${project_name_full}" | sed -n '4 p' | awk '{split($0,a,"|"); print a[3]}' | sed 's/ //g'`
	
	#remove all proj files
	sudo rm -r --force $project_number
	sudo rm -r --force $tmp_dir
	sudo rm -r --force $pipeline_dir
	sudo rm -r --force $rawdata_dir
	sudo rm -r --force $fastqc_dir
fi