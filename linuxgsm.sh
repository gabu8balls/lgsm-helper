#!/usr/bin/env bash

######################################################################
# Gabriel (Gabu) Salvador                                            #
# gbsalvador at gmail.com                                            #
#                                                                    #
# Unofficial script for Linux Game Server Manager                    #
# License: GPLv2                                                     #
######################################################################

clear

# Global variables
declare -g VERSION; VERSION="0.1a"; readonly VERSION
declare -g RED; RED=$(tput setaf 1); readonly RED
declare -g GREEN; GREEN=$(tput setaf 2); readonly GREEN
declare -g BLUE; BLUE=$(tput setaf 4); readonly BLUE
declare -g NC; NC=$(tput sgr0); readonly NC
declare -g oIFS; oIFS="$IFS"; readonly oIFS
declare -g GAME
declare -g VOLUME
declare -g USERTCP
declare -g USERUDP
declare -g TCPPORTS
declare -g UDPPORTS

# Functions
function fn_dependency() # Check for required dependencies
{
	local DEPCHECK
	for DEPCHECK in 'docker' 'wget' 'whiptail' 'wc'; do
		if ! command -v "$DEPCHECK" > /dev/null 2>&1; then
			printf "%sI need \'%s\' to run this script%s\n" "${RED}" "${DEPCHECK}" "${NC}"
			exit 1
		fi
	done

	return 0
}

function fn_varcheck() # Check if variable has a valid string
{
	## Ports must be higher than 1024 and lower than 49151
	## Allow dashes and spaces

	## Local variable
	local USERPORTS; USERPORTS="$1"

	## Check if it's empty
	if [[ -n $USERPORTS ]]; then
		## Check if it contains non alpha numeric characters
		if [[ ! $USERPORTS =~ ^[[:alnum:]]+$ ]]; then
			printf "\n%sInvalid port number.%s\n" "${RED}" "${NC}"
			exit 1
		## Or letters
		elif [[ $USERPORTS =~ ^[a-zA-Z]+$ ]]; then
			printf "\n%sInvalid port number.%s\n" "${RED}" "${NC}"
			exit 1
		fi
	fi

	return 0
}

function fn_srvlist() # Download servers list, treat the information and print the result
{
	## Download servers list
	if ! wget -q -O /tmp/serverlist.csv https://raw.githubusercontent.com/GameServerManagers/LinuxGSM/master/lgsm/data/serverlist.csv > /dev/null 2>&1; then
		printf "\n%sI could not download the servers list.%s\n" "${RED}" "${NC}"
		exit 1
	fi

	## Local variables
	local ARRAY=()
	local GAMEID=()
	local GAMENAME=()
	local NUM; NUM=$(wc -l < /tmp/serverlist.csv)
	local X

	## Treat the information
	while IFS=',' read -ra ARRAY; do
		GAMEID+=("${ARRAY[1]}")
		GAMENAME+=("${ARRAY[2]}")
	done < /tmp/serverlist.csv

	## Print the result
	for (( X=0; X < NUM; X++)); do
		printf '%s¦ %s ¦' "${GAMEID[$X]}" "${GAMENAME[$X]}"
	done

	rm /tmp/serverlist.csv

	return 0
}

function fn_game() # Let the user choose the game and specify the port(s) to be exposed
{
	## Local variable
	local GAMESLIST; GAMESLIST=$(fn_srvlist)

	## Create game servers list menu dialog
	IFS="¦"
	GAME=$(whiptail --menu "Choose a game:" --title "LinuxGSM v${VERSION}" 30 60 22 ${GAMESLIST} 3>&1 1>&2 2>&3)
	IFS="$oIFS"

	## And check if didn't left it empty
	if [[ -z $GAME ]]; then
		printf "\n%sYou must choose a game!%s\n" "${RED}" "${NC}"
		exit 1
	fi

	## Check if the volume already exists
	if docker volume ls | grep "$GAME" > /dev/null 2>&1; then
		printf "%sWARNING!!!%s\n\nVolume %s already exists.\nType %sYES%s if you want to proceed: " "${RED}" "${NC}" "${GAME}" "${BLUE}" "${NC}"
		read -r
		if [[ $REPLY != "YES" ]]; then
			exit 1
		fi
		VOLUME=1
	else
		VOLUME=0
	fi

	## Create TCP Ports input dialog
	USERTCP=$(whiptail --title "LinuxGSM v${VERSION}" --inputbox \
	"Please, enter the TCP Ports to be exposed.\nSeparate multiple ports with spaces.\nUse a dash for ranges.\n\ne.g.: 1000 2000-2010 4321" \
	12 60 3>&1 1>&2 2>&3)
	## Check if the input format is OK
	fn_varcheck "$USERTCP"

	## Create UDP Ports input dialog
	USERUDP=$(whiptail --title "LinuxGSM v${VERSION}" --inputbox \
	"Now, enter the UDP Ports to be exposed.\nSame as before: Separate multiple ports with spaces\nand a dash for ranges.\n\ne.g.: 1000 2000-2010 4321" \
	12 60 3>&1 1>&2 2>&3)
	## Check if the input format is OK
	fn_varcheck "$USERUDP"

	## And check if they're not both empty
	if [[ -z $USERTCP && -z $USERUDP ]]; then
		printf "\n%sYou must type at least one TCP or UDP port.%s\n" "${RED}" "${NC}"
		exit 1
	fi

	## So far, so good
	printf "\nMoving on...\n"

	return 0
}

