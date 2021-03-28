#!/bin/bash

# Pod names for gluster and heketi pods
gluster_pod=""
heketi_pod=""
first_gluster_pod=

# commands in pod will timeout after $timeout seconds	
timeout="120"

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
	first_gluster_pod=$(echo "$gluster_pods"|awk '{print $1}'| head -1)
}


# Dump data to temporary directory at /tmp/
# /tmp/tmp.jskVuZ27zT/
# ├── command_output
# │   ├── gluster_common_command_output
# │   │   ├── gluster_volume_list
# │   │   └── gluster_volume_status
# │   │   └── [..]
# │   ├── gluster_pod
# │   │   └── glusterfs-storage-7w6j9
# │   ├── heketi_command_output
# │   │   ├── heketi-cli_server_operations_info
# │   │   ├── heketi-cli_topology_info
# │   │   └── heketi-cli_volume_list
# │   └── oc_command_output
# ├── config_file
# │   ├── gluster
# │   └── heketi
# └── logs



# Function to create directory structure where data will be dumped
function initialise() {
	
	tempdirname=$(mktemp -d)

	mkdir "$tempdirname"/command_output
	mkdir "$tempdirname"/logs
	mkdir "$tempdirname"/config_file

	gluster_command_dir="$tempdirname/command_output/gluster_command_output"
	gluster_pod_command_dir="$tempdirname/command_output/from_each-gluster_pods"
	heketi_command_output="$tempdirname/command_output/heketi_command_output"
	oc_command_output="$tempdirname/command_output/oc_command_output"
	gluster_config_files="$tempdirname/config_file/gluster"
	heketi_config_files="$tempdirname/config_file/heketi"
	gluster_log_files="$tempdirname/logs/gluster"
	heketi_log_files="$tempdirname/logs/heketi"

	mkdir "$gluster_command_dir"
	mkdir "$gluster_pod_command_dir"
	mkdir "$heketi_command_output"
	mkdir "$oc_command_output"
	mkdir "$gluster_config_files"
	mkdir "$heketi_config_files"
	mkdir "$gluster_log_files"
	mkdir "$heketi_log_files"
	

# If no argument is passed, use present working directory
	if [ ! -d "${DATA_COLLECTION_PATH}" ]; then
        DATA_COLLECTION_PATH=$(pwd)
    fi

    get_pod_name
}



# oc exec command to run gluster and heketi commands in the pods.
function oc_exec() {
        container_name="$1"
        container_command="$2"
		command_dump_directory="$3"
        #file=${gluster_commands[$i]}
        #filename=${file// /_}
        file=$container_command
        filename=${file// /_}
        echo "Collecting $2 from $1"
		oc exec -n "$OCS_NAMESPACE" "$container_name"  -- bash -c "$container_command" >> "$command_dump_directory"/"$filename"

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


# Function to create tar file from /tmp/ and remove temporary directory.
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