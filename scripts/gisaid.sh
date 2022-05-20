#########################################################
# ARGS
#########################################################
output_dir=$1
project_id=$2
pipeline_config=$3
final_results=$4
reject_flag=$5
#########################################################
# functions
#########################################################
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


#########################################################
# Set dirs, files, args
#########################################################
# read in config
eval $(parse_yaml ${pipeline_config} "config_")

# set date
date_stamp=`date '+%Y_%m_%d'`

# set dirs
fasta_notuploaded=$output_dir/analysis/fasta/not_uploaded
fasta_uploaded=$output_dir/analysis/fasta/upload_partial
fasta_failed=$output_dir/analysis/fasta/upload_failed
log_dir=$output_dir/logs

# set files
gisaid_log="$log_dir/gisaid_log_${project_id}_${date_stamp}.txt"
gisaid_failed="$log_dir/gisaid_failed_${project_id}_${date_stamp}.txt"
gisaid_results="$output_dir/analysis/intermed/gisaid_results.csv"
gisaid_rejected="$output_dir/analysis/intermed/gisaid_rejected.csv"

FASTA_filename="batched_fasta_${project_id}_${date_stamp}.fasta"
batched_fasta="$log_dir/$FASTA_filename"

meta_filename="batched_meta_${project_id}_${date_stamp}.csv"
batched_meta="$log_dir/$meta_filename"

# set gisaid ID
gisaid_auth="${config_gisaid_auth}"

#########################################################
# Controls
#########################################################
# to run cleanup of frameshift samples, pass frameshift_flag
if [[ $reject_flag == "N" ]]; then
	pipeline_prep="Y"
	pipeline_upload="Y"
	pipeline_qc="Y"
	pipeline_rejected="N"
else
	pipeline_prep="N"
	pipeline_upload="N"
	pipeline_qc="N"
	pipeline_rejected="Y"
fi

