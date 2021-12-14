#########################################################
# ARGS
#########################################################
run_dir=$1

#########################################################
# functions
#########################################################
#handle yaml file
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

config_format() {
    input_variable="'$*'"
    
    if [[ "$input_variable" == "''" ]]; then
        input_variable=","
    else
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
    
    #convert "-" to " " for header
    array_output=`echo $array_echo | awk '{ gsub("-", " ") ; print $0 }'`
    array_output=`echo $array_output | awk '{ gsub("'\''", "") ; print $0 }'`

    #output to metadata file
    echo $array_output >> $batched_meta
}

#########################################################
# parse yaml
#########################################################
eval $(parse_yaml "${run_dir}/gisaid_config.yaml" "config_")

#########################################################
# Code
#########################################################
#create files to track changes
failed_list="$run_dir/qc_failed.txt"
passed_list="$run_dir/qc_passed.txt"
batched_meta="$run_dir/batched_metadata_input.csv"
batched_fasta="$run_dir/batched_fasta_input.fasta"
touch $failed_list
touch $passed_list
touch $batched_fasta

#remove trailing / 
project_dir=$(echo $config_project_dir | sed 's:/*$::')

#make tmp dir without spaces in name
gisaid_dir="$project_dir/tmp"
if [[ ! -d "${gisaid_dir}" ]]; then mkdir -p "${gisaid_dir}"; fi
cp -r "$project_dir/Fastas - GISAID Not Complete/"* $gisaid_dir 

# Create manifest for upload
touch $batched_meta

#set headers; echo to metadata_input
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
for f in "$gisaid_dir/"*; do

    #determine total number of seq
    total_num=`cat $f | grep -v ">" | wc -m`
    
    #determine total number of N
    n_num=`cat $f | tr -d -c 'N' | awk '{ print length; }'`

    #if the frequency is higher than 50$ GISAID will reject
    #move failed files to failed folder and add to list
    if [[ "$(($n_num*100/$total_num))" -gt $((config_percent_n)) ]]; then
        echo "$f \t $(($n_num*100/$total_num))%" >> $failed_list
    else
        ## grab header line
        full_header=`cat $f | grep ">"`
        header=`echo $full_header | awk -F'-' '{print $NF}' | awk -F'_' '{print $NF}'`
        
        # #if header has a / then rearraign, otherwise use header
        header_split=`echo $header | awk '{ gsub(">", "") ; print $0 }' | awk '{ gsub("SC", "") ; print $0 }' | awk -F'/' '{print $1,$2}'`

        #create array, determine if need to concatonate
        IFS=' ' read -ra header_array <<< "$header_split"

        #if there are multiple elements of header
        if [[ ${#header_array[@]} -gt 1 ]]; then 

            #check if sample is from 2021
            if [[ "${header_array[1]}" == "2021" ]]; then
                #if it is then new header is 2021 followed by number without SC
                new_header="${header_array[1]}${header_array[0]}"
            #otherwise it's 2021 + 1 + number without SC
            else
                new_header="${header_array[1]}1${header_array[0]}"
            fi 
        else
            new_header=${header_array[0]}
        fi

        #find associated metadata
        meta=`cat $config_metadata_file | grep "$new_header"`

        #if meta is found create input metadata row
        if [[ ! "$meta" == "" ]]; then
            #the filename that contains the sequence without path (e.g. all_sequences.fasta not c:\users\meier\docs\all_sequences.fasta)
            IFS='/' read -r -a strarr <<< "$f"
            FASTA_filename="${strarr[${#strarr[@]}-1]}"
            
            #hCoV-19/Netherlands/Gelderland-01/2020 (Must be FASTA-Header from the FASTA file all_sequences.fasta)
            virus_name=$full_header

            #Date in the format YYYY or YYYY-MM or YYYY-MM-DD
            #convert date to format above 4/21/81	9/22/21
            collection_date=`echo $meta | awk -F',' '{print $1}'`

            #e.g. Europe / Germany / Bavaria / Munich
            location=`echo $meta | awk -F',' '{print $3}'`
            
            #e.g.  65 or 7 months, or unknown 
            #YYYY or YYYY-MM or YYYY-MM-DD
            patient_age=`echo $meta | awk -F',' '{print $6}'`

            #given by the originating laboratory
            sample_ID_o=`echo $meta | awk -F',' '{print $4}'`

            #given by the submitting laboratory
            sample_ID_s=`echo $meta | awk -F',' '{print $5}'`

            #format config variables
            config_format ${config_submitter}
            submitter=$input_variable
            
            config_format ${config_type}
            type=$input_variable
            
            config_format ${config_passage}
            passage=$input_variable
            
            config_format ${config_additional_location_information}
            additional_location_information=$input_variable
            
            config_format ${config_host}
            host=$input_variable
            
            config_format ${config_additional_host_information}
            additional_host_information=$input_variable
            
            config_format ${config_sampling_strategy}
            sampling_strategy=$input_variable
            
            config_format ${config_gender}
            gender=$input_variable
            
            config_format ${config_patient_status}
            patient_status=$input_variable
            
            config_format ${config_specimen_source}
            specimen_source=$input_variable
            
            config_format ${config_outbreak}
            outbreak=$input_variable
            
            config_format ${config_last_vaccinated}
            last_vaccinated=$input_variable
            
            config_format ${config_treatment}
            treatment=$input_variable
            
            config_format ${config_sequencing_technology}
            sequencing_technology=$input_variable
            
            config_format ${config_assembly_method}
            assembly_method=$input_variable
            
            config_format ${config_coverage}
            coverage=$input_variable

            config_format ${config_submitting_lab}
            submitting_lab=$input_variable

            config_format ${config_address_submitting}
            address_submitting=$input_variable
            
            config_format ${config_authors}
            authors=$input_variable

            #add file name to log
            echo $f >> $passed_list

            #output variables to metadata file
            metadata_array=`echo "${submitter} ${FASTA_filename} \
            ${virus_name} ${type} ${passage} ${collection_date} ${location} \
            ${additional_location_information} ${host} ${additional_host_information} \
            ${sampling_strategy} ${gender} ${patient_age} ${patient_status} \
            ${specimen_source} ${outbreak} ${last_vaccinated} ${treatment} \
            ${sequencing_technology} ${assembly_method} ${coverage} \"${submitting_lab}\" \
            \"${address_submitting}\" ${sample_ID_o} \"${submitting_lab}\" \"${address_submitting}\" \
            ${sample_ID_s} \"${authors}\""`

            metadata_output "${metadata_array[@]}"

            # merge all fasta files that pass QC and metadata into one
            cat $f >> $batched_fasta
            echo >> $batched_fasta

        #if meta is not found, add to failed list
        else
            echo "$f\tMissing metadata" >> $failed_list
        fi
    fi
done



#remove tmp dir
rm -r $gisaid_dir