function fn_ports() # Arrange TCP and/or UDP port(s)
{
	## Local variable
	local ARRAY=()
	
	## If there are TCP ports defined, arrange them
	if [[ -n "${USERTCP}" ]]; then
		local Y; Y=0
		IFS=' ' read -r -a ARRAY <<< "$USERTCP"
		while [ "$Y" -lt "${#ARRAY[@]}" ]; do
			TCPPORTS="$TCPPORTS -p ${ARRAY[$Y]}:${ARRAY[$Y]}/tcp"
			(( Y++ )) || true
		done
		IFS="$oIFS"
	fi

	## If there are UDP ports defined, arrange them
	if [[ -n "${USERUDP}" ]]; then
		local Z; Z=0
		IFS=' ' read -r -a ARRAY <<< "$USERUDP"
		while [ "$Z" -lt "${#ARRAY[@]}" ]; do
			UDPPORTS="$UDPPORTS -p ${ARRAY[$Z]}:${ARRAY[$Z]}/udp"
			(( Z++ )) || true
		done
		IFS="$oIFS"
	fi

	return 0
}

function fn_volume() # Create or use existing Docker volume
{
	## If volume does not exist, then create it
	if [[ "${VOLUME}" == "0" ]]; then
		printf "\nCreating Docker volume %s to store your game files...\n" "${GAME}"
		docker volume create "${GAME}" > /dev/null 2>&1
	## If volume already exist, ask to use it
	elif [[ "${VOLUME}" == "1" ]]; then
		printf "\nUsing Docker volume %s previously created.\n\n%sTHIS IS YOUR LAST CHANCE TO NOT RUIN EVERYTHING.%s\n" "${GAME}" "${RED}" "${NC}"
		printf "\nType %sYES%s if you want to proceed: " "${BLUE}" "${NC}"
		read -r
		### Exit if answer is not YES
		if [[ $REPLY != "YES" ]]; then
			exit 1
		fi
	## WHAT THE F***
	else
		printf "\n%sHOW DID YOU GET HERE, PEASANT?%s\n" "${RED}" "${NC}"
		exit 1
	fi

	return 0
}

function fn_container() # Ask one last time if I should create the container
{
	## Just DO IT
	if (whiptail --title "LinuxGSM v${VERSION}" --yesno "I will create a Docker container named ${GAME}.\nProceed?" 10 60); then
		printf "\nCreating %s%s%s container.\nPlease wait...\n" "${GREEN}" "${GAME}" "${NC}"
		docker run -d -i -t --init -h $GAME --name $GAME -u linuxgsm --restart unless-stopped -v $GAME:/home/linuxgsm $TCPPORTS $UDPPORTS \
		-e GAMESERVER=$GAME -e LGSM_GITHUBUSER=GameServerManagers -e LGSM_GITHUBREPO=LinuxGSM -e LGSM_GITHUBBRANCH=master \
		gameservermanagers/linuxgsm-docker:latest > /dev/null 2>&1
	## Aborting and deleting volume
	elif [[ "${VOLUME}" == "0" ]]; then
		printf "\nRemoving %s volume.\n" "${GAME}"
		docker volume rm "${GAME}" > /dev/null 2>&1
		exit 1
	## Aborting and preserving volume
	elif [[ "${VOLUME}" == "1" ]]; then
		printf "\nDon't worry. Volume %s will be preserved. Bye!\n" "${GAME}"
		exit 1
	fi

	return 0
}

# Main
fn_dependency

fn_game

fn_ports

fn_volume

fn_container

exit 0