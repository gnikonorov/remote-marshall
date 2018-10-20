# REMOTE MARSHALL

__Remote marshall is a shell script that is responsible for coordinating commands over ssh to a set of pre-defined hosts.__

## Description

Remote marshall is used to orchestrate ssh commands to a set of user defined hosts. The script will send a requested command to the set of hosts and note any erroring hosts.

Additionally, a _threshold_ may be set. A threshold is the indication of the minimum number hosts required to pass in order for script run to be considered a success. If threshold is not met for a run of `marshall.sh`, the script will terminate with an exit code of 2 and output an error to `STDOUT`.

## Commands

The following commands may be run for this script.

1. --add_host

   This command will add a host to the list of _marshalled hosts_. These are hosts that this script will send commands over ssh to.

2. --remove_host

   Remove a host from the list of _marshalled hosts_. This means that this script will no longer send ssh commands to the host.

3. --display_config

   Output a list of hosts that are currently _marshalled hosts_ and also output the set threshold ( if defined ).

4. --set_threshold

   Set the threshold that must be met in order for a run of `marshall.sh` to count as a success. This number is interpretted as a percentage, and if less than threshold% hosts report success, the script will exit with status 2.

For the help menu of this script, please run `./marshall.sh -h`

## Limitations

This script will not validate that the commands provided to it are executable on the remote hosts. This is left up to the user to verify before invocation of this script.