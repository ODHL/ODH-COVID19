#########################################################
# ARGS
#########################################################
output_dir=$1
project_id=$2
pipeline_config=$3
final_results=$4
gisaid_results=$5
reject_flag=$6

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
fasta_partial=$output_dir/analysis/fasta/upload_partial
fasta_uploaded=$output_dir/analysis/fasta/upload_complete
log_dir=$output_dir/logs

# set files
ncbi_metadata=$log_dir/${project_id}_${date_stamp}_metadata.tsv
ncbi_results=$output_dir/analysis/intermed/ncbi_results.csv

#########################################################
# Controls
#########################################################
# to run cleanup of frameshift samples, pass frameshift_flag
if [[ $reject_flag == "N" ]]; then
	pipeline_prep="Y"
	pipeline_rejected="N"
else
	pipeline_prep="N"
	pipeline_rejected="Y"
fi

#########################################################
# Code
#########################################################
if [[ "$pipeline_prep" == "Y" ]]; then
        echo "----PREPARING FILES"
	# create files
    if [[ -f $metadata_results ]]; then rm $metadata_results; fi
    if [[ -f $ncbi_results ]]; then rm $ncbi_results; fi
	touch $metadata_results
	touch $ncbi_results

    # Create manifest for upload
	# second line is needed for manual upload to ncbi website, but not required for CLI upload
    chunk1="*sample_name\tsample_title\tbioproject_accession\t*organism\t*collected_by\t*collection_date\t*geo_loc_name\t*host"
	chunk2="*host_disease\t*isolate\t*isolation_source\tantiviral_treatment_agent\tcollection_device\tcollection_method\tdate_of_prior_antiviral_treat"
	chunk3="date_of_prior_sars_cov_2_infection\tdate_of_sars_cov_2_vaccination\texposure_event\tgeo_loc_exposure\tgisaid_accession\tgisaid_virus_name"
	chunk4="host_age\thost_anatomical_material\thost_anatomical_part\thost_body_product\thost_disease_outcome\thost_health_state\thost_recent_travel_loc"
	chunk5="host_recent_travel_return_date\thost_sex\thost_specimen_voucher\thost_subject_id\tlat_lon\tpassage_method\tpassage_number\tprior_sars_cov_2_antiviral_treat"
	chunk6="prior_sars_cov_2_infection\tprior_sars_cov_2_vaccination\tpurpose_of_sampling\tpurpose_of_sequencing\tsars_cov_2_diag_gene_name_1\tsars_cov_2_diag_gene_name_2"
	chunk7="sars_cov_2_diag_pcr_ct_value_1\tsars_cov_2_diag_pcr_ct_value_2\tsequenced_by\tvaccine_received\tvirus_isolate_of_prior_infection\tdescription"
	echo "${chunk1}\t${chunk2}\t${chunk3}\t${chunk4}\t${chunk5}\t${chunk6}\t${chunk7}" > $metadata_results

    for f in `ls -1 "$fasta_partial"`; do
		# set full file path
        # grab header line
		# remove header <, SC, consensus_, and .consensus_threshold_[0-9].[0-9]_quality_[0-9]
		#if header has a / then rearraign, otherwise use header
		full_path="$fasta_notuploaded"/$f
		full_header=`cat "$full_path" | grep ">"`
		sample_id=`echo $full_header | awk '{ gsub(">", "")  gsub("SC", "") gsub("Consensus_","") \
		gsub("[.]consensus_threshold_[0-9].[0-9]_quality_[0-9].*","") gsub(" ","") gsub(".consensus.fa",""); print $0}'`
                
		#find associated metadata
        meta=`cat "$log_dir/${config_metadata_file}" | grep "$sample_id"`
                        
		#if meta is found create input metadata row
        if [[ ! "$meta" == "" ]]; then
			#the filename that contains the sequence without path (e.g. all_sequences.fasta not c:\users\meier\docs\all_sequences.fasta)
			IFS='/' read -r -a strarr <<< "$full_path"

			#convert date to ncbi required format - 4/21/81 to 1981-04-21
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
				location=`echo "USA"`
			else
				location=`echo "USA: Ohio"`
			fi

			sc_id=`echo $virus_name | cut -f4 -d"-" | cut -f1 -d"/"`
			gisaid_accession=`cat $gisaid_results | grep $sample_id | cut -f3 -d","`

			# break output into chunks
			chunk1="{sc_id}\t{$config_sample_title}}\t{$config_bioproject_accession}\t{$config_organism}\t{$config_collected_by}"
			chunk2="{$collection_date}\t{$config_geo_loc_name}\t{$config_host}\t{$config_host_disease}\t{$sample_id}"
			chunk3="{$config_isolation_source}\t{$config_antiviral_treatment_agent}\t{$config_collection_device}"
			chunk4="{$config_collection_method}\t{$config_date_of_prior_antiviral_treat}\t{$config_date_of_prior_sars_cov_2_infection}"
			chunk5="{$config_date_of_sars_cov_2_vaccination}\t{$config_exposure_event}\t{$config_geo_loc_exposure}"
			chunk6="{$gisaid_accession}\t{$virus_name}\t{$config_host_age}\t{$config_host_anatomical_material}\t{$config_host_anatomical_part}"
			chunk7="{$config_host_body_product}\t{$config_host_disease_outcome}\t{$config_host_health_state}\t{$config_host_recent_travel_loc}"
			chunk8="{$config_host_recent_travel_return_date}\t{$config_host_sex}\t{$config_host_specimen_voucher}\t{$config_host_subject_id}"
			chunk9="{$config_lat_lon}\t{$config_passage_method}\t{$config_passage_number}\t{$config_prior_sars_cov_2_antiviral_treat}\t{$config_prior_sars_cov_2_infection}"
			chunk10="{$config_prior_sars_cov_2_vaccination}\t{$config_purpose_of_sampling}\t{$config_purpose_of_sequencing}\t{$config_sars_cov_2_diag_gene_name_1}"
			chunk11="{$config_sars_cov_2_diag_gene_name_2}\t{$config_sars_cov_2_diag_pcr_ct_value_1}\t{$config_sars_cov_2_diag_pcr_ct_value_2}"
			chunk12="{$config_sequenced_by}\t{$config_vaccine_received}\t{$config_virus_isolate_of_prior_infection}\t{$config_description"
			
			#add output variables to metadata file
			echo "${chunk1}\t${chunk2}\t${chunk3}\t${chunk4}\t${chunk5}\t${chunk6}\t${chunk7}\t${chunk8}\t${chunk9}\t${chunk10}\t${chunk11}\t${chunk12}" >> $metadata_results
			
            fi
        done
