#########################################################
# functions
#########################################################
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

message_cmd_log(){
        msg="$1"
        echo $msg >> $pipeline_log
	echo $msg
}

message_stats_log(){
	msg="$1"
	echo "$msg" >> $stats_log
	echo "$msg"

}

clean_file_insides(){
	sed -i "s/[_-]SARS//g" $1
	sed -i "s/[-_]$project_name_full//g" $1
	sed -i "s/[-_]$project_name//g" $1
	sed -i "s/-OH//g" $1
   sed -i "s/_001//g" $1
   sed -i "s/_S[0-9]*_//g" $1
   sed -i "s/_L001//g" $1
}

clean_file_names(){
	out=`echo $1 | sed "s/[_-]SARS//g" | sed "s/[_-]$project_name_full//g" | sed "s/[_-]$project_name//g"`
	out=`echo $out | sed "s/-OH//g" | sed "s/_S[0-9]*//g" | sed "s/_L001//g" | sed "s/_001//g" | sed "s/_R/.R/g"`
   echo $out
}

makeDirs(){
	new=$1
	if [[ ! -d $$new ]]; then mkdir -p $new; fi
}

get_config_info(){
   version=`cat config/software_versions.txt | awk -v name=$2 '$1 ~ name' | awk -v pid="$1" '$2 ~ pid' | awk '{ print $3 }'`
   echo $version
}

stats_process(){
   final_in=$1

   echo "----------------------- HEAD -----------------------"
   head $final_in
   echo "----------------------------------------------"

   echo "----------------------- STATS -----------------------"
   length=`cat $final_in | wc -l`
   pass=`cat $final_in | grep -e "[Pp]ass"| wc -l`
   fail=`cat $final_in | grep -e "[Ff]ail"| wc -l`

   echo "Length: $length"
   echo "Pass: $pass"
   echo "Fail: $fail"
   echo "----------------------------------------------"
}

update_config(){
   old_cmd=$1
   new_cmd=$2
   sed -i "s/$old_cmd/$new_cmd/" $3
}

update_config_refs(){
    if [[ ! -f $2 ]]; then
        echo "Reference file ($ref_file) is missing from $ref_path. Please update $pipeline_config"
		exit
	fi

	old_cmd="params.$1 = \"TBD\""
	new_cmd="params.$1 = \"$2\""
	new_cmd=$(echo $new_cmd | sed 's/\//\\\//g')
	sed -i "s/$old_cmd/$new_cmd/" $3
}
