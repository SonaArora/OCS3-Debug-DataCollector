#!/bin/bash

# Pod names for gluster and heketi pods

gluster_pod_array=()
heketi_pod=""
first_gluster_pod=""

# commands in pod will timeout after $timeout seconds	

timeout="120"

# Data collection path is an arugment

DATA_COLLECTION_PATH=$1
OCS_NAMESPACE=$2

# node name where glusterfs and heketi pods are running

node=()

# Check namespace ($2) is empty or not.
# Also check if namespace exists or not. 

function check_args() {
	if [[ -z "$OCS_NAMESPACE" ]]; then
		echo "Please provide OCS3 namespace and run the script again"
		exit 0;
	fi

	oc get projects |grep "$OCS_NAMESPACE"
	if [[ $? -eq 1 ]]; then
		echo "Namespace $OCS_NAMESPACE does not exist. Please provide valid OCS namespace"
		exit 0;
	fi

}



# Directory structure where data is dumped
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




# To check if the filesystem where data is dumped has enough free space or not.
function check_free_space() {

	data_dump_dir="$1"
	free_space=$(df -k "$data_dump_dir" | tail -1 | awk '{print $4}')
	min_free_space=1048576

	if [[ "$free_space" -lt "$min_free_space" ]]; then
		echo "Free space at $data_dump_dir is less than $min_free_space Kb, skipping data collection"
		exit
	fi

}


# Function to create directory structure where data will be dumped

function initialise() {
	
	tempdirname=$(mktemp -d)

	check_free_space "$tempdirname"

	mkdir "$tempdirname"/command_output
	mkdir "$tempdirname"/logs
	mkdir "$tempdirname"/config_file

	gluster_command_dir="$tempdirname/command_output/gluster_command_output"
	gluster_pod_command_dir="$tempdirname/command_output/from_each-gluster_pods"
	heketi_command_output_dir="$tempdirname/command_output/heketi_command_output"
	oc_command_output_dir="$tempdirname/command_output/oc_command_output"
	gluster_config_files_dir="$tempdirname/config_file/gluster"
#	heketi_config_files_dir="$tempdirname/config_file/heketi"
	gluster_log_files_dir="$tempdirname/logs/gluster"
#	heketi_log_files_dir="$tempdirname/logs/heketi"

	mkdir "$gluster_command_dir"
	mkdir "$gluster_pod_command_dir"
	mkdir "$heketi_command_output_dir"
	mkdir "$oc_command_output_dir"
	mkdir "$gluster_config_files_dir"
#	mkdir "$heketi_config_files_dir"
	mkdir "$gluster_log_files_dir"
#	mkdir "$heketi_log_files_dir"
	

# If no argument is passed, use present working directory

	if [ ! -d "${DATA_COLLECTION_PATH}" ]; then
        DATA_COLLECTION_PATH=$(pwd)
	fi

	get_pod_name
}




# Fetch gluster and heketi pod names

