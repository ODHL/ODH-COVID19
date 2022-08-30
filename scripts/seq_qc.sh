#########################################################
# Set args
#########################################################
output_dir=$1

#########################################################
# Eval, source
#########################################################
source ./scripts/functions.sh
eval $(parse_yaml ${pipeline_config} "config_")

#########################################################
# Set dirs, files, variables
#########################################################
fasta_notuploaded=$output_dir/analysis/fasta/not_uploaded

#########################################################
# Run QC
#########################################################
sample_pass=0
sample_fail=0
for f in `ls -1 "$fasta_notuploaded"`; do
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
        ((sample_fail+=1))
    else
        ((sample_pass+=1))
    fi
done

echo "----The total number of samples passing QC is $sample_pass"
echo "----The total number of samples failing QC is $sample_fail"