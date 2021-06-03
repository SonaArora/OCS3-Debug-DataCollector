
- The script (collect-command-output.sh) is created to collect commonly used data required for troubleshooting OCS 3 issues.

- Environment to run script : OCS 3.11 Converged Mode Cluster

- The script collects:

    * Gluster commands output from glusterfs pods
    * Heketi commands output from heketi pod
    * oc command output
    * Configuration files of gluster from the storage nodes
    * Logs of gluster from storage nodes
    * Logs of heketi pod 

- Prerequisite to run script:

    * Script should be run from master node
    * Requires a user that has access to all hosts. If you want to run the installer as a non-root user, first configure passwordless sudo rights each host. This is one of thre prerequiste of OCP installation.

- How to run script:

~~~
bash collect-command-output.sh <-d|--directory-name> <-n|--namespace> [-t|--timeout]
~~~

Run script with --help or -h option to understand the arguments:

~~~
./collect-command-output.sh -h
		
	collect-command-output.sh, collect-command-output:   This script will collect data for OCS 3 converged mode:
                                 1. Gluster commands output from gluster pods
                                 2. Heketi commands output from heketi pod
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
~~~

- The script dumps the output in a temporary directory at /tmp, and once all data is captured, it will tar it in the directory user has specified in the command line argument. And then it removes the temporary directory created.

- The script checks if minimum 1 Gb space is available at /tmp before dumping data. If free space is less than 1 Gb, it will not dump data and exit.


Ex.:

~~~
./collect-command-output.sh -n app-storage -d /root/dump-ocs-data
 Info : Collecting gluster volume list from glusterfs-storage-c6gtt
 Info : Collecting gluster volume info from glusterfs-storage-c6gtt
 Info : Collecting gluster volume status from glusterfs-storage-c6gtt

[..]
--------------------------
 Info : Please upload /root/dump-ocs-data/ocs3-debug.tar.gz..
--------------------------

~~~
