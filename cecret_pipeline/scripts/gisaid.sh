#########################################################
# ARGS
#########################################################
run_dir=$1
fastas_dir=$2

#########################################################
# functions
#########################################################
config_format() {
    input_variable="'$*'"
    
    if [[ "$input_variable" == "''" ]]; then
        input_variable=","
    else
		#convert spaces to - so that single variables are not split into multiple columns
        input_variable=`echo $input_variable | awk '{ gsub(" ", "-") ; print $0 }'`
        input_variable=`echo $input_variable | awk '{ gsub(",", "\,") ; print $0 }'`
    fi
}

metadata_output() {
    input_array=("$@")
    array_echo=""

    #for each element of array, bind with "\t" and print to output
    for h in ${input_array[@]}; do
        if [ "$array_echo" == "" ]; then 
            array_echo=`echo "${h}"`
        elif [ "$h" == "," ]; then 
            array_echo=`echo "${array_echo}${h}"`
        else
            array_echo=`echo "${array_echo},${h}"`
        fi
    done
    
    #fix temporary substitutions
    array_output=`echo $array_echo | awk '{ gsub("-", " ") ; print $0 }'` #corrects header
    array_output=`echo $array_output | awk '{ gsub("'\''", "") ; print $0 }'` #corrects authors
	array_output=`echo $array_output | awk '{ gsub("*", "-") ; print $0 }'` #corrects virus name

    #output to metadata file
    echo $array_output >> $batched_meta
}

#########################################################
# yaml location
#####################################################
yaml_location="${run_dir}"/gisaid_config.yaml

#########################################################
# Dirs, files
#########################################################
#create files to track changes
echo "----Creating log files"
failed_list="$run_dir/qc_failed.txt"
passed_list="$run_dir/qc_passed.txt"
batched_fasta="$gisaid_dir/batched_fasta_input.fasta"
batched_meta="$gisaid_dir/batched_meta_${date_stamp}_${project_id}.csv"
touch "${failed_list}"
touch "${passed_list}"
touch "${batched_fasta}"
touch "${batched_meta}"

#########################################################
# Code
#########################################################
#remove trailing / 
project_dir=$(cat "${yaml_location}" | grep "project_dir: " | sed 's/project_dir: //' | sed 's:/*$::' | sed 's/"//g')

# Create manifest for upload
## set headers; echo to metadata_input
header_1=("submitter" "fn" "covv_virus_name" "covv_type" "covv_passage" "covv_collection_date" "covv_location" "covv_add_location" \
"covv_host" "covv_add_host_info" "covv_sampling_strategy" "covv_gender" "covv_patient_age" "covv_patient_status" "covv_specimen" \
"covv_outbreak" "covv_last_vaccinated" "covv_treatment" "covv_seq_technology" "covv_assembly_method" "covv_coverage" "covv_orig_lab" \
"covv_orig_lab_addr" "covv_provider_sample_id" "covv_subm_lab" "covv_subm_lab_addr" "covv_subm_sample_id" "covv_authors" "covv_comment" "comment_type")
metadata_output "${header_1[@]}"

header_2=("Submitter" "FASTA-filename" "Virus-name" "Type" "Passage-details/history" "Collection-date" "Location" \
"Additional-location-information" "Host" "Additional-host-information" "Sampling-Strategy" "Gender" "Patient-age" \
"Patient-status" "Specimen-source" "Outbreak" "Last-vaccinated" "Treatment" "Sequencing-technology" "Assembly-method" \
"Coverage" "Originating-lab" "Address" "Sample-ID-given-by-originating-laboratory" "Submitting-lab" "Address" \
"Sample-ID-given-by-the-submitting-laboratory" "Authors" "Comment" "Comment-Icon")
metadata_output "${header_2[@]}"

