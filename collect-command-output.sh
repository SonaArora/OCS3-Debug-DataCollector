#!/bin/bash

# Initializing variables

gluster_pod_array=()
heketi_pod=""
first_gluster_pod=""

# commands in pod will timeout after $timeout seconds	
timeout=""

# Data collection path is an arugment
DATA_COLLECTION_PATH=
OCS_NAMESPACE=

# node name where glusterfs and heketi pods are running
node=()

# To display help for all options

function print_help() {
	cat > /tmp/helpfile <<EOF
		
	collect-command-output.sh, collect-command-output:   This script will collect data for OCS 3 converged mode:
                                 1. Gluster command output from gluster pods
                                 2. Heketi command output from heketi pod
                                 3. Gluster and heketi logs
                                 4. Gluster and heketi config files
              
	Syntax:  ./collect-command-output.sh <-d|--directory-name> <-n|--namespace> [-t|--timeout]

         -d, --directory-name   Directory where data will be dumped
         
         -n, --namespace        Namespace where OCS pods are running
                  
         -t, --timeout          Commands in pod will get timeout after the time interval specified [optional]

         -h, --help				Print help
         
         
Author     : Sonal Arora(aarorasona@gmail.com)
Maintainer : Sonal Arora(aarorasona@gmail.com)
License    : GPLv3
Link       : https://github.com/SonaArora/OCS3-Debug-DataCollector
EOF
cat /tmp/helpfile


}




# command line argument parsing

	args=("$@")
	len="$#"
	i=0
    arg3="true"

	while [ "$i" -lt "$len" ]
	do
		option=${args[$i]}
		case "$option" in
			-d|--directory)
				i=$((i+1))
				if [ -n "${args[$i]}" ]; then
					DATA_COLLECTION_PATH=${args[$i]}
					arg1="true"
				else 
					arg1="false"
				fi
				i=$((i+1))
			;;
			-n|--namespace)
				i=$((i+1))
				if [ -n "${args[$i]}" ]; then
					OCS_NAMESPACE=${args[$i]}
					arg2="true"
				else
					arg2="false"
				fi
				i=$((i+1))
			;;
			-t|--timeout)
				i=$((i+1))
				timeout="${args[$i]}"
				if [  -z "$timeout" ]; then
				    arg3="false"
				fi
				i=$((i+1))
			;;
			-h|--help)
				print_help
				i=$((i+1))
			;;	
			*)
				print_help
				exit 1
			;;
		esac
    done

    if [ "$arg1" != "true" ] || [ "$arg2" != "true" ] || [ "$arg3" != "true" ];then
	    print_help
		exit 1
	fi


function print_info() {
	echo -e "\e[34m\e[1m Info \e[0m: $1"
}

function print_error() {
	echo -e "\e[31m\e[1m Error \e[0m: $1"
}

function print_warning() {
	echo -e "\e[33m\e[1m Warning \e[0m: $1 "
}

# Check if the data dump directory exits or not. If not, mkdir it

function check_directory() {
	if [ ! -d "$DATA_COLLECTION_PATH" ]; then
        mkdir "$DATA_COLLECTION_PATH"
	fi

}


# check if ocs namespace provided in command line argument exists or not.

function check_namespace() {
	temp_ns=$(oc get project |grep "$OCS_NAMESPACE" | awk '{print $1}')	
	if [ "$OCS_NAMESPACE" != "$temp_ns" ]; then
		print_error "$OCS_NAMESPACE Namespace does not exists. Please provide correct OCS namespace"
		exit 1
	fi	

}


# check if timeout value is not provided in command line args, then assign default value.

function check_timeout() {
	if [ -z "$timeout" ]; then
		timeout=120
	fi

}

# check if time entered is integer or not
#function check_timestamp() {
#
#
#}

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
# │   └── gluster
# └── logs




# To check if the filesystem where data is dumped has enough free space or not.
function check_free_space() {

	data_dump_dir="$1"
	free_space=$(df -k "$data_dump_dir" | tail -1 | awk '{print $4}')
	min_free_space=1048576

	if [[ "$free_space" -lt "$min_free_space" ]]; then
		print_error "Free space at $data_dump_dir is less than $min_free_space Kb, skipping data collection"
		exit
	fi

}


# Function to create directory structure where data will be dumped

function initialise() {
	
	tempdirname=$(mktemp -d)

	check_free_space "$tempdirname"
	check_namespace

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
	
	check_directory
	
	check_timeout
	get_pod_name
	get_node_name
}




# Fetch gluster and heketi pod names

