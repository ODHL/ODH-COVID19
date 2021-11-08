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

#set dir
failed_dir="$run_dir/failed_qc"
merged_dir="$run_dir/merged_upload"

#create files to track changes
failed_list="$run_dir/qc_failed.txt"
passed_list="$run_dir/qc_passed.txt"
touch $failed_list
touch $passed_list

# Parse FASTA file for N, create filtered lists
for f in $project_dir/*.fasta; do
    #determine total number of seq
    total_num=`cat $f | grep -v ">" | wc -m`
    
    #determine total number of N
    n_num=`cat $f | tr -d -c 'N' | awk '{ print length; }'`

    #if the frequency is higher than 50$ GISAID will reject
    #move failed files to failed folder and add to list
    #move passed files to merged folder 
    if [[ "$(($n_num*100/$total_num))" -gt $((percent_n)) ]]; then
        echo "$f \t $(($n_num*100/$total_num))%" >> $failed_list
        cp $f "$failed_dir"
    else
        #rename file
        ## grab header line
        #pull the last infor after any _ or - 
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
            sed "s/>.*/>${new_header}/" $f > "$merged_dir/$new_header.fasta"

        #if meta is not found, add to failed list
        else
            echo "$f\tMissing metadata" >> $failed_list
            cp $f "$failed_dir"
        fi
    fi
done

# Create manifest for upload
#---- batched_metadata.csv
# Create merged FASTA file for upload
#---- batched_fasta.fasta

#sh /Users/sevillas2/Desktop/APHL/ODH-COVID19/GSIAD.sh -p /Users/sevillas2/Desktop/APHL/test_data/OH-123