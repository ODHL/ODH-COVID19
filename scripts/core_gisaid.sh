#########################################################
# ARGS
#########################################################
output_dir=$1
project_id=$2
pipeline_config=$3
final_results=$4
subworkflow=$5
environment=$6
proj_date=$7

#########################################################
# Eval, source
#########################################################
source $(dirname "$0")/functions.sh
eval $(parse_yaml ${pipeline_config} "config_")

#########################################################
# Requirements
#########################################################
# check metadata file exists
if [[ ! -f $config_metadata_file ]]; then
    echo "----Missing metadata file $config_metadata_file. File must be located in $log_dir. Review config_pipeline to update file name."
    exit
fi

#########################################################
# Set dirs, files, args
#########################################################
# set date
today_date=$(date '+%Y-%m-%d'); today_date=`echo $today_date | sed "s/-//g"`
today_date="20240306"
# set dirs
fasta_dir=$output_dir/analysis/fasta
log_dir=$output_dir/logs
intermed_dir=$output_dir/analysis/intermed

# set files
pipeline_log=$log_dir/pipeline_log.txt
gisaid_log="$log_dir/gisaid/gisaid_log_${project_id}_${today_date}.txt"
gisaid_failed="$log_dir/gisaid/gisaid_failed_${project_id}_${today_date}.txt"

gisaid_results="$intermed_dir/gisaid_results.csv"
cecret_results="$intermed_dir/final_cecret.csv"

FASTA_filename="batched_fasta_${project_id}_${today_date}.fasta"
batched_fasta="$log_dir/gisaid/$FASTA_filename"
meta_filename="batched_meta_${project_id}_${today_date}.csv"
batched_meta="$log_dir/gisaid/$meta_filename"
#########################################################
# Controls
#########################################################
flag_prep="N"
flag_upload="N"
flag_qc="N"
if [[ $subworkflow == "PREP" ]]; then
	flag_prep="Y"
elif [[ $subworkflow == "UPLOAD" ]]; then
	flag_upload="Y"
elif [[ $subworkflow == "QC" ]]; then
	flag_qc="Y"
elif [[ $subworkflow == "ALL" ]]; then
	flag_prep="Y"
	flag_upload="Y"
	flag_qc="Y"
else
	echo "CHOOSE CORRECT FLAG -s: PREP UPLOAD QC ALL"
	echo "YOU CHOOSE: $subworkflow"
fi

#########################################################
# Code
#########################################################
# set keys
username=`cat /home/ubuntu/tools/gisaid/keys | grep "username" | cut -f2 -d":"`
password=`cat /home/ubuntu/tools/gisaid/keys | grep "password" | cut -f2 -d":"`
clientid=`cat /home/ubuntu/tools/gisaid/keys | grep "clientid" | cut -f2 -d":"`