#########################################################
# Code
#########################################################
if [[ "$pipeline_prep" == "Y" ]]; then
        echo "----PREPARING FILES"
	# create files
        if [[ -f $batched_meta ]]; then rm $batched_meta; fi
        if [[ -f $gisaid_results ]]; then rm $gisaid_results; fi
        if [[ -f $batched_fasta ]]; then rm $batched_fasta; fi
	touch $batched_fasta
	touch $gisaid_results
	touch $gisaid_log

        # Create manifest for upload
	# second line is needed for manual upload to gisaid website, but not required for CLI upload
        echo "submitter,fn,covv_virus_name,covv_type,covv_passage,covv_collection_date,covv_location,covv_add_location,covv_host,covv_add_host_info,covv_sampling_strategy,covv_gender,covv_patient_age,covv_patient_status,covv_specimen,covv_outbreak,covv_last_vaccinated,covv_treatment,covv_seq_technology,covv_assembly_method,covv_coverage,covv_orig_lab,covv_orig_lab_addr,covv_provider_sample_id,covv_subm_lab,covv_subm_lab_addr,covv_subm_sample_id,covv_authors,covv_comment,comment_type" > $batched_meta

        #echo "Submitter,\"FASTA filename\",\"Virus name\",Type,\"Passage details/history\",\"Collection date\",Location,\"Additional location information\",\
        #        Host,\"Additional host information\",\"Sampling Strategy\",Gender,\"Patient age\",\"Patient status\",\"Specimen source\",\
        #        Outbreak,\"Last vaccinated\",Treatment,\"Sequencing technology\",\"Assembly method\",\
        #        Coverage,\"Originating lab\",Address,\"Sample ID given by originating laboratory\",\"Submitting lab\",\
        #        Address,\"Sample ID given by the submitting laboratory\",Authors,Comment,\"Comment Icon\"" >> $batched_meta

        for f in `ls -1 "$fasta_notuploaded"`; do
                # set full file path
                # grab header line
                # remove header <, SC, consensus_, and .consensus_threshold_[0-9].[0-9]_quality_[0-9]
                #if header has a / then rearraign, otherwise use header
                full_path="$fasta_notuploaded"/$f
                full_header=`cat "$full_path" | grep ">"`
                sample_id=`echo $full_header | awk '{ gsub(">", "")  gsub("SC", "") gsub("Consensus_","") \
			gsub("[.]consensus_threshold_[0-9].[0-9]_quality_[0-9].*","") gsub(" ","") gsub(".consensus.fa",""); print $0}'`
                
		# determine total number of seq
                # if the file is empty, set equal to 1
                total_num=`cat "$full_path" | grep -v ">" | wc -m`
                if [ "$total_num" -eq 0 ]; then total_num=1; fi

                # determine total number of N
                # if there are no N's set value to 1
                n_num=`cat "$full_path" | tr -d -c 'N' | awk '{ print length; }'`
                if [ ! -n "$n_num" ]; then n_num=1; fi

                # if the frequency of N's is higher than 50 GISAID will reject
                # the sample - screen and move any sample with N>50 to
                # failed folder and add to list
		percent_n_calc=$(($n_num*100/$total_num))
                if [[ "$percent_n_calc" -gt $((config_percent_n_cutoff)) ]]; then
			short_f=`echo $f | sed "s/.consensus.fa//"`
			echo "$short_f,gisaid_fail,qc_${percent_n_calc}%_Ns" >> $gisaid_results
                        mv "$full_path" "$fasta_failed"/"${sample_id}.consensus.fa"
                else
                        #find associated metadata
                        meta=`cat "$log_dir/${config_metadata_file}" | grep "$sample_id"`
                        
			#if meta is found create input metadata row
                        if [[ ! "$meta" == "" ]]; then
                                #the filename that contains the sequence without path (e.g. all_sequences.fasta not c:\users\meier\docs\all_sequences.fasta)
                                IFS='/' read -r -a strarr <<< "$full_path"

                                #convert date to GISAID required format - 4/21/81 to 1981-04-21
                                raw_date=`echo $meta | awk -F',' '{print $3}'`
                                collection_yr=`echo "${raw_date}" | awk '{split($0,a,"/"); print a[3]}' | tr -d '"'`
                                collection_mn=`echo "${raw_date}" | awk '{split($0,a,"/"); print a[1]}' | tr -d '"'`
                                collection_dy=`echo "${raw_date}" | awk '{split($0,a,"/"); print a[2]}' | tr -d '"'`
				if [[ $collection_mn -lt 9 ]]; then collection_mn="0$collection_mn"; fi
                                if [[ $collection_dy -lt 9 ]]; then collection_dy="0$collection_dy"; fi
                                collection_date=${collection_yr}-${collection_mn}-${collection_dy}

				# take header (IE 2021064775) and turn into correct version hCoV-19/USA/OH-xxx/YYYY
                                # for example: hCoV-19/Netherlands/Gelderland-01/2020 (Must be FASTA-Header from the FASTA file all_sequences.fasta)
                                # year must be the collection year and not the analysis or sequencing year
				# cut_id will be 2021064775 --> 1064775 OR 2022064775 --> 2064775 OR 2020064775 --> 1064775
				year=`echo "${raw_date}" | awk '{split($0,a,"/"); print a[3]}' | tr -d '"'`
                                cut_id=`echo $sample_id | awk '{ gsub("2020","1") gsub("202",""); print $0}'`
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
                                if [[ $agey -eq 0 ]]; then
                                        agey="$patient_mn months"
                                fi

                                # if the patients birthday hasn't happened, adjust
                                if [[ $agem -lt 0 ]]; then
                                        agey=$((agey-1))
                                elif [[ $agem -eq 0 && $aged -lt 0 ]] ; then
                                        agey=$((agey-1))
                                fi

                                #add output variables to metadata file
				#excel metadata files may add what is viewed as "^M" to the end line of the file
				# this is interpreted as "\r" however and must be removed
				echo "${config_submitter},${FASTA_filename},${virus_name},${config_type},${config_passage},${collection_date},\"${location}\",${config_additional_location_information},${config_host},${config_additional_host_information},${config_sampling_strategy},${config_gender},${agey},${config_patient_status},${config_specimen_source},${config_outbreak},${config_last_vaccinated},${config_treatment},${config_sequencing_technology},${config_assembly_method},${config_coverage},\"${config_submitting_lab}\",\"${config_address_submitting}\",${sample_id},\"${config_submitting_lab}\",\"${config_address_submitting}\",${sample_id},\"${config_authors}\"" >> $batched_meta
				sed -i "s/\r//" $batched_meta

                                # merge all fasta files that pass QC and metadata into one
                                # skips the header line and any odd formatted /date lines that follow
                                echo ">$virus_name" | sed 's/*/-/g' >> $batched_fasta
                                cat "$full_path" | grep -v ">" | grep -v "/" >> $batched_fasta

                        else
                                # add sample to results, move associated files
                                echo "$sample_id,gisaid_fail,qc_missing_metadata" >> $gisaid_results
                                mv "$full_path" "$fasta_failed"/${sample_id}.fa
                        fi
                fi
        done
fi

if [[ "$pipeline_upload" == "Y" ]]; then
	echo "----UPLOADING"
	# if this is a re-run, save previous log file
	if [[ -f "${gisaid_log}" ]]; then mv ${gisaid_log} ${gisaid_log}_v1; fi
	
	cli2 upload --metadata $batched_meta --fasta $batched_fasta --token $gisaid_auth --log $gisaid_log --failed $gisaid_failed --frameshift catch_novel
fi

