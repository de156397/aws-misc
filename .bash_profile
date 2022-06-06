
# ssh-agent processing
## 1st let's make a list of user processes:
##
## msi2n@viator MINGW64 ~
## make a list of the current user processes
## $ ps -u $(id -un)
##      PID    PPID    PGID     WINPID   TTY         UID    STIME COMMAND
##     2595    2315    2595      45332  pty1      197609 21:25:37 /usr/bin/ps
##     2373       1    2373       2928  ?         197609 17:58:22 /usr/bin/mintty
##     1869       1    1869      26948  ?         197609   May 25 /usr/bin/ssh-agent
##     2374    2373    2374      54756  pty0      197609 17:58:22 /usr/bin/bash
##     2556       1    2556      39804  ?         197609 21:24:19 /usr/bin/ssh-agent
##     2315    2314    2315      56116  pty1      197609 17:42:32 /usr/bin/bash
##     2314       1    2314      34852  ?         197609 17:42:32 /usr/bin/mintty
##
## issue with above list is the variable count of words of STIME column in each row
## only the PID and COMMAND column of lines matching "ssh-agent" matter for our processing
##
## msi2n@viator MINGW64 ~
## $ ps -u $(id -un) | sed -ne '/ssh-agent/{;s/ *\([0-9][0-9]*\).*\(ssh-agent\).*$/\1 \2/;p;}'
## 1869 ssh-agent
## 2556 ssh-agent

function ssh-agent_clean {
	local ssh_agent_pid="$1"
	local ssh_auth_sock=${2:-$( find /tmp -maxdepth 2 -type s -name agent.$((ssh_agent_pid - 1 )) 2>/dev/null )}
	local ssh_auth_dir=${ssh_auth_sock%/agent.*}
	[[ -n "$ssh_agent_pid" ]] && ps -p $ssh_agent_pid &> /dev/null && kill $ssh_agent_pid || :
	## on termination ssh-agent is supposed to clear socket file and /tmp/ssh-* subfolder
	[[ -s "$ssh_auth_sock" ]] && rm $ssh_auth_sock 2>/dev/null || :
	[[ -d "${ssh_auth_dir}" ]] && rmdir ${ssh_auth_dir} 2>/dev/null || :
	return 0
}

