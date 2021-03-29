# OCS3-Debug-DataCollector
It's a tool to collect data for debugging OCS 3 issues.

- The script (collect_command.sh) is suppose to collect :

1. gluster, heketi and oc command output
2. Config files
3. Log files

* The script is aimed to collect data for **OCS 3 Converged Mode**. For Independent mode, sosreport can be collected.

- How to run the script:

# ./collect_command.sh <Directory-to-dump-data> <ocs-namespace>
  
Ex.: ./collect-command-output.sh  ocs3-dump app-storage

- Below is the structure of directories the script will create:

├── command_output
│   ├── from_each-gluster_pods
│   ├── gluster_command_output
│   │   ├── gluster_peer_status
│   │   ├── gluster_pool_list
│   │   ├── gluster_volume_get_all_cluster.op-version
│   │   ├── [..]
│   ├── heketi_command_output
│   │   ├── heketi-cli_server_operations_info
│   │   ├── heketi-cli_topology_info
│   │   └── [..]
│   └── oc_command_output
│       ├── oc_get_all
│       ├── oc_get_nodes
│       ├── oc_get_pods_-o_wide
│       └── [..]
├── config_file
│   ├── gluster
│   └── heketi
└── logs
    ├── gluster
    └── heketi



