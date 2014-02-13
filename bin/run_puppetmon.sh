#!/bin/bash
#
# stage puppetmon
########################

IFS='
	 '

DIR="$( cd "$( dirname "$0" )" && pwd )"
OS=`uname -s`

PATH=/bin:/usr/bin:/sbin:/usr/sbin:$DIR
export PATH

SSH='ssh -nT'
SSHUSER=black
SUDO='source .bash_profile; sudo'

#---
# print error message to stderr and exit
error()
{
    echo "$0: $@" 1>&2
    exit 1
}

#---
# print warning message to stderr
warn()
{
    echo "$0: $@" 1>&2
}

#---
# print debug message
#
debug()
{

    if [ -n "$DEBUG" ]; then
        echo "$0 - DEBUG: $@"
    fi
}

#---
# print usage and exit
usage()
{
    echo "Usage: $0 [-t] -i <file with hostname>"
    exit 1
}

stage_linux ()
{
	HOST=$1

	echo "staging puppetmon to $HOST (Linux)"

	scp puppetmon $SSHUSER@$HOST: 2>&1 > /dev/null
	$SSH $SSHUSER@$HOST "sudo mv puppetmon /usr/bin/"
	$SSH $SSHUSER@$HOST "sudo chmod 755 /usr/bin/puppetmon"
}

stage_other ()
{
	HOST=$1
	REMOTE_OS=`$SSH $SSHUSER@${host} "uname -s"`
		
	case "$REMOTE_OS" in
		SunOS)
		SUDO='source .bash_profile; sudo'
		;;

		*)
		SUDO='sudo'
		;;
	esac

	echo "staging puppetmon to $HOST (SunOS/AIX)"

	scp puppetmon $SSHUSER@$HOST: 2>&1 > /dev/null
	$SSH $SSHUSER@$HOST "$SUDO mv puppetmon /opt/puppet/bin/"
	$SSH $SSHUSER@$HOST "$SUDO chmod 755 /opt/puppet/bin/puppetmon"
}

run_puppetmon()
{
	INPUTFILE=$1

	while read host; do 
		REMOTE_OS=`$SSH $SSHUSER@${host} "uname -s"`
		
		case "$REMOTE_OS" in
			SunOS)
			PUPPETMON='/opt/puppet/bin/ruby /opt/puppet/bin/puppetmon'
			SUDO='source .bash_profile ; sudo'
			;;

			AIX)
			PUPPETMON='/opt/puppet/bin/ruby /opt/puppet/bin/puppetmon'
			SUDO='sudo'
			;;

			*)
			PUPPETMON='puppetmon'
			SUDO='sudo'
			;;
		esac

		echo "running puppetmon on $host with command $PUPPETMON"
		$SSH $SSHUSER@$host "$SUDO $PUPPETMON"
	done < $INPUTFILE
}

connect()
{
	HOST=$1

(
	$SSH $SSHUSER@$host "source .bash_profile ; echo ok" 1>/dev/null 2>&1 &
	SSH_PID=$!

	declare -i timeout=5
	while ((timeout > 0)); do
		sleep 1
		kill -0 $SSH_PID 2>/dev/null || {
			wait $SSH_PID	
			SSH_STATUS=$?
			[ $SSH_STATUS -ne 0 ] && return $SSH_STATUS
			return 0
		}
		((timeout -= 1))
	done

	kill -s SIGTERM $SSH_PID && kill -0 $SSH_PID 2>/dev/null || return 0
	sleep 5
	kill -s SIGKILL $SSH_PID
) 

}

save_status()
{
	declare -a array=("${!1}")
	filename=$2

	[ -f "$filename" ] && error "failed.hosts file exists, please remove it"

	for line in "${array[@]}"; do
		echo $line
	done >> $filename
}

test_sudo()
{
	HOST=$1

	REMOTE_OS=`$SSH $SSHUSER@${host} "uname -s"`
	case "$REMOTE_OS" in
		SunOS)
		SUDO='source .bash_profile; sudo'
		;;

		*)
		SUDO='sudo'
		;;
	esac

	$SSH $SSHUSER@$host "$SUDO echo ok" 1>/dev/null
	return $?
}

test_connectivity()
{
	INPUTFILE=$1

	declare -a okhosts
	declare -a failedhosts

	while read host; do
		connect $host
		STATUS=$?
		if [ $STATUS -eq 0 ]; then
			test_sudo $host
			STATUS=$?
			if [ $STATUS -eq 0 ]; then
				echo "$host ok"
				okhosts=("${okhosts[@]}" "$host")
			else
				echo "$host not ok (sudo)"
				failedhosts=("${failedhosts[@]}" "$host $STATUS")
			fi
		else
			echo "$host not ok (connectivity)"
			failedhosts=("${failedhosts[@]}" "$host $STATUS")
		fi
	done < $INPUTFILE

	save_status okhosts[@]  ok.hosts
	save_status failedhosts[@] failed.hosts
}

stage()
{
	INPUTFILE=$1
	while read host; do
		REMOTE_OS=`$SSH $SSHUSER@${host} "uname -s"`
		
		case "$REMOTE_OS" in
	
			Linux)
			stage_linux $host
			;;
	
			SunOS|AIX)
			stage_other $host
			;;
		esac
	done < $INPUTFILE
}

#---
# MAIN
# 

test $# -eq 0 && usage

while test $# -gt 0
do
    case $1 in
	-t | --test)
            TEST=true
	    ;;
        -i | --inputfile)
            INPUTFILE=$2
            shift
            ;;
	-r | --run)
	    RUN=true
	    ;;
        -*)
            error "Unrecognized option: $1"
            ;;
        *)
            break
            ;;
    esac
    shift
done

[ ! -f "$INPUTFILE" ] && error "$INPUTFILE does not exist!"

if [ "$TEST" == "true" ]; then
	test_connectivity $INPUTFILE
elif [ "$RUN" == "true" ]; then
	run_puppetmon $INPUTFILE
else
	stage $INPUTFILE
fi

