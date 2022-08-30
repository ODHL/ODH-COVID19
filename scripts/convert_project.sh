# create dirs
dir_list=(logs analysis);\
project_name="OH-M2941-211115";\
date_stamp="20211115";\
final_output="analysis/final_results_$date_stamp.csv";\
for pd in "${dir_list[@]}"; do if [[ ! -d $pd ]]; then mkdir -p $pd; fi; done;\
dir_list=(fasta intermed);\
for pd in "${dir_list[@]}"; do if [[ ! -d analysis/$pd ]]; then mkdir -p analysis/$pd; fi; done;\
dir_list=(not_uploaded upload_complete upload_partial upload_failed);\
for pd in "${dir_list[@]}"; do if [[ ! -d analysis/fasta/$pd ]]; then mkdir -p analysis/fasta/$pd; fi; done;\
cp /c/Users/33245250/Documents/GitHub/ODH-COVID19/config/* logs;\
sed -i "s/merged_complete.csv/metadata_${project_name}.csv/" "logs/config_pipeline.yaml";\
mv GISAID_logs/*/* logs;\
echo "sample_id,gisaid_status,gisaid_notes,pango_qc,nextclade_clade,pangolin_lineage,pangolin_scorpio,aa_substitutions">$final_output;\
cat logs/qc_failed.txt>>$final_output;\
sed -i "s/_consensus.fasta /,qc_fail,qc_/g" $final_output;\
sed -i "s/%/%_Ns/g" $final_output;\
aa_file="/l/Micro/Gen Micro/Whole Genome Sequencing/Coronavirus_WGS/COVID-19 Fastas/analysis/mutation_analysis/aa_download_05172022/ohio_aadownload_01012022_to_05172022_sub.csv";\
IFS=$'\n' read -d '' -r -a sample_list < "logs/qc_passed.txt";\
for sample_line in "${sample_list[@]}"; do
    sample_id=`echo "${sample_line}" | cut -f10 -d"/" | cut -f1 -d"_"`;\
    aa_line=`cat "${aa_file}" | grep "${sample_id}"`;\
    gisaid_id=`echo "${aa_line}" | cut -f2 -d","`;\
    pangolin_lineage=`echo "${aa_line}" | cut -f3 -d","`;\
    nextclade_clade=`echo "${aa_line}" | cut -f4 -d","`;\
    aa_substitutions=`echo "${aa_line}" | cut -f2 -d"(" | sed "s/)//g"`;\
    echo "${sample_id},gisaid_pass,${gisaid_id},passed_qc,${nextclade_clade},${pangolin_lineage},,"${aa_substitutions}"">>$final_output;\
done;\
error_log="fastas_GISAID_errors/error_log.txt";\
IFS=$'\n' read -d '' -r -a sample_list < $error_log;\
for sample_line in "${sample_list[@]}"; do
    sample_id=`echo "${sample_line}" | cut -f3 -d"/" | cut -f2 -d"-"`;\
    sed -i "s/$sample_id,gisaid_pass/$sample_id,gisaid_rejected/g" $final_output;\
done;\
mv "Fastas - GISAID Not Complete/"*fasta analysis/fasta/not_uploaded;\
mv fastas_GISAID_errors/*fasta analysis/fasta/upload_failed;\
mv fastas_GISAID_errors/error_log* analysis/intermed/gisaid_rejected.txt;\
mv fastas_GISAID_uploaded/*fasta analysis/fasta/upload_partial;\
mv gisaid_log* logs;\
mv monroe* analysis;\
mv fastas_GISAID_errors/metadata* logs/metadata_gisaid_failed.csv;\
mv logs/qc_passed* analysis/intermed/gisaid_passed.txt;\
for f in analysis/fasta/*/*; do new_name=`echo $f | sed "s/_consensus//g"`; mv $f $new_name; done;\
rm -r fastas*;\
rm -r Fastas*;\
rm -r GISAID*;\
rm logs/warning*