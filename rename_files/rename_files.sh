#!/bin/bash

##INFO
# takes argument of parent dir and output dir
# parses parent dir tree
# moves and rename files to output dir

#########################################################
# Arguments
#########################################################

helpFunction()
{
   echo ""
   echo "Usage: $0 -p parent_dr"
   echo -e "\t-p path to parent dir to parse"
   echo "Usage: $1 -o output_dir"
   echo -e "\t-o path to output directory"
   exit 1 # Exit script after printing help
}

while getopts "p:o:" opt
do
   case "$opt" in
      p ) parent_dir="$OPTARG" ;;
      o ) output_dir="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$parent_dir" ] || [ -z "$output_dir" ]; then
   echo "Some or all of the parameters are empty";
   helpFunction
fi

#########################################################  
# Set variables
#########################################################
#remove trailing / on directories
parent_dir=$(echo $parent_dir | sed 's:/*$::')
output_dir=$(echo $output_dir | sed 's:/*$::')

#create time stamp
log_time=`date +"%Y%m%d_%H%M"`

#########################################################
# code
#########################################################
#create output dir
if [[ -d "$output_dir" ]]; then rm -r $output_dir; fi

if [[ ! -d "$output_dir" ]]
then 
   echo
   echo "** Creating output directory: $output_dir"
   mkdir $output_dir
else
   echo
   echo "Output directory already exists. Must create new directory"
   exit
fi

#add log file to parent dir
log_file=$parent_dir/${log_time}_rename_log.txt
touch $log_file

#grab all file names
file_list=(`find $parent_dir -type f -name "*.fastq.gz"`)

echo "** Renaming files **"

for f in ${file_list[@]}; do
   
   #grab file name
   IFS='/' read -r -a strarr <<< "$f"
   fastq_name="${strarr[${#strarr[@]}-1]}"

   #rename fastq
   #example:
   #SC1234-OH-M5185-20211210_S1_L001_R1_001.fastq.gz to SC1234_R1.fastq.gz
   renamed_file=`echo $fastq_name | sed -e 's/-OH-[A-Z0-9]*._[0-9]*.S*._L[0-9]*./_/'`

   #add file info to log
   echo $f $parent_dir/$fastq_name >> $log_file

   #move fastq file
   cp $f $parent_dir/$renamed_file
done

echo "** Process Complete **"
echo

#sh /Users/sevillas2/Desktop/APHL/ODH-COVID19/scripts/rename_files.sh -p /Users/sevillas2/Desktop/APHL/demo/rename_demo/ -o test

#touch ../../../demo/rename_demo/dirA/SC1234-OH-M5185_20211130_S1_L001_R1.fastq.gz; touch ../../../demo/rename_demo/dirA/SC1234-OH-M5185_20211130_S2_L001_R2.fastq.gz; \
#touch ../../../demo/rename_demo/dirB/SC5678-OH-M5185_20211130_S1_L001_R1.fastq.gz; touch ../../../demo/rename_demo/dirB/SC5678-OH-M5185_20211130_S2_L001_R2.fastq.gz; \
