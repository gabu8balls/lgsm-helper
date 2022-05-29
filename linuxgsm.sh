#!/usr/bin/env bash

######################################################################
# Gabriel (Gabu) Salvador                                            #
# gbsalvador at gmail.com                                            #
#                                                                    #
# André (Magrão) Borali                                              #
# andreborali at gmail.com                                           #
#                                                                    #
#                                                                    #
#                                                                    #
# Unofficial script to create a LinuxGSM container                   #
# License: Creative Commons                                          #
######################################################################



######################################################################
#                          GLOBAL VARIABLES                          #
######################################################################

declare -gr VERSION="0.1a"
declare -gr oIFS="$IFS"

declare -g RED; RED=$(tput setaf 1)
declare -g GREEN; GREEN=$(tput setaf 2)
declare -g BLUE; BLUE=$(tput setaf 4)
declare -g NC; NC=$(tput sgr0)

declare -gi VOLUME

declare -g GAME
declare -g USERTCP
declare -g USERUDP
declare -g TCPPORTS
declare -g UDPPORTS

######################################################################
#                             FUNCTIONS                              #
######################################################################

function fn_depcheck() # Check for dependencies
{
	declare DEPCHECK

	for DEPCHECK in "$@"; do
		if ! command -v "${DEPCHECK}" > /dev/null 2>&1; then
			printf "\n%sI need \'%s\' to run this script.%s\n" "${RED}" "${DEPCHECK}" "${NC}"
			exit 1
		fi
	done

	return 0
}

function fn_srvlist() # Process the server list data
{
	declare -a GAMEARRAY
	declare -a GAMEID
	declare -a GAMENAME
	declare -ir NUM=$(wc -l < /tmp/serverlist.csv)
	declare -i X

	while IFS=',' read -ra GAMEARRAY; do
		GAMEID+=("${GAMEARRAY[1]}")
		GAMENAME+=("${GAMEARRAY[2]}")
	done < /tmp/serverlist.csv

	IFS="$oIFS"

	for (( X=0; X < NUM; X++ )); do
		printf '%s¦ %s ¦' "${GAMEID[$X]}" "${GAMENAME[$X]}"
	done

	return 0
}

function fn_menu() # Create the menu
{
	## Process the server list data
	declare GAMESLIST; GAMESLIST=$(fn_srvlist)

	IFS="¦"
	GAME=$(whiptail --menu "Choose a game:" --title "LinuxGSM v${VERSION}" 30 60 22 ${GAMESLIST} 3>&1 1>&2 2>&3)
	IFS="$oIFS"

	if [[ -z ${GAME} ]]; then
		printf "\n%sYou must choose a game.%s\n" "${RED}" "${NC}"
		exit 1
	fi

	return 0
}

function fn_varcheck() # Check if variable has a valid string
{
	declare USERPORTS="$1"
	declare -a PORTRANGE
	declare -a PORTLIST
	declare -a RANGETEMP
	declare -i RANGE1ST
	declare -i RANGE2ND
	declare PORTTEST

	if [[ -n "${USERPORTS}" ]]; then
		if [[ ! ${USERPORTS} =~ ^([0-9]{1,5}\-[0-9]{1,5}|[0-9]{1,5})(\ ([0-9]{1,5}\-[0-9]{1,5}|[0-9]{1,5}))*$ ]]; then
			printf "\n%sSorry, invalid format.\nIt must be like this: 27015 27020-27030 30000%s\n" "${RED}" "${NC}"
			exit 1
		fi

		IFS=' '
		read -r -a PORTRANGE <<< "${USERPORTS}"
		IFS="$oIFS"
		USERPORTS=$(echo "${USERPORTS}" | tr "-" " ")
		IFS=' '
		read -r -a PORTLIST <<< "${USERPORTS}"
		IFS="$oIFS"

		for PORTTEST in "${PORTRANGE[@]}"; do
			if [[ ${PORTTEST} =~ \- ]]; then
				PORTTEST=$(echo "${PORTTEST}" | tr "-" " ")
				RANGETEMP=( "${PORTTEST}" )
				RANGE1ST="${RANGETEMP[0]}"
				RANGE2ND="${RANGETEMP[1]}"
				if [[ "${RANGE1ST}" -ge "${RANGE2ND}" ]]; then
					printf "\n%sIn a port range, the first value must be lower than the second.%s\n" "${RED}" "${NC}"
					exit 1
				fi
			fi
		done

		for PORTTEST in "${PORTLIST[@]}"; do
			if [[ ! ${PORTTEST} =~ [0-9]{4,5} ]]; then
				printf "\n%sPort(s) must be higher than 1024 and lower than 49151.%s\n" "${RED}" "${NC}"
				exit 1
			fi

			if [[ ${PORTTEST} -lt 1025 || ${PORTTEST} -gt 49150 ]]; then
				printf "\n%sPort(s) must be higher than 1024 and lower than 49151.%s\n" "${RED}" "${NC}"
				exit 1
			fi
		done
	fi

	return 0
}

