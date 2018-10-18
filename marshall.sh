#!/bin/bash
# Script responsible for executing provided command to a series of boxes, and reporting status back to user.
# TODO: Account for various file permission states
# TODO: Make exit statuses make sense

set -eou pipefail

# exit/return status codes
STATUS_OK=0
STATUS_INVALID_ARGUMENTS=1
STATUS_NO_HOSTS=2
STATUS_THRESHOLD_NOT_REACHED=3

CONFIG_DIR="$HOME/.marshall"
THRESHOLD_FILE="threshold"
HOSTS_FILE="hosts"

function add_host {
	echo "Confirm you wish to add a host to your configuration:"
	options=("y" "n")
	select answer in "${options[@]}"; do
		case $answer in
			"y" )
				break
				;;
			"n" )
				echo "You have declined to add a host to your configuration"
				return $STATUS_OK
				;;
		esac
	done

	while true; do
		echo "Enter host IP address"
		read host_ip

		if [[ -z "$host_ip" ]]; then
			echo "Please provide host IP address"
		else
			echo "Adding '$host_ip' to marshalled hosts"

			if [[ ! -d "$CONFIG_DIR" ]]; then
				mkdir "$CONFIG_DIR"
			fi

			if ! grep "$host_ip" "$CONFIG_DIR/$HOSTS_FILE" >/dev/null 2>&1; then
				echo "$host_ip" >> "$CONFIG_DIR/$HOSTS_FILE"
			fi

			break
		fi
	done
}

function remove_host {
	echo "Confirm you wish to remove a host from your configuration:"
	options=("y" "n")
	select answer in "${options[@]}"; do
		case $answer in
			"y" )
				break
				;;
			"n" )
				echo "You have declined to remove a host from your configuration"
				return $STATUS_OK
				;;
		esac
	done

	# Get all registered hosts
	no_hosts_message="No hosts registered, nothing to remove"
	if [[ ! -f "$CONFIG_DIR/$HOSTS_FILE" ]]; then
		echo "$no_hosts_message"
		return $STATUS_OK
	fi

	hosts=()
	readarray -t hosts < "$CONFIG_DIR/$HOSTS_FILE"
	while true; do
		if [[ "${#hosts[@]}" -eq 0 ]]; then
			echo "$no_hosts_message"
			return $STATUS_OK
		fi

		echo "Select a host to remove:"
		select answer in "${hosts[@]}"; do
			if [[ ! -z "$answer" ]]; then
				# remove old copy of file and remake it, without the removed entry
				rm "$CONFIG_DIR/$HOSTS_FILE"

				for host in "${hosts[@]}"; do
					if [[ "$host" != "$answer" ]]; then
						echo "$host" >> "$CONFIG_DIR/$HOSTS_FILE"
					fi
				done

				break
			fi
		done

		break
	done
}

