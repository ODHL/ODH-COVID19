#########################################################
# ARGS
#########################################################
output_dir=$1
project_id=$2
pipeline_config=$3
gisaid_results=$4
reject_flag=$5
final_results=$6

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
ncbi_hold="../ncbi_hold/$project_id"

# set files
ncbi_attributes=$log_dir/batched_ncbi_att_${project_id}_${date_stamp}.tsv
ncbi_metadata=$log_dir/batched_ncbi_meta_${project_id}_${date_stamp}.tsv
ncbi_output=$ncbi_hold/complete/*ok.tsv
ncbi_results=$output_dir/analysis/intermed/ncbi_results.csv

# set basespace command
basespace_command=${config_basespace_cmd}

#########################################################
# Controls
#########################################################
# to run cleanup of frameshift samples, pass frameshift_flag
if [[ $reject_flag == "N" ]]; then
	pipeline_prep="Y"
	pipeline_download="Y"
	pipeline_sra="N"
else
	pipeline_prep="N"
	pipeline_download="N"
	pipeline_sra="Y"
fi

#########################################################
# Code
#########################################################
if [[ "$pipeline_prep" == "Y" ]]; then
        echo "----PREPARING FILES"
	# create files
    	if [[ -f $ncbi_metadata ]]; then rm $ncbi_metadata; fi
    	if [[ -f $ncbi_results ]]; then rm $ncbi_results; fi
	touch $ncbi_results

    	# Create manifest for attribute upload
    	chunk1="*sample_name\tsample_title\tbioproject_accession\t*organism\t*collected_by\t*collection_date\t*geo_loc_name\t*host"
	chunk2="*host_disease\t*isolate\t*isolation_source\tantiviral_treatment_agent\tcollection_device\tcollection_method\tdate_of_prior_antiviral_treat"
	chunk3="date_of_prior_sars_cov_2_infection\tdate_of_sars_cov_2_vaccination\texposure_event\tgeo_loc_exposure\tgisaid_accession\tgisaid_virus_name"
	chunk4="host_age\thost_anatomical_material\thost_anatomical_part\thost_body_product\thost_disease_outcome\thost_health_state\thost_recent_travel_loc"
	chunk5="host_recent_travel_return_date\thost_sex\thost_specimen_voucher\thost_subject_id\tlat_lon\tpassage_method\tpassage_number\tprior_sars_cov_2_antiviral_treat"
	chunk6="prior_sars_cov_2_infection\tprior_sars_cov_2_vaccination\tpurpose_of_sampling\tpurpose_of_sequencing\tsars_cov_2_diag_gene_name_1\tsars_cov_2_diag_gene_name_2"
	chunk7="sars_cov_2_diag_pcr_ct_value_1\tsars_cov_2_diag_pcr_ct_value_2\tsequenced_by\tvaccine_received\tvirus_isolate_of_prior_infection\tdescription"
	echo -e "${chunk1}\t${chunk2}\t${chunk3}\t${chunk4}\t${chunk5}\t${chunk6}\t${chunk7}" > $ncbi_attributes

	# Create manifest for metadata upload
	chunk1="sample_name\tlibrary_ID\ttitle\tlibrary_strategy\tlibrary_source\tlibrary_selection"
	chunk2="library_layout\tplatform\tinstrument_model\tdesign_description\tfiletype\tfilename"
	chunk3="filename2\tfilename3\tfilename4\tassembly\tfasta_file"
	echo -e "${chunk1}\t${chunk2}\t${chunk3}" > $ncbi_metadata
	
	for f in `ls -1 "$fasta_partial"`; do
		# set full file path
        	# grab header line
		# remove header <, SC, consensus_, and .consensus_threshold_[0-9].[0-9]_quality_[0-9]
		#if header has a / then rearraign, otherwise use header
		full_path="$fasta_partial"/$f
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
			if [[ $collection_mn -lt 10 ]]; then collection_mn="0$collection_mn"; fi
			if [[ $collection_dy -lt 10 ]]; then collection_dy="0$collection_dy"; fi
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

			# set remaining variables
			sc_id=`echo $virus_name | cut -f4 -d"-" | cut -f1 -d"/"`
			gisaid_accession=`cat $gisaid_results | grep $sample_id | cut -f3 -d","`
			sample_title=`echo "${config_library_strategy} of ${config_organism}: ${config_isolation_source}"`

			# break output into chunks
			chunk1="${sc_id}\t${config_sample_title}\t${config_bioproject_accession}\t${config_organism}\t${config_collected_by}"
			chunk2="${collection_date}\t${location}\t${config_host}\t${config_host_disease}\t${sample_id}"
			chunk3="${config_isolation_source}\t${config_antiviral_treatment_agent}\t${config_collection_device}"
			chunk4="${config_collection_method}\t${config_date_of_prior_antiviral_treat}\t${config_date_of_prior_sars_cov_2_infection}"
			chunk5="${config_date_of_sars_cov_2_vaccination}\t${config_exposure_event}\t${config_geo_loc_exposure}"
			chunk6="${gisaid_accession}\t${virus_name}\t${config_host_age}\t${config_host_anatomical_material}\t${config_host_anatomical_part}"
			chunk7="${config_host_body_product}\t${config_host_disease_outcome}\t${config_host_health_state}\t${config_host_recent_travel_loc}"
			chunk8="${config_host_recent_travel_return_date}\t${config_host_sex}\t${config_host_specimen_voucher}\t${config_host_subject_id}"
			chunk9="${config_lat_lon}\t${config_passage_method}\t${config_passage_number}\t${config_prior_sars_cov_2_antiviral_treat}\t${config_prior_sars_cov_2_infection}"
			chunk10="${config_prior_sars_cov_2_vaccination}\t${config_purpose_of_sampling}\t${config_purpose_of_sequencing}\t${config_sars_cov_2_diag_gene_name_1}"
			chunk11="${config_sars_cov_2_diag_gene_name_2}\t${config_sars_cov_2_diag_pcr_ct_value_1}\t${config_sars_cov_2_diag_pcr_ct_value_2}"
			chunk12="${config_sequenced_by}\t${config_vaccine_received}\t${config_virus_isolate_of_prior_infection}\t${config_description}"
			
			#add output variables to attributes file
			echo -e "${chunk1}\t${chunk2}\t${chunk3}\t${chunk4}\t${chunk5}\t${chunk6}\t${chunk7}\t${chunk8}\t${chunk9}\t${chunk10}\t${chunk11}\t${chunk12}" >> $ncbi_attributes
		
			# breakoutput into chunks
			chunk1="${sc_id}\t${sample_id}\t${sample_title}\t${config_library_strategy}\t${config_library_source}\t${config_library_selection}"
			chunk2="${config_library_layout}\t${config_platform}\t${config_instrument_model}\t${config_design_description}\t${config_filetype}\t${sample_id}_R1.fastq.gz"
			chunk3="${sample_id}_R2.fastq.gz\t${config_filename3}\t${config_filename4}\t${assembly}\t${config_fasta_file}"

			#add output variables to attributes file
                        echo -e "${chunk1}\t${chunk2}\t${chunk3}" >> $ncbi_metadata
            fi
        done
fi

if [[ "$pipeline_download" == "Y" ]]; then
	echo "----DOWNLOADING SAMPLES"

	# create tmp ncbi hold dir
	if [[ ! -d $ncbi_hold ]]; then mkdir -p $ncbi_hold; fi	

	# download fastq files for samples uploaded to gisaid	
	for f in `ls -1 "$fasta_partial"`; do
		download_name=`echo $f | cut -f1 -d"."`
		#$basespace_command download biosample -n ${download_name} -o $ncbi_hold
	done

	# remove json files, move all fastq files
	if [[ ! -d $ncbi_hold/complete ]]; then mkdir $ncbi_hold/complete; fi
	rm $ncbi_hold/*.json
	mv $ncbi_hold/*L1*/*fastq.gz $ncbi_hold/complete

	# make sure downloads match metadata 
	fq_num=`ls ${ncbi_hold}/complete/*.gz | wc -l`
	meta_full_num=`cat $ncbi_metadata | wc -l`
	meta_num=$((meta_full_num-1))
	meta_num=$((meta_num*2))

	if [[ $meta_num -eq $fq_num ]]; then
		
		# rename files
		for f in $ncbi_hold/complete/*; do
			sample_id=`echo $f | cut -f5 -d "/" | cut -f1 -d"-"`
			r_version=`echo $f | cut -f5 -d "/" | cut -f2 -d"R" | cut -f1 -d"_"`
			new_name=`echo ${sample_id}_R${r_version}.fastq.gz`
			mv $f $ncbi_hold/complete/$new_name
		done

		# move meta and attributes 
		cp $ncbi_metadata $ncbi_hold/complete/metadata.tsv
		cp $ncbi_attributes $ncbi_hold/complete/attributes.tsv

		echo "--samples downloaded"
	else
		echo "The number of samples downloaded does not match the number of entries in the metadata files"
		echo "fq is $fq_num"
		echo "mt is $meta_num"
		exit
	fi	
fi

if [[ "$pipeline_sra" == "Y" ]]; then
	echo "----RUNNING QC"

	# create tmp file lists
	## complete sample ids for project
	## samples that were uploaded to NCBI
	## samples that were not uploaded
	cat $final_results | cut -f1 -d"," > tmp_full.txt
        sed -i "s/sample_id//g" tmp_full.txt
        sed -i '/^$/d' tmp_full.txt

	cat $ncbi_output | awk -F"\t" '{ print $6 }' > tmp_sra.txt
        sed -i "s/SC/202/g" tmp_sra.txt
	sed -i "s/sample_name//g" tmp_sra.txt
        comm -23 <(sort tmp_full.txt) <(sort tmp_sra.txt) > tmp_missing.txt

	# create final ncbi output 
	awk '{print $1",qc_fail,NA"}' tmp_missing.txt > $ncbi_results
	 
	# iterate through all samples that passed
	samples_uploaded=`cat tmp_sra.txt`
	for sample_id in ${samples_uploaded[@]}; do
		sra_id=`cat $ncbi_output | grep $sample_id | awk -F"\t" '{ print $1 }'`
		echo "${sample_id},ncbi_pass,$sra_id" >> $ncbi_results
		mv $output_dir/analysis/fasta/upload_partial/$sample_id* $output_dir/analysis/fasta/upload_complete
	done

	# merge ncbi results to final results file by sample id
    	sort $ncbi_results > tmp_nresults.txt
	sort $final_results > tmp_fresults.txt
	echo "sample_id,ncbi_status,ncbi_notes,gisaid_status,gisaid_notes,pango_qc,nextclade_clade,pangolin_lineage,pangolin_scorpio,aa_substitutions" > $final_results
	join <(sort tmp_nresults.txt) <(sort tmp_fresults.txt) -t $',' >> $final_results
	
	#cleanup
	rm tmp_*.txt
	
	# store ncbi output file
	cp $ncbi_output $output_dir/logs
fi
