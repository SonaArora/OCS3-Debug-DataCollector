#!/bin/bash

gluster_pod=""
heketi_pod=""
first_gluster_pod=""
        # Data collection path is an arugment

DATA_COLLECTION_PATH=$1

function get_pod_name(){

	gluster_pods=$(oc get pods -n app-storage |grep glusterfs|awk '{print $1}')
	heketi_pod=$(oc get pods -n app-storage |grep heketi|awk '{print $1}')
	first_gluster_pod=$(echo $gluster_pods|awk '{print $1}')
}


function initialise() {
        
tempdirname=$(mktemp -d)

mkdir $tempdirname/command_output
mkdir $tempdirname/logs
mkdir $tempdirname/config_file


gluster_command_dir="$tempdirname/command_output/gluster_command_output"
heketi_command_output="$tempdirname/command_output/heketi_command_output"
oc_command_output="$tempdirname/command_output/oc_command_output"
gluster_config_files="$tempdirname/logs/gluster_config_files"
gluster_log_file="$tempdirname/config_file/gluster_log_file"
heketi_log_file="$tempdirname/config_file/heketi_log_file"

mkdir "$gluster_command_dir"
mkdir "$heketi_command_output"
mkdir "$oc_command_output"
mkdir "$gluster_config_files"
mkdir "$heketi_log_file"



# If no argument is passed, use present working directory
        if [ -z "${DATA_COLLECTION_PATH}" ]; then
                DATA_COLLECTION_PATH=$(pwd)
        fi

        # gluster data collection path
        GLUSTER_COLLECTION_PATH="${DATA_COLLECTION_PATH}/gluster"
        get_pod_name
}




function oc_exec() {
        container_name="$1"
        container_command="$2"
        #file=${gluster_commands[$i]}
        #filename=${file// /_}
        file=$container_command
        filename=${file// /_}
        echo "Collecting $2 from $1"
        oc exec "$container_name"  -- bash -c "$container_command" >> "$gluster_command_dir/$filename"

}



function collect_command(){

# gluster commands
        gluster_commands=()
        gluster_commands+=("gluster peer status")
        gluster_commands+=("gluster volume list")
        #gluster_commands+=("gluster pool status")
        gluster_commands+=("gluster volume info")
        #gluster_commands+=("gluster volume status")
        #gluster_commands+=("gluster volume heal")

#                oc exec glusterfs-storage-hcv4w -- for (( i=0; i< ${#gluster_commands[@]}; i++ )); do temp=""; temp=${gluster_commands[i]}; temp > ${temp// /_} ;done

for (( i=0; i< ${#gluster_commands[@]}; i++ )) ; do
	
	oc_exec "glusterfs-storage-hcv4w" "${gluster_commands[$i]}"
    #  oc exec glusterfs-storage-hcv4w -- bash -c "${gluster_commands[$i]}" >> /tmp/"$filename"
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

initialise
collect_command
end 

