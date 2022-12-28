# proj info
project_name="OH-M2941-211115";\
dir_list=(logs analysis);\
for pd in "${dir_list[@]}"; do if [[ ! -d $project_name/$pd ]]; then mkdir -p $project_name/$pd; fi; done;\
dir_list=(fasta intermed);\
for pd in "${dir_list[@]}"; do if [[ ! -d $project_name/analysis/$pd ]]; then mkdir -p $project_name/analysis/$pd; fi; done;\
dir_list=(not_uploaded upload_complete upload_partial upload_failed);\
for pd in "${dir_list[@]}"; do if [[ ! -d $project_name/analysis/fasta/$pd ]]; then mkdir -p $project_name/analysis/fasta/$pd; fi; done

#copy configs, logs
project_name="OH-M2941-211115";\
cp /c/Users/33245250/Documents/GitHub/ODH-COVID19/config/* $project_name/logs;\
sed -i "s/merged_complete.csv/metadata_${project_name}.csv/" "$project_name/logs/config_pipeline.yaml";\
mv $project_name/GISAID_logs/*/* $project_name/logs;\
cat $project_name/"Fastas - GISAID Not Complete"/qc_failed.txt >> logs/qc_failed.txt
mv $project_name/"fastas_GISAID_errors"/*final* $project_name/logs;\
mv $project_name/"fastas_GISAID_errors"/*txt $project_name/logs;\
mv $project_id/"fastas_GISAID_uploaded/"/*sample_log* $project_name/logs;\
mv project_name/monroe* $project_name/logs

#process passed samples
project_name="OH-M2941-211115";\
date_stamp="20211115";\
final_output="$project_name/analysis/final_results_$date_stamp.csv";\
aa_file="/c/Users/33245250/Documents/GitHub/ODH-COVID19/scripts/gisaid_hcov-19.tsv";\
echo "sample_id,gisaid_status,gisaid_notes,pango_status,pangolin_lineage,pangolin_scorpio,pangolin_version,nextclade_clade,aa_substitutions">$final_output;\
IFS=$'\n' read -d '' -r -a sample_list < "$project_name/logs/qc_passed.txt";\
for sample_line in "${sample_list[@]}"; do
    sample_id=`echo "${sample_line}" | cut -f10 -d"/" | cut -f1 -d"_"`;\
    convert_id=`echo ${sample_id} | sed "s/202/SC/g"`;\
    aa_line=`cat "${aa_file}" | grep "${convert_id}"`;\
    if [[ $aa_line == "" ]]; then
        gisaid_status="fail";\
        gisaid_id="NA";\
        pangolin_lineage="NA";\
        aa_substitutions="NA";\
    else
        gisaid_status="pass";\
        gisaid_id=`echo "${aa_line}" | awk -F"\t" '{ print $2 }'`;\
        pangolin_lineage=`echo "${aa_line}" | awk -F"\t" '{ print $15 }'`;\
        aa_substitutions=`echo "${aa_line}" | awk -F"\t" '{ print $17 }'`;\
    fi;\
    nextclade_clade="NA";\
    final_line=`echo "${sample_id},gisaid_$gisaid_status,${gisaid_id},$gisaid_status,${pangolin_lineage},NA,MONROE,${nextclade_clade},${aa_substitutions}"`;\
    echo $final_line | sed "s/(/\"/g" | sed "s/)/\"/g">>$final_output;\
done

#process failed samples, prep fastas
project_name="OH-M2941-211115";\
date_stamp="20211115";\
final_output="$project_name/analysis/final_results_$date_stamp.csv";\
cat logs/qc_failed.txt >>$final_output;\
sed -i "s/_consensus.fasta /,qc_fail,qc_,fail,NA,NA,MONROE,NA,NA/g" $final_output;\
sed -i "s/%/%_Ns/g" $final_output;\
error_log="fastas_GISAID_errors/error_log.txt";\
mv $project_name/"Fastas - GISAID Not Complete/*.fa*" $project_name/analysis/fasta/not_uploaded;\
mv $project_name/"fastas_GISAID_errors/*fa*" $project_name/analysis/fasta/not_uploaded;\
mv $project_name/"fastas_GISAID_uploaded/*fa*" $project_name/analysis/fasta/not_uploaded

#process fastas
project_name="OH-M2941-211115";\
date_stamp="20211115";\
final_output="$project_name/analysis/final_results_$date_stamp.csv";\
for fasta_id in `ls $project_name/analysis/fasta/not_uploaded`; do
    sample_id=`echo $fasta_id | cut -f5 -d"/" | cut -f1 -d"."`;\
    status=`cat $final_output | grep $sample_id | cut -f2 -d","`;\
    if [[ $status == "gisaid_pass" ]]; then
        echo "pass $sample_id"
        mv $fasta_id $project_name/analysis/fasta/not_uploaded/$sample_id.fa
    else
        echo "fail $sample_id"
        mv $fasta_id $project_name/analysis/fasta/upload_partial/$sample_id.fa
    fi;\
done
# rm -r fastas*;\
# rm -r Fastas*;\
# rm -r GISAID*;\
# rm logs/warning*