function  ssh-agent_check {
	local ssh_agent_pid=$1
	local ssh_auth_sock=$(find /tmp -maxdepth 2 -type s -name agent.$((ssh_agent_pid - 1 )) 2>/dev/null )
	local success="0" error="1"
	local return_value=$error
	local key_list key_count status
	if [[ -s $ssh_auth_sock ]]
	then
		key_list=$(SSH_AUTH_SOCK="$ssh_auth_sock" ssh-add -l 2>&1)
		key_count=$( echo "$key_list" | wc -l ) # double quotes matter!
		(( key_count == 1 )) && status="identity" || status="identities"
		case ${key_count}${key_list}
		in
			"1The agent has no identities.")
				identity="no $status"
				action=ssh-agent_clean $ssh_agent_pid $ssh_auth_sock
				;;
			*@(SHA256)*)
				(( key_count == 1 )) && status="one $status" || status="$key_count $status"
				echo "export SSH_AGENT_PID=$ssh_agent_pid SSH_AUTH_SOCK=$ssh_auth_sock" > ~/.ssh/.agentrc
				source ~/.ssh/.agentrc
				return_value=$success
				;;
			*)      ## "Could not open a connection to your authentication agent." and anything else
				ssh-agent_clean $ssh_agent_pid $ssh_auth_sock
				;;
		esac
	else
		ssh-agent_clean $ssh_agent_pid $ssh_auth_sock
	fi
	if [[ $return_value == $success ]]
	then
		printf "ssh-agent with PID %s has %s loaded\n" $ssh_agent_pid $status
		printf "%s\n" "$key_list"
	fi
	return $return_value
}
##
[[ -z "$SSH_AUTH_SOCK" && action=ssh-agent_resume || :
while [[ -n "$action" ]]
do
	case $action in
	"ssh-agent_resume")
		if [[ -f ~/.ssh/.agentrc ]]
		then
			source ~/.ssh/.agentrc
			if [[ -n "$SSH_AGENT_PID" ]] && ps -p $SSH_AGENT_PID &> /dev/null
			then
				if [[ -n "$SSH_AUTH_SOCK" && -s "$SSH_AUTH_SOCK" ]]
				then
					action=ssh-agent_search
				else
					ssh-agent_clean $SSH_AGENT_PID $SSH_AUTH_SOCK
					unset SSH_AGENT_PID SSH_AUTH_SOCK
				fi
			else
				ssh-agent_clean $SSH_AGENT_PID $SSH_AUTH_SOCK
				unset SSH_AGENT_PID SSH_AUTH_SOCK
			fi
		else
			rm ~/.ssh/.agentrc
			action=ssh-agent_search
		fi
		;;
	"ssh-agent_search")
		declare -a aAgent=($(ps -u $(id -un) | sed -ne '/ssh-agent/{;s/ *\([0-9][0-9]*\).*ssh-agent.*$/\1/;p;}'))
		for (( nAgentIndex=0 ; nAgentIndex<${#aAgent[*]} ; nAgentIndex++ ))
		do
			if [[ $action == "ssh-agent_search" ]]
			then
				if ssh-agent_check
				then
					aAgent[$nAgentIndex]=""
					unset action
				fi
			else
				ssh-agent_clean ${aAgent[$nAgentIndex]}
			fi
		done
		[[ $action == "ssh-agent_search" ]] && action="ssh-agent_boot" || :
		unset pid aAgent nAgentIndex
		;;
	"ssh-agent_boot")
		## kill any stray ssh-agent and consider there is no pkill and only a poor ps command on Git-Bash available
		ps -u $(id -un) | sed -ne '/ssh-agent/{;s/ *\([0-9][0-9]*\).*ssh-agent.*$/\1/;p;}' | xargs -rI pid kill pid
		## remove any orphaned socket file
		find /tmp -maxdepth 1 -user $(id -un) -type d -name ssh-\* 2>/dev/null | xargs -rI dir find dir -type s -delete
		## remove any empty ssh socket dir
		find /tmp -maxdepth 1 -user $(id -un) -type d -name ssh-\* -empty -delete 2>/dev/null
		## launch ssh-agent and preserve its environment configuration writtenton STDOUT in ~/.ssh/.agentrc file
		if ( cd ~/.ssh && ssh-agent | grep -v ^echo > .agentrc 2>/dev/null )
		then
			if source ~/.ssh/.agentrc ## source ssh-agent environment setting
			then
				## prepare a list of private key file names to load
				typeset -i nIndex=0
				declare -a aPrivateKeys
				while read strKeyName
				do
					aPrivateKeys[$nIndex]=$strKeyName
					(( nIndex++ ))
				done <<< "$(cd ~/.ssh && file * | sed -ne '/OpenSSH.*private key/ {;s/: *OpenSSH private key//;p;};' )"
				## write numbered list of OpenSSH private keyfiles in ~/.ssh folder
				if (( ${#aPrivateKeys[0]} > 0 ))
				then
					nIndex=0
					while (( nIndex > 0 ))
					do
						[[ -n ${aPrivateKeys[nIndex]} ]] && printf "%2d) %s\n" $(( nIndex + 1 )) "${aPrivateKeys[nIndex]%.pem}"
						(( nIndex++ ))
					done
					read -p "Please input the numbers you'd like to load or none to skip: "
					declare -a aNumbers=($REPLY)
					if (( ${#aNumbers[*]} > 0 ))
					then
						for nIndex in ${aNumbers[*]}
						do
							printf "loading private key %s\n" "${aPrivateKeys[nIndex]%.pem}"
							( cd ~/.ssh && ssh-add ${aPrivateKeys[nIndex]} )
						done
					fi
				else
					[[ -t 2 ]] && printf "no OpenSSH private key files found in ~/.ssh folder\n" >&2 || :
				fi
			else
				[[ -t 2 ]] && printf "Error $? reading file ~/.ssh/.agentrc\n" >&2 || :
			fi
		else
			[[ -t 2 ]] && printf "Error $? on attempt to start ssh-agent\n" >&2 || :
		fi
		unset action nIndex aPrivateKeys strKeyName aNumbers REPLY
		;;
	esac
done

find /tmp -maxdepth 1 -user $(id -un) -type d -name ssh-\* | xargs -rI dir find dir -type s
find /tmp -maxdepth 1 -user $(id -un) -type d -name ssh-\* -empty | xargs -rI dir rmdir dir

