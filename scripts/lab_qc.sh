#!/bin/bash
search_dir="../OH-VH00648-220425/save/save"

# generate sample list
sample_list=`ls $search_dir | cut -f1 -d"." | grep [0-9] | sort | uniq`

# prep files
frag_out="$search_dir/merged_frag.csv"
cov_out="$search_dir/merged_coverage.csv"

echo "id,liquid_handler,frag_length,count" > $frag_out
echo "id,liquid_handler,align_reads,cov_ov_100,cov_50_100,cov_20_50,cov_15_20,cov_10_15,cov_3_10,cov_1_3,cov_0_1,input_reads,dup_reads,uni_reads,qc_reads_fail,map_count,map_perc,unmapped_reads,mapq_40,mapq_30_40,mapq_20_30,mapq_10_20,mapq_0_10" > $cov_out

# for each sample
for id in ${sample_list[@]}; do
	
	check_type=`echo $id | grep "b" | wc -l`
	if [[ $check_type -gt 0 ]]; then
		type="Hamilton"
	else
		type="epMotion"
	fi

	# fragment_lengt_hist
	# contains two columns separated by comma with length and number of reads
	# https://support.illumina.com/content/dam/illumina-support/help/Illumina_DRAGEN_Bio_IT_Platform_v3_7_1000000141465/Content/SW/Informatics/Dragen/GPipelineMeanIns_fDG.htm
	f=$search_dir/$id.fragment_length_hist.csv
        cat $f | grep -v ",0" | grep -v "Count" | grep -v "Sample" > tmp.hist.csv
       	sed -i "s/$/,$id,$type/" tmp.hist.csv
        cat tmp.hist.csv >> $frag_out

	# coverage
	## contains four cols separted by comma with various stats
	#https://support.illumina.com/content/dam/illumina-support/help/Illumina_DRAGEN_Bio_IT_Platform_v3_7_1000000141465/Content/SW/Informatics/Dragen/CoverageMetricsReport_fDG.htm
	f=$search_dir/$id.wgs_coverage_metrics.csv
	align_reads=`cat $f | awk -F"," 'FNR == 26 { print $4 }'`
	cov_ov_100=`cat $f | awk -F"," 'FNR == 5 { print $4 }'`
	cov_50_100=`cat $f | awk -F"," 'FNR == 13 { print $4 }'`
	cov_20_50=`cat $f | awk -F"," 'FNR == 14 { print $4 }'`
	cov_15_20=`cat $f | awk -F"," 'FNR == 15 { print $4 }'`
	cov_10_15=`cat $f | awk -F"," 'FNR == 16 { print $4 }'`
	cov_3_10=`cat $f | awk -F"," 'FNR == 17 { print $4 }'`
	cov_1_3=`cat $f | awk -F"," 'FNR == 18 { print $4 }'`
	cov_0_1=`cat $f | awk -F"," 'FNR == 19 { print $4 }'`
	
	f=$search_dir/$id.mapping_metrics.csv
	input_reads=`cat $f | awk -F"," 'FNR == 1 { print $4 }'`
	dup_reads=`cat $f | awk -F"," 'FNR == 2 { print $4 }'`
	uni_reads=`cat $f | awk -F"," 'FNR == 4 { print $4 }'`
	qc_reads_fail=`cat $f | awk -F"," 'FNR == 7 { print $4 }'`
	map_count=`cat $f | awk -F"," 'FNR == 8 { print $4 }'`
	map_perc=`cat $f | awk -F"," 'FNR == 8 { print $5 }'`
	unmapped_reads=`cat $f | awk -F"," 'FNR == 12 { print $4 }'`
        mapq_40=`cat $f | awk -F"," 'FNR == 19 { print $4 }'`
        mapq_30_40=`cat $f | awk -F"," 'FNR == 20 { print $4 }'`
        mapq_20_30=`cat $f | awk -F"," 'FNR == 21 { print $4 }'`
	mapq_10_20=`cat $f | awk -F"," 'FNR == 22 { print $4 }'`
        mapq_0_10=`cat $f | awk -F"," 'FNR == 23 { print $4 }'`
	
	echo "$id,$type,$align_reads,$cov_ov_100,$cov_50_100,$cov_20_50,$cov_15_20,$cov_10_15,$cov_3_10,$cov_1_3,$cov_0_1,$input_reads,$dup_reads,$uni_reads,$qc_reads_fail,$map_count,$map_perc,$unmapped_reads,$mapq_40,$mapq_30_40,$mapq_20_30,$mapq_10_20,$mapq_0_10" >> $cov_out
done