if [[ "$pipeline_qc" == "Y" ]]; then
	echo "----RUNNING QC"
	# then pull line by grouping and determine metdata information
	# uploaded: EPI_ID
	# duplicated: EPI_ID
	# errors: columns which had errors
	samples_uploaded=`cat $gisaid_log | grep "epi_isl_id" | grep -v "validation_error" | grep -o "SC[0-9]*./202[0-9]"`
	samples_duplicated=`cat $gisaid_log | grep "existing_ids" | grep -o "SC[0-9]*./202[0-9]"`
	samples_manifest_errors=`cat $gisaid_log | grep "field_missing" | grep -o "SC[0-9]*./202[0-9]"`

	## for samples that successfully uploaded, pull the GISAID ID
	## move samples to uploaded folder
	for log_line in ${samples_uploaded[@]}; do
		sample_line=`cat $gisaid_log | grep "${log_line}"`
		epi_id=`echo $sample_line | grep -o "EPI_ISL_[0-9]*.[0-9]"`
		sample_id=`echo $sample_line | grep -o "SC[0-9]*./202[0-9]" | sed "s/SC//" | sed "s/202[1,2]/202/" | awk 'BEGIN{FS=OFS="/"}{ print $2$1}'`
		
		mv ${fasta_notuploaded}/${sample_id}.* ${fasta_uploaded}
		echo "$sample_id,gisaid_pass,$epi_id" >> $gisaid_results
	done

	## for samples that have already been uploaded, add previous id
	## move samples to uploaded folder
	for log_line in ${samples_duplicated[@]}; do
                sample_line=`cat $gisaid_log | grep "${log_line}"`
		epi_id=`echo $sample_line | grep -o "EPI_ISL_[0-9]*.[0-9]"`
                sample_id=`echo $sample_line | grep -o "SC[0-9]*./202[0-9]" | sed "s/SC//" | sed "s/202[1,2]/202/" | awk 'BEGIN{FS=OFS="/"}{ print $2$1}'`
		
		mv ${fasta_notuploaded}/${sample_id}.* ${fasta_uploaded}
		echo "$sample_id,gisaid_fail,duplicated_id:$epi_id" >> $gisaid_results
	done

        ## for samples that had manifest error issues, add error
	## move samples to failed folder
	for log_line in ${samples_manifest_errors[@]}; do
                sample_line=`cat $gisaid_log | grep "${log_line}"`
		manifest_col=`echo $sample_line | cut -f3 -d"{" | sed "s/field_missing_error//g" | sed "s/\"//g" | sed 's/[\]//g' | sed "s/: , /,/g" | sed "s/: }//g" | sed "s/}//g"`
		sample_id=`echo $sample_line | grep -o "SC[0-9]*./202[0-9]" | sed "s/SC//" | sed "s/202[1,2]/202/" | awk 'BEGIN{FS=OFS="/"}{ print $2$1}'`
		
		mv ${fasta_notuploaded}/${sample_id}.* ${fasta_failed}
		echo "$sample_id,gisaid_fail,manifest_errors:$manifest_col" >> $gisaid_results
        done
	
	# merge gisaid results to final results file by sample id
        sort $gisaid_results > tmp_gresults.txt
	sort $final_results > tmp_fresults.txt
	echo "sample_id,gisaid_status,gisaid_notes,pango_qc,nextclade_clade,pangolin_lineage,pangolin_scorpio,aa_substitutions" > $final_results
	join <(sort tmp_gresults.txt) <(sort tmp_fresults.txt) -t $',' >> $final_results
	rm tmp_fresults.txt tmp_gresults.txt

fi

if [[ "$pipeline_rejected" == "Y" ]]; then
        echo "----PROCESSING REJECTED SAMPLES"
        # when a sample is rejected user creates /output/dir/analysis/intermed/gisaid_rejected.csv file
	# information includes full sample name followed by "," and reason. these include
	# frameshift, other, truncation

	# code below will pull this line and update the final_results file with new information
	rejected_lines=`cat $gisaid_rejected`

        ## for samples that were rejected, update the final analysis file
        ## move samples to failed folder
        for rejected_line in ${rejected_lines[@]}; do
		
		# grab sampleID
		sample_id=202`echo $rejected_line | cut -f3 -d'/' | cut -f3 -d"-" | sed "s/SC//g"`
		
		reject_reason=`echo $rejected_line | cut -f2 -d","`

		results_line=`cat $final_results | grep "${sample_id}"`
		new_line=`echo $results_line | sed "s/gisaid_pass/gisaid_rejected/g" | sed "s/EPI/$reject_reason-EPI/g"`

		# move file to notuploaded dir
		mv ${fasta_uploaded}/${sample_id}.* ${fasta_failed}
		
		# replace the old line with the new line
		sed -i "s/$results_line/$new_line/" $final_results
        done
fi