function get_pod_name() {

	gluster_pods=$(oc get pods -n "$OCS_NAMESPACE" |grep glusterfs|grep "Running" | awk '{print $1}')
	
	# shellcheck disable=SC2206
	gluster_pod_array=(${gluster_pods//[\(\),]/})
	heketi_pod=$(oc get pods -n "$OCS_NAMESPACE" |grep heketi| grep "Running" | awk '{print $1}')

	if [ ${#gluster_pod_array[@]} ]; then	
		first_gluster_pod=${gluster_pod_array[0]}
	fi
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
    print_info "Collecting $2 from $1"
	timeout "$timeout" oc exec -n "$OCS_NAMESPACE" "$container_name"  -- bash -c "$container_command" >> "$command_dump_directory"/"$filename"
}


# gluster command which contains volumename, their output is collected by below code 

function oc_exec_gluster_custom_command() {

    container_name="$1"
	command_dump_directory="$2"
	container_commands=()
	gluster_volume_list_file="$2"/gluster_volume_list
	
	if [[ -s "$gluster_volume_list_file" ]]; then
		while IFS= read -r vol; do 
		    container_commands+=("gluster volume heal $vol info")
			container_commands+=("gluster volume heal $vol info split-brain")
			container_commands+=("gluster volume heal $vol statistics heal-count")
			container_commands+=("gluster volume get $vol all")
			container_commands+=("gluster volume status $vol clients")

			for command in "${container_commands[@]}";do
				temp="$command"
				output_file=${temp// /_}
				timeout "$timeout" oc exec -n "$OCS_NAMESPACE" "$container_name"  -- bash -c "$command" >> "$command_dump_directory"/"$output_file"
			done
		done < "$gluster_volume_list_file"		
	fi
	
}



# Collect common gluster commands output  from one glusterfs pod
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

	oc_exec_gluster_custom_command "$first_gluster_pod" "${gluster_command_dir}"
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

	for (( i=0; i< ${#heketi_commands[@]}; i++ )); do
		oc_exec "$heketi_pod" "${heketi_commands[$i]}" "$heketi_command_output_dir"
	done
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
		print_info "Collecting ${oc_commands[$i]} from $OCS_NAMESPACE"
		# shellcheck disable=SC2206
		# shellcheck disable=SC2086
		timeout "$timeout" ${oc_commands["$i"]} -n "$OCS_NAMESPACE" >> "$oc_command_output_dir"/"$filename"
	done 

}


# To copy config and most-recent log files.

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
	print_info "Copying $temp_string from $servername to $target_directory"
	temp_string=${temp_string// /,}
	
	if [[ "$target_directory" == *"config_file"* ]]; then
		rsync -Ra --info=progress2   "$servername":\{"$temp_string"\} "$target_directory" 
	else
		rsync -Ra --info=progress2 --include='*.log' --include='messages' --include='*/' --exclude='*'  "$servername":\{"$temp_string"\} "$target_directory" 
	fi
}


# Prepare a list of config files to copy from gluster/heketi servers

function collect_config_files() {

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



# Prepare a list of log files to copy from gluster servers

function collect_gluster_log_files() {

	#get_node_name	

	gluster_log_file=()
	gluster_log_file+=("/var/log/glusterfs/")
	gluster_log_file+=("/var/log/messages")

	for n in "${node[@]}"; do
		log_dir="$gluster_log_files_dir"/"$n"
		mkdir "$log_dir"
		copy_data "$n" "$log_dir" "${gluster_log_file[@]}"
	done	
}


# collect heketi logs

function collect_heketi_pod_logs() {
		# Collect heketi pod logs
		timeout $timeout oc logs "$heketi_pod" -n "$OCS_NAMESPACE" >> "$heketi_log_files_dir"/heketi.log		

}


# Function to create a tar file from /tmp/ and remove temporary directory.

function end() {
	
	outputfile="$DATA_COLLECTION_PATH/ocs3-debug.tar.gz"
	tar -zcvf  "$outputfile" "$tempdirname" > /dev/null
	echo "--------------------------"
	print_info "Please upload $outputfile.."
	echo "--------------------------"
	echo "$tempdirname"|grep "/tmp/tmp." # && rm "$tempdirname/*" && rmdir  "$tempdirname"
	
}


initialise

if [ ${#gluster_pod_array[@]} ]; then
	collect_gluster_output
	collect_gluster_output_from_all_glusterfs_pods
else
	print_warning "No glusterfs pod is running, hence can't collect gluster commands output"
fi

if [ -n "$heketi_pod" ]; then
	collect_heketi_output
	collect_heketi_pod_logs
else
	print_warning "Heketi pod is not running, hence can't collect heketi commands output and heketi pod logs"
fi


collect_oc_output

if [ ${#node[@]} ]; then
	collect_config_files
	collect_gluster_log_files
else
	print_warning "No nodes have label glusterfs=storage-host, hence can't collect gluster config and log files"
fi

end