#########################################################
# ARGS
#########################################################
project_dir=$1
run_dir=$2
metadata_file=$3
percent_n=$4

#########################################################
# Code
#########################################################

#create files to track changes
failed_list="$run_dir/qc_failed.txt"
passed_list="$run_dir/qc_passed.txt"
touch $failed_list
touch $passed_list

# Parse FASTA file for N, create filtered lists
for f in "$project_dir/Fastas\ -\ GISAID\ Not\ Complete/*.fasta"; do
    #determine total number of seq
    total_num=`cat $f | grep -v ">" | wc -m`
    
    #determine total number of N
    n_num=`cat $f | tr -d -c 'N' | awk '{ print length; }'`

    #if the frequency is higher than 50$ GISAID will reject
    #move failed files to failed folder and add to list
    if [[ "$(($n_num*100/$total_num))" -gt $((percent_n)) ]]; then
        echo "$f \t $(($n_num*100/$total_num))%" >> $failed_list
    else
        #rename file
        ## grab header line
        #pull the last info after any _ or - 
        ori_header=`cat $f | grep ">"`
        header=`echo $ori_header | awk -F'-' '{print $NF}' | awk -F'_' '{print $NF}'`
        
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
        meta=`cat $metadata_file | grep "$new_header"`

        #if meta is found
        if [[ ! "$meta" == "" ]]; then
            #add new / old header to qc passted file
            echo "$ori_header\t$new_header" >> $passed_list

            #replace header in file, move and rename
            sed "s/>.*/>${new_header}/" $f > "$run_dir/$new_header.fasta"

        #if meta is not found, add to failed list
        else
            echo "$f\tMissing metadata" >> $failed_list
            cp $f "$failed_dir"
        fi
    fi
done

# Create manifest for upload
#---- batched_metadata.csv

header1=["submitter" "fn" "covv_virus_name" "covv_type" "covv_passage" "covv_collection_date" "covv_location" "covv_add_location" \
"covv_host" "covv_add_host_info" "covv_sampling_strategy" "covv_gender" "covv_patient_age" "covv_patient_status" "covv_specimen" \
"covv_outbreak" "covv_last_vaccinated" "covv_treatment" "covv_seq_technology" "covv_assembly_method" "covv_coverage" "covv_orig_lab" \
"covv_orig_lab_addr" "covv_provider_sample_id" "covv_subm_lab" "covv_subm_lab_addr" "covv_subm_sample_id" "covv_authors" "covv_comment" "comment_type"]

header_names=["Submitter" "FASTA filename" "Virus name" "Type" "Passage details/history" "Collection date" "Location" \
"Additional location information" "Host" "Additional host information" "Sampling Strategy" "Gender" "Patient age" \
"Patient status" "Specimen source" "Outbreak" "Last vaccinated" "Treatment" "Sequencing technology" "Assembly method" \
"Coverage" "Originating lab" "Address" "Sample ID given by originating laboratory" "Submitting lab" "Address" \
"Sample ID given by the submitting laboratory" "Authors" "Comment" "Comment Icon"]

#to auto populate

# #the filename that contains the sequence without path (e.g. all_sequences.fasta not c:\users\meier\docs\all_sequences.fasta)
# FASTA_filename=$f

# #hCoV-19/Netherlands/Gelderland-01/2020 (Must be FASTA-Header from the FASTA file all_sequences.fasta)
# virus_name=$new_header

# #Date in the format YYYY or YYYY-MM or YYYY-MM-DD
# #convert date to format above 4/21/81	9/22/21
# collection_date=$meta[2]

# #e.g. Europe / Germany / Bavaria / Munich
# location=$meta[3]

# #e.g.  65 or 7 months, or unknown 
# #YYYY or YYYY-MM or YYYY-MM-DD
# #convert birthday to format above 4/21/81	9/22/21
# patient_age=$collection_date - #converted_birthday

# #given by the originating laboratory
# sample_ID_o=""

# ##given by the submitting laboratory
# sample_ID_s=""

# # Create merged FASTA file for upload
# #---- batched_fasta.fasta

# #sh /Users/sevillas2/Desktop/APHL/ODH-COVID19/GSIAD.sh -p /Users/sevillas2/Desktop/APHL/test_data/OH-123

# specimen_source: ""	#Sputum, Alveolar lavage fluid, Oro-pharyngeal swab, Blood, Tracheal swab, Urine, Stool, Cloakal swab, Organ, Feces, Other
