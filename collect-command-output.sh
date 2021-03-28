#!/bin/bash

# Pod names for gluster and heketi pods
gluster_pod=""
heketi_pod=""
first_gluster_pod="120"

# commands in pod will timeout after $timeout seconds
timeout=""

# Data collection path is an arugment
DATA_COLLECTION_PATH=$1
OCS_NAMESPACE=$2

function check_args() {
	if [ -z "$OCS_NAMESPACE" ]; then
		echo "Please provide OCS3 namespace and run the script again"
		exit 0;
	fi

}

# Fetch gluster and heketi pod names
function get_pod_name() {

	gluster_pods=$(oc get pods -n "$OCS_NAMESPACE" |grep glusterfs|awk '{print $1}')
	heketi_pod=$(oc get pods -n "$OCS_NAMESPACE" |grep heketi|awk '{print $1}')
	first_gluster_pod=$(echo "$gluster_pods"|awk '{print $1}')
}


# Dump data to temporary directory at /tmp/
# /tmp/tmp.f9NAHlOOl1
# ├── command_output
# │   ├── gluster_command_output
# │   │   ├── gluster_peer_status
# │   │   ├── gluster_pool_list
# │   │   ├── gluster_volume_info
# │   │   └── gluster_volume_list
# │   ├── heketi_command_output
# │   └── oc_command_output
# ├── config_file
# │   └── heketi_log_file
# └── logs
#    └── gluster_config_files


function initialise() {
	
	tempdirname=$(mktemp -d)

	mkdir "$tempdirname"/command_output
	mkdir "$tempdirname"/logs
	mkdir "$tempdirname"/config_file

	gluster_command_dir="$tempdirname/command_output/gluster_common_command_output/"
	gluster_pod_command_dir="$tempdirname/command_output/gluster_pod/"
	heketi_command_output="$tempdirname/command_output/heketi_command_output/"
	oc_command_output="$tempdirname/command_output/oc_command_output/"
	gluster_config_files="$tempdirname/logs/gluster_config_files/"
	gluster_log_file="$tempdirname/config_file/gluster_log_files/"
	heketi_log_file="$tempdirname/config_file/heketi_log_files/"

	mkdir "$gluster_command_dir"
	mkdir "$gluster_pod_command_dir"
	mkdir "$heketi_command_output"
	mkdir "$oc_command_output"
	mkdir "$gluster_config_files"
	mkdir "$heketi_log_file"


# If no argument is passed, use present working directory
	if [ ! -d "${DATA_COLLECTION_PATH}" ]; then
        DATA_COLLECTION_PATH=$(pwd)
    fi

    get_pod_name
}



# oc exec command to run gluster and heketi commands in pod.
function oc_exec() {
        container_name="$1"
        container_command="$2"
		command_dump_directory="$3"
        #file=${gluster_commands[$i]}
        #filename=${file// /_}
        file=$container_command
        filename=${file// /_}
        echo "Collecting $2 from $1"
        timeout $timeout oc exec -n "$OCS_NAMESPACE" "$container_name"  -- bash -c "$container_command" >> "$command_dump_directory"/"$filename"

}


# Collect gluster commands output
function collect_gluster_command(){
# gluster commands
        gluster_commands=()
        gluster_commands+=("gluster peer status")
        gluster_commands+=("gluster pool list")
        gluster_commands+=("gluster volume list")
        gluster_commands+=("gluster volume info")
        gluster_commands+=("gluster volume status")
		gluster_commands+=("gluster volume get all cluster.op-version")

for (( i=0; i< ${#gluster_commands[@]}; i++ )) ; do	
	oc_exec "$first_gluster_pod" "${gluster_commands[$i]}" "${gluster_command_dir}"
    #  oc exec glusterfs-storage-hcv4w -- bash -c "${gluster_commands[$i]}" >> /tmp/"$filename"
done

}


# Collect heketi commands output
function collect_heketi_command() {

# heketi commands
	heketi_commands=()
	heketi_commands+=("heketi-cli topology info")
	heketi_commands+=("heketi-cli volume list")
	heketi_commands+=("heketi-cli server operations info")

for (( i=0; i< ${#heketi_commands[@]}; i++ )); do
	oc_exec "$heketi_pod" "${heketi_commands[$i]}" "$heketi_command_output"
done

}


function end(){
	outputfile="$DATA_COLLECTION_PATH/ocs3-debug.tar.gz"
	tar -zcvf  "$outputfile" "$tempdirname" > /dev/null
	echo "--------------------------"
	echo "Please upload $outputfile.."
	echo "--------------------------"
	echo "$tempdirname"|grep "/tmp/tmp." # && rm "$tempdirname/*" && rmdir  "$tempdirname"
	
}

check_args
initialise
collect_gluster_command
collect_heketi_command
end