# Parse FASTA file for N, create filtered lists
#ls -1 "$project_dir"/"Fastas - GISAID Not Complete"
echo "------------------Processing Samples"
for f in `ls -1 "$project_dir"/"Fastas - GISAID Not Complete"`; do
	#skip the log text file
	if [[ "$f" == *".txt"* ]]; then continue; fi
	
	#id sample
	echo "---------------------------$f"
	
	#set full file path
	full_path="$project_dir"/"Fastas - GISAID Not Complete"/$f
	
    #determine total number of seq
    total_num=`cat "$full_path" | grep -v ">" | wc -m`

	#if the file is empty, set equal to 1
	if [ "$total_num" -eq 0 ]; then total_num=1; fi

    #determine total number of N
    n_num=`cat "$full_path" | tr -d -c 'N' | awk '{ print length; }'`
	
	#if there are no N's set value to 1
	if [ ! -n "$n_num" ]; then n_num=1; fi
	
    #if the frequency is higher than 50$ GISAID will reject
    #move failed files to failed folder and add to list
	config_percent_n=$(cat "${yaml_location}" | grep "percent_n: " | sed 's/percent_n: //' | sed 's/"//g')
    if [[ "$(($n_num*100/$total_num))" -gt $((config_percent_n)) ]]; then
        echo "$f $(($n_num*100/$total_num))%" >> $failed_list
    else
        ## grab header line
        full_header=`cat "$full_path" | grep ">"`
        header=`echo $full_header | awk -F'-' '{print $NF}' | awk -F'_' '{print $NF}'`
        
        #if header has a / then rearraign, otherwise use header
        header_split=`echo $header | awk '{ gsub(">", "") ; print $0 }' | awk '{ gsub("SC", "") ; print $0 }' | awk -F'/' '{print $1,$2}'`

        #create array, determine if need to concatonate
        IFS=' ' read -ra header_array <<< "$header_split"

		#if the header starts with 202 then leave it alone
		header_check=`echo ${header_array[0]} | cut -c1-4`
		if [[ "$header_check" == "202"* ]]; then
			new_header=${header_array[0]}
		#otherwise add 202 to the header
		else
			new_header="202${header_array[0]}"
		fi

        #find associated metadata
        config_metadata_file=$(cat "${yaml_location}" | grep "metadata_file: " | sed 's/metadata_file: //' | sed 's/"//g')
		meta=`cat "$config_metadata_file" | grep "$new_header"`

        #if meta is found create input metadata row
        if [[ ! "$meta" == "" ]]; then
			
            #the filename that contains the sequence without path (e.g. all_sequences.fasta not c:\users\meier\docs\all_sequences.fasta)
            IFS='/' read -r -a strarr <<< "$full_path"
            #FASTA_filename="${strarr[${#strarr[@]}-1]}" #this is single file name - not needed for batched upload
            FASTA_filename="batched_fasta_input.fasta"
			
            #hCoV-19/Netherlands/Gelderland-01/2020 (Must be FASTA-Header from the FASTA file all_sequences.fasta)
			#take header (IE 2021064775) and turn into correct version hCoV-19/USA/OH-xxx/YYYY
			year=`echo $new_header | cut -c1-4`
			virus_name="hCoV*19/USA/OH*$new_header/$year"

            #Date in the format YYYY or YYYY-MM or YYYY-MM-DD
            #convert date to format above - 4/21/81 to 1981-04-21
			#add space to avoid errors with excel conversion
			raw_date=`echo $meta | awk -F',' '{print $1}' | sed 's/-/*/g'`
			collection_date=`echo "${raw_date}"-`

            #e.g. Europe / Germany / Bavaria / Munich
			county=`echo ${meta} | awk -F',' '{print $3}'`
            location=`echo North-America/USA/$county | sed 's/"//g'`
			
            #e.g.  65 or 7 months, or unknown 
            patient_age=`echo $meta | awk -F',' '{print $6}'`

            #given by the originating laboratory
            sample_ID_o=`echo $meta | awk -F',' '{print $4}'`

            #given by the submitting laboratory
            sample_ID_s=`echo $meta | awk -F',' '{print $5}'`

            #format config variables
			config_submitter=$(cat "${yaml_location}" | grep "submitter: " | sed 's/submitter: //' | sed 's/"//g')
            config_format ${config_submitter}
            submitter=$input_variable
            
			config_type=$(cat "${yaml_location}" | grep "type: " | sed 's/type: //' | sed 's/"//g')
            config_format ${config_type}
            type=$input_variable
            
			config_passage=$(cat "${yaml_location}" | grep "passage: " | sed 's/passage: //' | sed 's/"//g')
            config_format ${config_passage}
            passage=$input_variable
            
			config_additional_location_information=$(cat "${yaml_location}" | grep "additional_location_information: " | sed 's/additional_location_information: //' | sed 's/"//g')
            config_format ${config_additional_location_information}
            additional_location_information=$input_variable
            
			config_host=$(cat "${yaml_location}" | grep "host: " | sed 's/host: //' | sed 's/"//g')
            config_format ${config_host}
            host=$input_variable
            
			config_additional_host_information=$(cat "${yaml_location}" | grep "additional_host_information: " | sed 's/additional_host_information: //' | sed 's/"//g')
            config_format ${config_additional_host_information}
            additional_host_information=$input_variable
            
			config_sampling_strategy=$(cat "${yaml_location}" | grep "sampling_strategy: " | sed 's/sampling_strategy: //' | sed 's/"//g')
            config_format ${config_sampling_strategy}
            sampling_strategy=$input_variable
            
			config_gender=$(cat "${yaml_location}" | grep "gender: " | sed 's/gender: //' | sed 's/"//g')
            config_format ${config_gender}
            gender=$input_variable
            
			config_patient_status=$(cat "${yaml_location}" | grep "patient_status: " | sed 's/patient_status: //' | sed 's/"//g')
            config_format ${config_patient_status}
            patient_status=$input_variable
            
			config_specimen_source=$(cat "${yaml_location}" | grep "specimen_source: " | sed 's/specimen_source: //' | sed 's/"//g')
            config_format ${config_specimen_source}
            specimen_source=$input_variable
            
			config_outbreak=$(cat "${yaml_location}" | grep "outbreak: " | sed 's/outbreak: //' | sed 's/"//g')
            config_format ${config_outbreak}
            outbreak=$input_variable
            
			config_last_vaccinated=$(cat "${yaml_location}" | grep "last_vaccinated: " | sed 's/last_vaccinated: //' | sed 's/"//g')
            config_format ${config_last_vaccinated}
            last_vaccinated=$input_variable
            
			config_treatment=$(cat "${yaml_location}" | grep "treatment: " | sed 's/treatment: //' | sed 's/"//g')
            config_format ${config_treatment}
            treatment=$input_variable
            
			config_sequencing_technology=$(cat "${yaml_location}" | grep "sequencing_technology: " | sed 's/sequencing_technology: //' | sed 's/"//g')
            config_format ${config_sequencing_technology}
            sequencing_technology=$input_variable
            
			config_assembly_method=$(cat "${yaml_location}" | grep "assembly_method: " | sed 's/assembly_method: //' | sed 's/"//g')
            config_format ${config_assembly_method}
            assembly_method=$input_variable
            
			config_coverage=$(cat "${yaml_location}" | grep "coverage: " | sed 's/coverage: //' | sed 's/"//g')
            config_format ${config_coverage}
            coverage=$input_variable

			config_submitting_lab=$(cat "${yaml_location}" | grep "submitting_lab: " | sed 's/submitting_lab: //' | sed 's/"//g')
            config_format ${config_submitting_lab}
            submitting_lab=$input_variable

			config_address_submitting=$(cat "${yaml_location}" | grep "address_submitting: " | sed 's/address_submitting: //' | sed 's/"//g')
            config_format ${config_address_submitting}
            address_submitting=$input_variable
            
			config_authors=$(cat "${yaml_location}" | grep "authors: " | sed 's/authors: //' | sed 's/"//g')
            config_format ${config_authors}
            authors=$input_variable

            #add output variables to metadata file
            metadata_array=`echo "${submitter} ${FASTA_filename} \
            ${virus_name} ${type} ${passage} ${collection_date} ${location} \
            ${additional_location_information} ${host} ${additional_host_information} \
            ${sampling_strategy} ${gender} ${patient_age} ${patient_status} \
            ${specimen_source} ${outbreak} ${last_vaccinated} ${treatment} \
            ${sequencing_technology} ${assembly_method} ${coverage} \"${submitting_lab}\" \
            \"${address_submitting}\" ${sample_ID_o} \"${submitting_lab}\" \"${address_submitting}\" \
            ${sample_ID_s} \"${authors}\""`

            metadata_output "${metadata_array[@]}"

            #add file name to log
            echo "$full_path" >> $passed_list
			
            # merge all fasta files that pass QC and metadata into one
			# skips the header line and any odd formatted /date lines that follow
            echo ">$virus_name" | sed 's/*/-/g' >> $batched_fasta
			cat "$full_path" | grep -v ">" | grep -v "/" >> $batched_fasta
			
			#move merged files to completed dir
			mv "$full_path" "$fastas_dir"/$f

        #if meta is not found, add to failed list
        else
            echo "$f Missing metadata" >> $failed_list
        fi
    fi
done

#add qc failure log to not complete folder
failed_compiled="$project_dir/Fastas - GISAID Not Complete/qc_failed.txt"
if [[ ! -f "$failed_compiled" ]]; then touch "$failed_compiled"; fi
cat "$failed_list" >> "$failed_compiled"

