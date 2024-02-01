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

cleanmanifests(){
	sed -i "s/[_-]SARS//g" $1
	sed -i "s/-$project_name_full//g" $1
	sed -i "s/-$project_name//g" $1		
	sed -i "s/-OH//g" $1		
}

makeDirs(){
	new=$1
	if [[ ! -d $$new ]]; then mkdir -p $new; fi
}

get_config_info(){
   version=`cat config/software_versions.txt | awk -v name=$2 '$1 ~ name' | awk -v pid="$1" '$2 ~ pid' | awk '{ print $3 }'`
   # version=`cat config/software_versions.txt | awk -v name=pangolin '$1 ~ /name/'`
   echo $version
}