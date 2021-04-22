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
	heketi_log_files_dir="$tempdirname/logs/heketi"

	mkdir "$gluster_command_dir"
	mkdir "$gluster_pod_command_dir"
	mkdir "$heketi_command_output_dir"
	mkdir "$oc_command_output_dir"
	mkdir "$gluster_config_files_dir"
#	mkdir "$heketi_config_files_dir"
	mkdir "$gluster_log_files_dir"
	mkdir "$heketi_log_files_dir"
	

# If no argument is passed, use present working directory

	if [[ ! -d "${DATA_COLLECTION_PATH}" ]]; then
        DATA_COLLECTION_PATH=$(pwd)
	fi

	get_pod_name
}




# Fetch gluster and heketi pod names

function get_pod_name() {

	gluster_pods=$(oc get pods -n "$OCS_NAMESPACE" |grep glusterfs|grep "Running" | awk '{print $1}')
	# shellcheck disable=SC2206
	gluster_pod_array=(${gluster_pods//[\(\),]/})
	heketi_pod=$(oc get pods -n "$OCS_NAMESPACE" |grep heketi| grep "Running" | awk '{print $1}')
	first_gluster_pod=${gluster_pod_array[0]}
}


# Fetch node names where glusterfs pods are running

function get_node_name() {
	
	node_temp=$(oc get nodes --show-labels |grep 'glusterfs=storage-host'|awk '{print $1}')
	# shellcheck disable=SC2206
	node=(${node_temp//[\(\),]/})

}

# oc exec command to run gluster and heketi commands in the pods.

function oc_exec() {
    container_name="$1"
    container_command="$2"
	command_dump_directory="$3"
    file="$container_command"
    filename=${file// /_}
    echo "Collecting $2 from $1"
	timeout "$timeout" oc exec -n "$OCS_NAMESPACE" "$container_name"  -- bash -c "$container_command" >> "$command_dump_directory"/"$filename"
}


# To collect heal commands output from only one running glusterfs pod.

function oc_exec_heal_command() {

    container_name="$1"
	command_dump_directory="$2"
	container_commands=()
	gluster_volume_list_file="$2"/gluster_volume_list
	
	if [[ -s "$gluster_volume_list_file" ]]; then
		while IFS= read -r vol; do 
		    container_commands+=("gluster volume heal $vol info")
			container_commands+=("gluster volume heal $vol info split-brain")
			container_commands+=("gluster volume heal $vol statistics heal-count")

			for command in "${container_commands[@]}";do
				temp="$command"
				output_file=${temp// /_}
				timeout "$timeout" oc exec -n "$OCS_NAMESPACE" "$container_name"  -- bash -c "$command" >> "$command_dump_directory"/"$output_file"
			done
		done < "$gluster_volume_list_file"		
	fi
	
}



# Collect gluster commands output
function collect_gluster_output() {

# gluster commands output will be collected only from one glusterfs pod
    
	gluster_commands=()
    gluster_commands+=("gluster volume list")
    gluster_commands+=("gluster volume info")
    gluster_commands+=("gluster volume status")
	gluster_commands+=("gluster volume get all cluster.op-version")


	for (( i=0; i< ${#gluster_commands[@]}; i++ )); do	
    	oc_exec "$first_gluster_pod" "${gluster_commands[$i]}" "${gluster_command_dir}"
    	# oc exec glusterfs-storage-hcv4w -- bash -c "${gluster_commands[$i]}" >> /tmp/"$filename"
	done

	oc_exec_heal_command "$first_gluster_pod" "${gluster_command_dir}"
}


# collect gluster commands output from all running glusterfs pod

function collect_gluster_output_from_all_glusterfs_pods() {

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
	gluster_command_from_each_pod+=("lsblk")


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
		# shellcheck disable=SC2206
		# shellcheck disable=SC2086
		timeout "$timeout" ${oc_commands["$i"]} -n "$OCS_NAMESPACE" >> "$oc_command_output_dir"/"$filename"
	done 

}



# To copy heketi and gluster config and log files.

function copy_data() {

	len="$#"
	args=("$@")
	servername="$1"
	target_directory="$2"
	source_directory=()
	temp=0

	for i in $(seq 2 $((len -1)));do
		source_directory[$temp]=${args[$i]}
		temp=$((temp+1))
	done


	temp_string="${source_directory[*]}"
	echo "Copying $temp_string from $servername to $target_directory"
	temp_string=${temp_string// /,}
	
	rsync -Rva "$servername":\{"$temp_string"\} "$target_directory" > /dev/null
	
}


# Prepare a list of config files to copy from gluster/heketi servers

function collect_config_files() {

	get_node_name	

	gluster_config_file=()
	gluster_config_file+=("/etc/fstab")
	gluster_config_file+=("/var/lib/glusterd/")
	gluster_config_file+=("/etc/target/saveconfig.json")

	for n in "${node[@]}"; do	
		config_dir="$gluster_config_files_dir"/"$n"
		mkdir "$config_dir"
		copy_data "$n" "$config_dir" "${gluster_config_file[@]}"
	done

}


# Prepare a list of log files to copy from gluster/heketi servers

function collect_log_files() {

		get_node_name	

		gluster_log_file=()
		gluster_log_file+=("/var/log/glusterfs/")
		gluster_log_file+=("/var/log/messages")

		for n in "${node[@]}"; do
			log_dir="$gluster_log_files_dir"/"$n"
			mkdir "$log_dir"
			copy_data "$n" "$log_dir" "${gluster_log_file[@]}"
		done	

		get_pod_name
		
		# Collect heketi pod logs
		timeout $timeout oc logs "$heketi_pod" -n "$OCS_NAMESPACE" >> "$heketi_log_files_dir"/heketi.log		

}


# Function to create a tar file from /tmp/ and remove temporary directory.

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
collect_gluster_output_from_all_glusterfs_pods
collect_heketi_output
collect_oc_output
collect_config_files
collect_log_files
end