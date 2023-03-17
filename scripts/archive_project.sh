#################################################################
# input args
#################################################################
project_dir=$1
date_stamp=$2

#################################################################
# dirs, files
#################################################################
git_dir="/home/ubantu/analysis_workflow"

final_output="$project_dir/analysis/final_results_$date_stamp.csv"

#################################################################
# variables
#################################################################
aa_file="$git_dir/gisaid_hcov-19.tsv"

#################################################################
# flags
#################################################################
flag_mkdirs="Y"
flag_prep="N"
flag_process_samples="N"
flag_process_failed="N"
flag_process_fastas="N"
#################################################################
# code
#################################################################
cp -r $project_dir saveme

# create dirs
if [[ $flag_mkdirs == "Y" ]]; then
	dir_list=(logs analysis)
	for pd in "${dir_list[@]}"; do if [[ ! -d $project_dir/$pd ]]; then mkdir -p $project_dir/$pd; fi; done
	
	dir_list=(fasta intermed)
	for pd in "${dir_list[@]}"; do if [[ ! -d $project_dir/analysis/$pd ]]; then mkdir -p $project_dir/analysis/$pd; fi; done
	
	dir_list=(not_uploaded upload_complete upload_partial upload_failed)
	for pd in "${dir_list[@]}"; do if [[ ! -d $project_dir/analysis/fasta/$pd ]]; then mkdir -p $project_dir/analysis/fasta/$pd; fi; done
fi

if [[ $flag_prep == "Y" ]]; then
	#copy configs
	cp $git_dir/config/* $project_dir/logs
	sed -i "s/merged_complete.csv/metadata_${project_dir}.csv/" "$project_dir/logs/config_pipeline.yaml"

	# move old logs
	mv $project_dir/GISAID_logs/*/* $project_dir/logs
	mv $project_dir/"fastas_GISAID_errors"/*txt $project_dir/logs
	mv $project_dir/"fastas_GISAID_uploaded/"/*sample_log* $project_dir/logs
	mv $project_dir/monroe* $project_dir/logs
	mv $project_dir/"Fastas - GISAID Not Complete"/qc_failed.txt $project_dir/logs
fi

if [[ $flag_process_samples == "Y" ]]; then
	#process passed samples
	echo "sample_id,gisaid_status,gisaid_notes,pango_status,pangolin_lineage,pangolin_scorpio,pangolin_version,nextclade_clade,aa_substitutions">$final_output;\
	IFS=$'\n' read -d '' -r -a sample_list < "$project_dir/logs/qc_passed.txt";\
	for sample_line in "${sample_list[@]}"; do
    		sample_id=`echo "${sample_line}" | cut -f10 -d"/" | cut -f1 -d"_"`
    		convert_id=`echo ${sample_id} | sed "s/202/SC/g"`
    		aa_line=`cat "${aa_file}" | grep "${convert_id}"`
    		
		if [[ $aa_line == "" ]]; then
        		gisaid_status="fail"
        		gisaid_id="NA"
        		pangolin_lineage="NA"
        		aa_substitutions="NA"
    		else
        		gisaid_status="pass"
        		gisaid_id=`echo "${aa_line}" | awk -F"\t" '{ print $2 }'`
        		pangolin_lineage=`echo "${aa_line}" | awk -F"\t" '{ print $15 }'`
        		aa_substitutions=`echo "${aa_line}" | awk -F"\t" '{ print $17 }'`
    		fi
    
		nextclade_clade="NA"
		final_line=`echo "${sample_id},gisaid_$gisaid_status,${gisaid_id},$gisaid_status,${pangolin_lineage},NA,MONROE,${nextclade_clade},${aa_substitutions}"`
    		echo $final_line | sed "s/(/\"/g" | sed "s/)/\"/g">>$final_output
	done
fi

if [[ $flag_process_failed == "Y" ]]; then
	#process failed samples, prep fastas
	cat logs/qc_failed.txt >>$final_output;\
	sed -i "s/_consensus.fasta /,qc_fail,qc_,fail,NA,NA,MONROE,NA,NA/g" $final_output;\
	sed -i "s/%/%_Ns/g" $final_output;\
	error_log="fastas_GISAID_errors/error_log.txt";\
	mv $project_dir/"Fastas - GISAID Not Complete/*.fa*" $project_dir/analysis/fasta/not_uploaded;\
	mv $project_dir/"fastas_GISAID_errors/*fa*" $project_dir/analysis/fasta/not_uploaded;\
	mv $project_dir/"fastas_GISAID_uploaded/*fa*" $project_dir/analysis/fasta/not_uploaded
fi

#process fastas
if [[ $flag_process_fastas == "Y" ]]; then
	for fasta_id in `ls $project_dir/analysis/fasta/not_uploaded`; do
    		sample_id=`echo $fasta_id | cut -f5 -d"/" | cut -f1 -d"."`
    		status=`cat $final_output | grep $sample_id | cut -f2 -d","`
    		if [[ $status == "gisaid_pass" ]]; then
        		echo "pass $sample_id"
        		mv $fasta_id $project_dir/analysis/fasta/not_uploaded/$sample_id.fa
    		else
        		echo "fail $sample_id"
        		mv $fasta_id $project_dir/analysis/fasta/upload_partial/$sample_id.fa
    		fi
	done
fi
# rm -r fastas*;\
# rm -r Fastas*;\
# rm -r GISAID*;\
# rm logs/warning*