function get_pod_name() {

	gluster_pods=$(oc get pods -n "$OCS_NAMESPACE" |grep glusterfs|grep "Running" | awk '{print $1}')
	gluster_pod_array=(${gluster_pods//[\(\),]/})
	heketi_pod=$(oc get pods -n "$OCS_NAMESPACE" |grep heketi| grep "Running" | awk '{print $1}')
	first_gluster_pod=${gluster_pod_array[0]}
}




function get_node_name() {
	
	node_temp=$(oc get nodes --show-labels |grep 'glusterfs=storage-host'|awk '{print $1}')
	node=(${node_temp//[\(\),]/})

}

# oc exec command to run gluster and heketi commands in the pods.

function oc_exec() {
    container_name="$1"
    container_command="$2"
	command_dump_directory="$3"
    file=$container_command
    filename=${file// /_}
    echo "Collecting $2 from $1"
	timeout "$timeout" oc exec -n "$OCS_NAMESPACE" "$container_name"  -- bash -c "$container_command" >> "$command_dump_directory"/"$filename"

}



# Collect gluster commands output

function collect_gluster_output(){

# gluster commands
    
	gluster_commands=()
    gluster_commands+=("gluster volume list")
    gluster_commands+=("gluster volume info")
    gluster_commands+=("gluster volume status")
	gluster_commands+=("gluster volume get all cluster.op-version")

# collect common gluster commands from one running glusterfs pod

for (( i=0; i< ${#gluster_commands[@]}; i++ )) ; do	
    oc_exec "$first_gluster_pod" "${gluster_commands[$i]}" "${gluster_command_dir}"
    # oc exec glusterfs-storage-hcv4w -- bash -c "${gluster_commands[$i]}" >> /tmp/"$filename"
done

	gluster_command_from_each_pod=()
	gluster_command_from_each_pod+=("pvs --all --units k --reportformat=json")
	gluster_command_from_each_pod+=("vgs --all --units k --reportformat=json")
	gluster_command_from_each_pod+=("lvs --all --units k --reportformat=json")
	gluster_command_from_each_pod+=("df -h")
	gluster_command_from_each_pod+=("rpm -qa|grep gluster")
	gluster_command_from_each_pod+=("gluster peer status")
	gluster_command_from_each_pod+=("systemctl status glusterd")
	gluster_command_from_each_pod+=("systemctl status gluster-blockd")
	gluster_command_from_each_pod+=("systemctl status gluster-block-target")
	gluster_command_from_each_pod+=("systemctl status tcmu-runner")
	gluster_command_from_each_pod+=("gluster snapshot list")
	gluster_command_from_each_pod+=("gluster snaphsot config")

# collect gluster commands from all running glusterfs pod

for (( l=0; l< ${#gluster_pod_array[@]}; l++ )); do

	dirname="${gluster_pod_command_dir}"/"${gluster_pod_array[$l]}"
	mkdir "$dirname"

	for (( j=0; j< ${#gluster_command_from_each_pod[@]}; j++ )) ; do
		oc_exec "${gluster_pod_array[$l]}" "${gluster_command_from_each_pod[$j]}" "$dirname"
	done
	
done

}



# Collect heketi commands output
function collect_heketi_output() {

# heketi commands
	heketi_commands=()
	heketi_commands+=("heketi-cli topology info")
	heketi_commands+=("heketi-cli volume list")
	heketi_commands+=("heketi-cli server operations info")
	heketi_commands+=("heketi-cli db dump")

	if [ -z "$heketi_pod" ]; then
		echo "Heketi pod is not running, hence heketi commands are not captured"
	else
		for (( i=0; i< ${#heketi_commands[@]}; i++ )); do
			oc_exec "$heketi_pod" "${heketi_commands[$i]}" "$heketi_command_output_dir"
		done
	fi
}



function collect_oc_output() {

	# oc commands
	oc_commands=()
	oc_commands+=("oc get all")
	oc_commands+=("oc get pods -o wide")
	oc_commands+=("oc get nodes")
	oc_commands+=("oc get sc")
	oc_commands+=("oc get pvc")
	oc_commands+=("oc get pv")
	oc_commands+=("oc get serviceaccount")

	for (( i=0; i< ${#oc_commands[@]}; i++ )); do
		file=${oc_commands[$i]}
		filename=${file// /_}
		echo "Collecting ${oc_commands[$i]} from $OCS_NAMESPACE"
		timeout "$timeout" ${oc_commands[$i]} -n "$OCS_NAMESPACE" >> "$oc_command_output_dir"/"$filename"
	done 

}



# To copy heketi and gluster config/log files to temporary directory.
function copy_data() {

	servername="$1"
	source_directory="$2"
	target_directory="$3"

	timeout "$timeout" scp -r "$servername":"$source_directory" "$target_directory"
	echo "Copying $source_directory from $servername to $target_directory"
}


# Make tar of temporary directory where gluster and heketi config/log files are collected, and delete the temporary directory.
function make_tar() {

    data_dump_dir="$1"
	tmp_dir="$2"

	if [[ "$data_dump_dir" == **config** ]]; then
		compressedfile="gluster-config"
	elif [[ "$data_dump_dir" == **log** ]]; then
		compressedfile="log-file"
	fi

	tar -zcvf "$data_dump_dir"/"$compressedfile".tar.gz "$tmp_dir"  > /dev/null

	rm -rf "$tmp_dir"
}


function collect_config_files() {

	get_node_name	

	gluster_config_file=()
	gluster_config_file+=("/etc/fstab")
	gluster_config_file+=("/var/lib/glusterd/")
	gluster_config_file+=("/etc/target/saveconfig.json")

	tempdir=$(mktemp -d)

	for n in "${node[@]}"; do	
		tmp_config_dir="$tempdir"/"$n"
		mkdir "$tmp_config_dir"
	
		for file in "${gluster_config_file[@]}"; do
			copy_data "$n" "$file" "$tmp_config_dir"
		done

	done

	make_tar "$gluster_config_files_dir" "$tempdir"

}


function collect_log_files() {

		get_node_name	

		gluster_log_file=()
		gluster_log_file=("/var/log/glusterfs")

		tempdir=$(mktemp -d)

		for n in "${node[@]}"; do
			tmp_log_dir="$tempdir"/"$n"
			mkdir "$tmp_log_dir"

			for file in "${gluster_log_file[@]}"; do
				copy_data "$n" "$file" "$tmp_log_dir"
			done

		done
	
		make_tar "$gluster_log_files_dir" "$tempdir"

}

# Function to create tar file from /tmp/ and remove temporary directory.

function end() {
	
	outputfile="$DATA_COLLECTION_PATH/ocs3-debug.tar.gz"
	tar -zcvf  "$outputfile" "$tempdirname" > /dev/null
	echo "--------------------------"
	echo "Please upload $outputfile.."
	echo "--------------------------"
	echo "$tempdirname"|grep "/tmp/tmp." # && rm "$tempdirname/*" && rmdir  "$tempdirname"
	
}

check_args
initialise
collect_gluster_output
collect_heketi_output
collect_oc_output
collect_config_files
collect_log_files
end