function set_threshold {
	deleting_threshold=0

	echo "Do you want to set a success threshold?"
	options=("y" "n" "delete old threshold")
	select answer in "${options[@]}"; do
		case $answer in
			"y" )
				break
				;;
			"n" )
				echo "You have declined to set a threshold"
				return $STATUS_OK
				;;
			"delete old threshold" )
				deleting_threshold=1
				break
				;;
		esac
	done

	if [[ "$deleting_threshold" -eq 1 ]]; then
		if [[ -f "$CONFIG_DIR/$THRESHOLD_FILE" ]]; then
			echo "Deleting old threshold"
			rm "$CONFIG_DIR/$THRESHOLD_FILE"
		else
			echo "No threshold was set. Noop"
			return $STATUS_OK
		fi

		return $STATUS_OK
	fi

	while true; do
		echo "Enter a success threshold ( should be a percentage between 0 - 100 ): "
		read threshold

		if [[ -z "$threshold" ]]; then
			echo "Please provide a threshold amount"
		else
			# verify it is a number ( with optional % mark )
			valid_threshold_regex='^([0-9]{1,2}|100)%{0,1}$'
			starts_w_percent_regex='^([0-9]{1,2}|100)%$'
			if [[ ! "$threshold" =~ $valid_threshold_regex ]]; then
				>&2 echo "Invalid threshold '$threshold' provided"
			else
				if [[ "$threshold" =~ $starts_w_percent_regex ]]; then
					# strip % if it is present
					threshold=${threshold:1:${#threshold}}
				fi

				if [[ ! -d "$CONFIG_DIR" ]]; then
					mkdir "$CONFIG_DIR"
				fi

				echo "$threshold" > "$CONFIG_DIR/$THRESHOLD_FILE"
				echo "Threshold now set to $threshold"
				break
			fi
		fi
	done
}

function display_config {
	# For now we can only show hosts file
	# TODO: Make this better
	if [[ ! -f "$CONFIG_DIR/$HOSTS_FILE" ]] && [[ ! -f "$CONFIG_DIR/$THRESHOLD_FILE" ]]; then
		echo "No configuration files detected"
		return $STATUS_OK
	fi

	local printed_hosts=0
	local config_display_text=''
	if [[ -f "$CONFIG_DIR/$HOSTS_FILE" ]]; then
		config_display_text="MARSHALLED HOSTS:"
		config_display_text="${config_display_text}\n$(cat ${CONFIG_DIR}/${HOSTS_FILE})"

		printed_hosts=1
	fi

	if [[ -f "$CONFIG_DIR/$THRESHOLD_FILE" ]]; then
		if [ $printed_hosts -eq 1 ]; then
			config_display_text="${config_display_text}\n\n"
		fi

		config_display_text="${config_display_text}CURRENT THRESHOLD:"
		config_display_text="${config_display_text}\n$(cat ${CONFIG_DIR}/${THRESHOLD_FILE})\n"
	fi

	printf "${config_display_text}"
}

function exec_command {
	exec_command=$1

	# trim any leading and trailing whitespace
	exec_command=${exec_command## }  # remove any leading spaces
	exec_command=${exec_command%% }  # remove any trailing spaces

	# get our threshold ( if any )
	threshold=-1
	if [[ -f "$CONFIG_DIR/$THRESHOLD_FILE" ]]; then
		threshold=$(cat "$CONFIG_DIR/$THRESHOLD_FILE")
	fi

	# store our hosts in an array
	# if no file exists, or there are no hosts error
	# TODO: Stresstest to make sure we make threshold under various number of hosts and failures ( passed base case tests)
	no_hosts_error="No hosts detected. Run './marshall -h' for help menu"
	if [[ -f "$CONFIG_DIR/$HOSTS_FILE" ]]; then
		hosts=()
		readarray -t hosts < "$CONFIG_DIR/$HOSTS_FILE"

		if [[ "${#hosts[@]}" -eq 0 ]]; then
			>&2 echo "$no_hosts_error"
			return $STATUS_NO_HOSTS
		fi

		# send the requested command to all hosts
		number_of_hosts="${#hosts[@]}"
		num_failed_hosts=0
		for host in "${hosts[@]}"; do
			echo "Seinding: '$exec_command' to '$host'"
			if ! ssh "$USER@$host" "\$exec_command"; then
				>&2 echo "Error ssh'ing command to '$USER@$host'"
				num_failed_hosts=$((num_failed_hosts + 1))
			fi
		done

		# see if threshold was passed. If it was not, error out.
		threshold_reached=$(echo - | awk "{ print 100 - ( ( $num_failed_hosts / $number_of_hosts ) * 100 ) }")
		if [[ $threshold_reached -lt $threshold ]]; then
			>&2 echo "Threshold unmet; see above output"
			return $STATUS_THRESHOLD_NOT_REACHED
		fi
	else
		>&2 echo "$no_hosts_error"
		return $STATUS_NO_HOSTS
	fi
}

function print_help {
	cat <<HELP_TEXT
./marshall.sh COMMAND [ -a | --add_host ] [ -d | --display_config ] [ -s | --set_threshold] [ -h | --help ]

Sends command <COMMAND> to a list of predefined hosts. If all hosts report back success,
this utility will exit with success. Else a list of failed hosts is outputted and utility
will exit with failure, unless a threshold <THRESHOLD> is set in which case <THRESHOLD>
hosts must pass for this utility to pass.

If any flags are passed in, <COMMAND> is not executed.

Arguments:
	COMMAND: The command to execute over ssh
		 Note that this command should be sent in an ssh compatable format.
	[ -a | --add_host ]: 	   Add a host to marshall commands to
	[ -r | --remove_host ]:    Remove a currently marshall'able host
	[ -d | --display_config ]: Show current configuration of this utility
	[ -s | --set_threshold ]:  Sets number of hosts that must execute their command successfully
	[ -h | --help ]:           Print this help message
HELP_TEXT
}

# Argument parsing
if [ $# -eq 0 ]; then
	>&2 echo "No arguments passed in"
	print_help

	exit $STATUS_INVALID_ARGUMENTS
fi

adding_host=0
removing_host=0
displaying_config=0
setting_threshold=0
exec_command=''
while test $# -gt 0; do
	case "$1" in
		-h|--help)
			print_help
			exit $STATUS_OK;;
		-a|--add_host)
			adding_host=1;;
		-r|--remove-host)
			removing_host=1;;
		-d|--display_config)
			displaying_config=1;;
		-s|--setting-threshold)
			setting_threshold=1;;
		*)
			exec_command="$exec_command $1";;
	esac

	shift
done

# handle ambiguous commands
num_flags_set=0
all_flags=($adding_host $removing_host $displaying_config $setting_threshold)
for i in "${all_flags[@]}"
do
	:
	if [[ $i == 1 ]]; then
		num_flags_set=$((num_flags_set + 1))
	fi
done

if [[ $num_flags_set -gt 1 ]]; then
	>&2 echo "Flag combination invalid; provide only one flag"
	print_help

	exit $STATUS_INVALID_ARGUMENTS
elif [[ $adding_host == 1 ]]; then
	add_host
elif [[ $removing_host == 1 ]]; then
	remove_host
elif [[ $displaying_config == 1 ]]; then
	display_config
elif [[ $setting_threshold == 1 ]]; then
	set_threshold
else
	exec_command "$exec_command"
	exit $?
fi

exit $STATUS_OK