function fn_ports() # Arrange TCP and/or UDP port(s)
{
	declare -a PORTARRAY
	declare -i Y=0
	declare -i Z=0

	if [[ -n "${USERTCP}" ]]; then
		IFS=' ' read -r -a PORTARRAY <<< "${USERTCP}"

		while [ "$Y" -lt "${#PORTARRAY[@]}" ]; do
			TCPPORTS="$TCPPORTS -p ${PORTARRAY[$Y]}:${PORTARRAY[$Y]}/tcp"
			(( Y++ )) || true
		done

		IFS="$oIFS"
	fi

	if [[ -n "${USERUDP}" ]]; then
		IFS=' ' read -r -a PORTARRAY <<< "${USERUDP}"

		while [ "$Z" -lt "${#PORTARRAY[@]}" ]; do
			UDPPORTS="$UDPPORTS -p ${PORTARRAY[$Z]}:${PORTARRAY[$Z]}/udp"
			(( Z++ )) || true
		done

		IFS="$oIFS"
	fi

	return 0
}

######################################################################
#                                MAIN                                #
######################################################################

clear

## Check for dependencies
fn_depcheck "docker" "wget" "whiptail" "wc" "tr"

# Get the latest LinuxGSM server list from GitHub
if ! wget -q -O /tmp/serverlist.csv https://raw.githubusercontent.com/GameServerManagers/LinuxGSM/master/lgsm/data/serverlist.csv > /dev/null 2>&1; then
	printf "\n%sOops! I could not download the servers list.%s\n" "${RED}" "${NC}"
	exit 1
fi

## Create the menu
fn_menu

# Remove server list temp file
rm /tmp/serverlist.csv

# Check if game server already exists
if docker container ls | grep "${GAME}" > /dev/null 2>&1; then
	printf "\n%sWARNING!!!%s\n\nGame server %s already exists.\nPlease, select another game.\n" "${RED}" "${NC}" "${GAME}"
	exit 1
fi

if docker volume ls | grep "${GAME}" > /dev/null 2>&1; then
	printf "\n%sWARNING!!!%s\n\nThere is already a repository for %s.\nType %sYES%s if you want to use it: " "${RED}" "${NC}" "${GAME}" "${BLUE}" "${NC}"
	read -r
	if [[ $REPLY != "YES" ]]; then
		printf "\n%sExiting...%s\n" "${GREEN}" "${NC}"
		exit 0
	fi
	printf "\n%sUsing existing repository...%s\n" "${GREEN}" "${NC}"
	VOLUME=1
else
	VOLUME=0
fi

# Get the TCP port(s) to be exposed
USERTCP=$(whiptail --title "LinuxGSM v${VERSION}" --inputbox \
"Please, enter the TCP Ports to be exposed or leave empty if none.\nSeparate multiple ports with spaces.\nUse a dash for ranges.\n\ne.g.: 27015 27020-27030 30000" \
12 70 3>&1 1>&2 2>&3)

## Check if variable has a valid string
fn_varcheck "${USERTCP}"

# Get the UDP port(s) to be exposed
USERUDP=$(whiptail --title "LinuxGSM v${VERSION}" --inputbox \
"Now, enter the UDP Ports to be exposed or leave empty if none.\nSame as before: Separate multiple ports with spaces\nand a dash for ranges.\n\ne.g.: 27015 27020-27030 30000" \
12 70 3>&1 1>&2 2>&3)

## Check if variable has a valid string
fn_varcheck "${USERUDP}"

# Check if both variables are not empty
if [[ -z ${USERTCP} && -z ${USERUDP} ]]; then
	printf "\n%sYou must type at least one TCP or UDP port.%s\n" "${RED}" "${NC}"
	exit 1
fi

## Arrange TCP and/or UDP port(s)
fn_ports

# Create the container
if (whiptail --title "LinuxGSM v${VERSION}" --yesno "I will create a Docker container named ${GAME}.\nProceed?" 10 60); then
	printf "\nCreating %s%s%s container.\nPlease wait, this may take a while...\n" "${GREEN}" "${GAME}" "${NC}"
	if [[ "${VOLUME}" == "0" ]]; then
		printf "\nCreating Docker volume %s to store your game files.\n" "${GAME}"
		docker volume create "${GAME}" > /dev/null 2>&1
	elif [[ "${VOLUME}" == "1" ]]; then
		printf "\nUsing Docker volume %s previously created.\n" "${GAME}"
	fi
	eval docker run -d -i -t --init -h "${GAME}" --name "${GAME}" -u linuxgsm --restart unless-stopped -v "${GAME}":/home/linuxgsm "${TCPPORTS}" "${UDPPORTS}" \
	-e GAMESERVER="${GAME}" -e LGSM_GITHUBUSER=GameServerManagers -e LGSM_GITHUBREPO=LinuxGSM -e LGSM_GITHUBBRANCH=master \
	gameservermanagers/linuxgsm-docker:latest > /dev/null 2>&1
else
	printf "\nAborting...\n"
fi

exit 0