if [[ "$flag_prep" == "Y" ]]; then
	message_cmd_log "------------------------------------------------------------------------"
	message_cmd_log "--- STARTING GISAID PIPELINE ---"
	message_cmd_log "----PREPARING FILES"
    message_cmd_log "Ending time: `date`"
	
	# create files
    if [[ -f $batched_meta ]]; then rm $batched_meta; fi
    if [[ -f $gisaid_results ]]; then rm $gisaid_results; fi
    if [[ -f $batched_fasta ]]; then rm $batched_fasta; fi

	# clean metadata file
	sed -i "s/ //g" $config_metadata_file

    # Create manifest for upload
	# second line is needed for manual upload to gisaid website, but not required for CLI upload
    echo "submitter,fn,covv_virus_name,covv_type,covv_passage,covv_collection_date,covv_location,covv_add_location,covv_host,covv_add_host_info,covv_sampling_strategy,covv_gender,covv_patient_age,covv_patient_status,covv_specimen,covv_outbreak,covv_last_vaccinated,covv_treatment,covv_seq_technology,covv_assembly_method,covv_coverage,covv_orig_lab,covv_orig_lab_addr,covv_provider_sample_id,covv_subm_lab,covv_subm_lab_addr,covv_subm_sample_id,covv_authors,covv_comment,comment_type" > $batched_meta
	
    for f in ${fasta_dir}/*; do
        # set full file path
        # grab header line
        # remove header <, SC, consensus_, and .consensus_threshold_[0-9].[0-9]_quality_[0-9]
        # if header has a / then rearraign, otherwise use header
        sample_id=`cat $f | grep ">" | cut -f2 -d">" | cut -f2 -d"_" | cut -f1 -d"."`

		# ensure sample passed PIPELINE QC
		qc_status=`cat $cecret_results | grep $sample_id | grep -o "pass"`
		if [[ $qc_status == "pass" ]]; then		
			# determine total number of seq
			# if the file is empty, set equal to 1
			total_num=`cat "$f" | grep -v ">" | wc -m`
			if [ "$total_num" -eq 0 ]; then total_num=1; fi

			# determine total number of N
			# if there are no N's set value to 1
			n_num=`cat "$f" | tr -d -c 'N' | awk '{ print length; }'`
			if [ ! -n "$n_num" ]; then n_num=1; fi

			# if the frequency of N's is higher than 50 GISAID will reject
			# the sample - screen and move any sample with N>50 to
			# failed folder and add to list
			percent_n_calc=$(($n_num*100/$total_num))
			if [[ $percent_n_calc -gt 50 ]]; then
				echo "--sample failed N check: $sample_id at ${percent_n_calc}%_Ns"
				echo "$sample_id,qc_fail,qc_${percent_n_calc}%_Ns" >> $gisaid_results
			else
				#find associated metadata
				meta=`cat "${config_metadata_file}" | grep "$sample_id"`
				
				# if meta is found create input metadata row
				if [[ ! "$meta" == "" ]]; then
					# the filename that contains the sequence without path (e.g. all_sequences.fasta not c:\users\meier\docs\all_sequences.fasta)
					IFS='/' read -r -a strarr <<< "$f"

					#convert date to GISAID required format - 4/21/81 to 1981-04-21
					raw_date=`echo $meta | awk -F',' '{print $3}'`
					collection_yr=`echo "${raw_date}" | awk '{split($0,a,"/"); print a[3]}' | tr -d '"'`
					collection_mn=`echo "${raw_date}" | awk '{split($0,a,"/"); print a[1]}' | tr -d '"'`
					collection_dy=`echo "${raw_date}" | awk '{split($0,a,"/"); print a[2]}' | tr -d '"'`
					if [[ $collection_mn -lt 10 ]]; then collection_mn="0$collection_mn"; fi
					if [[ $collection_dy -lt 10 ]]; then collection_dy="0$collection_dy"; fi
					collection_date=${collection_yr}-${collection_mn}-${collection_dy}

					# take header (IE 2021064775) and turn into correct version hCoV-19/USA/OH-xxx/YYYY
					# for example: hCoV-19/Netherlands/Gelderland-01/2020 (Must be FASTA-Header from the FASTA file all_sequences.fasta)
					# year must be the collection year and not the analysis or sequencing year
					# cut_id will be 2021064775 --> 1064775 OR 2022064775 --> 2064775 OR 2020064775 --> 1064775
					year=`echo "${raw_date}" | awk '{split($0,a,"/"); print a[3]}' | tr -d '"'`
					cut_id=`echo $sample_id | awk '{ gsub("2020","1") gsub("2022","2") gsub("2023","3") gsub("2024","4"); print $0}'`
					virus_name="hCoV-19/USA/OH-ODH-SC$cut_id/$year"

					#e.g. Europe / Germany / Bavaria / Munich
					county=`echo ${meta} | awk -F',' '{print $4}' | tr -d '"'`
					if [[ "$county" == *"OUT OF STATE"* ]]; then
						location=`echo "North America/USA/"`
					else
						location=`echo "North America/USA/OHIO/$county"`
					fi

					# Calculate the person's age in either years or months based on today's date
					#e.g.  65 or 7 months, or unknown
					# dates must be with "/"
					raw_dob=`echo $meta | awk -F',' '{print $2}'`
					patient_yr=`echo "${raw_dob}" | awk '{split($0,a,"/"); print a[3]}' | sed 's/^0*//' | tr -d '"'`
					patient_mn=`echo "${raw_dob}" | awk '{split($0,a,"/"); print a[1]}' | sed 's/^0*//' | tr -d '"'`
					patient_dy=`echo "${raw_dob}" | awk '{split($0,a,"/"); print a[2]}' | sed 's/^0*//' | tr -d '"'`

					today_yr=`date '+%Y' | sed 's/^0*//'`
					today_mn=`date '+%m' | sed 's/^0*//'`
					today_dy=`date '+%d' | sed 's/^0*//'`

					agey=$(($today_yr-$patient_yr))
					agem=$(($today_mn-$patient_mn))
					aged=$(($today_dy-$patient_dy))

					# if patient is <0 then add months
					if [[ $agey -eq 0 ]]; then agey="$patient_mn months"; fi

					# if the patients birthday hasn't happened, adjust
					if [[ $agem -lt 0 ]]; then
						agey=$((agey-1))
					elif [[ $agem -eq 0 && $aged -lt 0 ]] ; then
						agey=$((agey-1))
					fi

					#add output variables to metadata file
					#excel metadata files may add what is viewed as "^M" to the end line of the file
					# this is interpreted as "\r" however and must be removed
					echo "${config_submitter},${FASTA_filename},${virus_name},${config_type},${config_passage},${collection_date},\"${location}\",${config_additional_location_information},${config_host},${config_additional_host_information},${config_sampling_strategy},${config_gender},${agey},${config_patient_status},${config_specimen_source},${config_outbreak},${config_last_vaccinated},${config_treatment},${config_sequencing_technology},${config_assembly_method},${config_coverage},\"${config_originating_lab}\",\"${config_address_originating}\",${sample_id},\"${config_submitting_lab}\",\"${config_address_submitting}\",${sample_id},\"${config_authors}\"" >> $batched_meta
					sed -i "s/\r//" $batched_meta

					# merge all fasta files that pass QC and metadata into one
					# skips the header line and any odd formatted /date lines that follow
					echo ">$virus_name" | sed 's/*/-/g' >> $batched_fasta
					cat "$f" | grep -v ">" | grep -v "/" >> $batched_fasta

					echo "$sample_id is ready"
				# if there is no metadata, not and fail
				else
					#add sample to results, move associated files
					echo "--sample failed metadata check: $sample_id"
					echo "$sample_id,qc_fail,qc_missing_metadata" >> $gisaid_results
				fi
			fi
		else
			echo "--sample failed pipeline check: $sample_id"
			echo "$sample_id,qc_fail,pipeline_fail" >> $gisaid_results
        fi
    done