fi

if [[ "$pipeline_rejected" == "Y" ]]; then
	echo "----RUNNING QC"
	# then pull line by grouping and determine metdata information
	# uploaded: ncbi_id
	# errors: failed
	samples_uploaded=`cat $ncbi_log | grep "SRA" | cut -f1 -d","`
	samples_failed=`cat $ncbi_log | grep "failed" | cut -f1 -d","`

	## for samples that successfully uploaded, pull the ncbi ID
	## move samples to uploaded folder
	for log_line in ${samples_uploaded[@]}; do
		sample_line=`cat $ncbi_log | grep "${log_line}"`
		ncbi_id=`echo $sample_line | grep -o "EPI_ISL_[0-9]*.[0-9]"`
		sample_id=`echo $sample_line | grep -o "SC[0-9]*./202[0-9]" | sed "s/SC//" | sed "s/202[1,2]/202/" | awk 'BEGIN{FS=OFS="/"}{ print $2$1}'`
		
		mv ${fasta_notuploaded}/${sample_id}.* ${fasta_uploaded}
		echo "$sample_id,ncbi_pass,$ncbi_id" >> $ncbi_results
	done

    ## for samples that had manifest error issues, add error
	## move samples to failed folder
	for log_line in ${samples_manifest_errors[@]}; do
                sample_line=`cat $ncbi_log | grep "${log_line}"`
		manifest_col=`echo $sample_line | cut -f3 -d"{" | sed "s/field_missing_error//g" | sed "s/\"//g" | sed 's/[\]//g' | sed "s/: , /,/g" | sed "s/: }//g" | sed "s/}//g"`
		sample_id=`echo $sample_line | grep -o "SC[0-9]*./202[0-9]" | sed "s/SC//" | sed "s/202[1,2]/202/" | awk 'BEGIN{FS=OFS="/"}{ print $2$1}'`
		
		mv ${fasta_notuploaded}/${sample_id}.* ${fasta_failed}
		echo "$sample_id,ncbi_fail,manifest_errors:$manifest_col" >> $ncbi_results
        done
	
	# merge ncbi results to final results file by sample id
    sort $ncbi_results > tmp_gresults.txt
	sort $final_results > tmp_fresults.txt
	echo "sample_id,ncbi_status,ncbi_notes,pango_qc,nextclade_clade,pangolin_lineage,pangolin_scorpio,aa_substitutions" > $final_results
	join <(sort tmp_gresults.txt) <(sort tmp_fresults.txt) -t $',' >> $final_results
	rm tmp_fresults.txt tmp_gresults.txt

fi