fi

if [[ "$flag_upload" == "Y" ]]; then
	## QC check
	if [[ -f $batched_fasta ]]; then
		message_cmd_log "----UPLOADING"
		# if this is a re-run, save previous log file
		if [[ -f "${gisaid_log}" ]]; then mv ${gisaid_log} ${gisaid_log}_v1; fi
		
		$config_gisaid_cmd upload \
		--metadata $batched_meta \
		--fasta $batched_fasta \
		--log $gisaid_log \
		--frameshift catch_novel \
		--username $username \
		--password $password \
		--clientid $clientid
	fi
fi

if [[ "$flag_qc" == "Y" ]]; then
	message_cmd_log "----RUNNING QC"
	# then pull line by grouping and determine metdata information
	# uploaded: EPI_ID
	# duplicated: EPI_ID
	# errors: columns which had errors
	samples_uploaded=`cat $gisaid_log | grep "epi_isl_id" | grep -v "validation_error" | grep -o "SC[0-9]*./202[0-4]"`
	samples_duplicated=`cat $gisaid_log | grep "existing_ids" | grep -o "SC[0-9]*./202[0-4]"`
	samples_manifest_errors=`cat $gisaid_log | grep "field_missing" | grep -o "SC[0-9]*./202[0-4]"`

	## for samples that successfully uploaded, pull the GISAID ID
	## move samples to uploaded folder
	for log_line in ${samples_uploaded[@]}; do
		sample_line=`cat $gisaid_log | grep "${log_line}"`
		epi_id=`echo $sample_line | grep -o "EPI_ISL_[0-9]*.[0-9]"`
		sample_id=`echo $sample_line | grep -o "SC[0-9]*./202[0-4]" | cut -c 4- | awk 'BEGIN{FS=OFS="/"}{ print $2$1}'`
		echo "$sample_id,gisaid_pass,$epi_id" >> $gisaid_results
	done

	## for samples that have already been uploaded, add previous id
	## move samples to uploaded folder
	for log_line in ${samples_duplicated[@]}; do
        sample_line=`cat $gisaid_log | grep "${log_line}"`
		epi_id=`echo $sample_line | grep -o "EPI_ISL_[0-9]*.[0-9]"`
		sample_id=`echo $sample_line | grep -o "SC[0-9]*./202[0-4]" | cut -c 4- | awk 'BEGIN{FS=OFS="/"}{ print $2$1}'`
		echo "$sample_id,gisaid_fail,duplicated_id:$epi_id" >> $gisaid_results
	done

    ## for samples that had manifest error issues, add error
	## move samples to failed folder
	for log_line in ${samples_manifest_errors[@]}; do
        sample_line=`cat $gisaid_log | grep "${log_line}"`
		manifest_col=`echo $sample_line | cut -f3 -d"{" | sed "s/field_missing_error//g" | sed "s/\"//g" | sed 's/[\]//g' | sed "s/: , /,/g" | sed "s/: }//g" | sed "s/}//g"`
		sample_id=`echo $sample_line | grep -o "SC[0-9]*./202[0-4]" | cut -c 4- | awk 'BEGIN{FS=OFS="/"}{ print $2$1}'`
		echo "$sample_id,gisaid_fail,manifest_errors:$manifest_col" >> $gisaid_results
    done
	
	# merge gisaid results to final results file by sample id
	if [[ -f $final_results ]]; then mv $final_results $intermed_dir/final_copy.csv; fi
    sed -i "s/>Consensus_//g" $gisaid_results
	sed -i "s/\.fa//g" $gisaid_results
	sort $gisaid_results > tmp_gresults.txt
	sort $cecret_results > tmp_cresults.txt
	echo "sample_id,gisaid_status,gisaid_notes,pango_status,pangolin_lineage,pangolin_scorpio,pangolin_version,nextclade_clade,aa_substitutions" > $final_results
	join <(sort -k1 -t, tmp_gresults.txt) <(sort -k1 -t, tmp_cresults.txt) -t $',' >> $final_results
	rm tmp_cresults.txt tmp_gresults.txt

	check_length=`cat $final_results | wc -l`
	if [[ $check_length -gt 10 ]]; then
		if [[ -d $fasta_dir ]]; then tar -zcvf $fasta_dir.tar.gz $fasta_dir/; fi
		if [[ -f $fasta_dir.tar.gz ]]; then rm -rf $fasta_dir/; fi
		
		# log
		message_cmd_log "---- The pipeline completed upload at `date` "
		message_cmd_log "--- GISAID PIPELINE COMPLETE ---"
		message_cmd_log "------------------------------------------------------------------------"
	else 
		echo "FAILED: $final_results"
		exit
	fi
fi