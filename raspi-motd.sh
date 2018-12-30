#!/bin/bash
#: put this file to /etc/profile.d/<ANYTHING>.sh
#: stolen from: https://github.com/Detmud/raspberrypi-motd/blob/master/motd.sh


RED=$(tput setaf 1)
GRE=$(tput setaf 2)
YEL=$(tput setaf 3)
BLU=$(tput setaf 4)
WHI=$(tput setaf 7)


VAR_UPTIME="$(uptime | sed -E 's/^[^,]*up *//; s/, *[[:digit:]]* user.*//; s/min/minutes/; s/([[:digit:]]+):0?([[:digit:]]+)/\1 hours, \2 minutes/')"
VAR_MEMORY="$(free -m | awk 'NR==2 { printf "Total: %sMB, Used: %sMB, Free: %sMB",$2,$3,$4; }')"
VAR_SPACE="$(df -h ~ | awk 'NR==2 { printf "Total: %sB, Used: %sB, Free: %sB",$2,$3,$4; }')"
VAR_LOADAVG="$(cat /proc/loadavg | awk '{print $1,$2,$3}')"
VAR_PROCESSES="$(ps ax | wc -l | tr -d " ")"
VAR_IP_INTERN="$(hostname -I)"
#VAR_IP_EXTERN="$(wget -q -O - http://icanhazip.com/ | tail)"
VAR_TEMP="$(/opt/vc/bin/vcgencmd measure_temp | cut -c "6-9")°C"
VAR_LAST_LOGIN="$(last -i $USER -F | grep -v 'still logged' | head -1 | awk '{print $6,$5,$8,$7}')"
VAR_DATE="$(date +"%A, %e %B %Y, %R")"
VAR_UNAME="$(uname -snrmo)"
VAR_TYPE="$(cat /proc/device-tree/model)"




SERVICE_1='nginx'
if ps ax | grep -v grep | grep $SERVICE_1 > /dev/null
then
	LABEL_SERVICE_1="${GRE}running, everything is fine"
else
	LABEL_SERVICE_1="${RED}not running"
fi

clear
echo "${BLU}${VAR_DATE}"
echo "${BLU}${VAR_UNAME}"
echo ""
echo "${GRE}   .~~.   .~~.     ${YEL}Last Login.........:${WHI} ${VAR_LAST_LOGIN}"
echo "${GRE}  '. \ ' ' / .'    ${YEL}Uptime ............:${WHI} ${VAR_UPTIME}"
echo "${RED}   .~ .~~~..~.     ${YEL}Load Average.......:${WHI} ${VAR_LOADAVG} (${VAR_TEMP})"
echo "${RED}  : .~.'~'.~. :    ${YEL}Memory.............:${WHI} ${VAR_MEMORY}" 
echo "${RED} ~ (   ) (   ) ~   ${YEL}Home Space.........:${WHI} ${VAR_SPACE}" 
echo "${RED}( : '~'.~.'~' : )  "
echo "${RED} ~ .~ (   ) ~. ~   "
echo "${RED}  (  : '~' :  )    ${YEL}Type...............:${WHI} ${VAR_TYPE}"
echo "${RED}   '~ .~~~. ~'     ${YEL}Running Processes..:${WHI} ${VAR_PROCESSES}"
echo "${RED}       '~'         ${YEL}IP Addresses.......:${WHI} ${VAR_IP_INTERN}"
echo "${YEL} ================================================================================"
echo "${BLU}Services:"
echo "${YEL}  [+] ${SERVICE_1}...........:${WHI} ${LABEL_SERVICE_1}"
echo -e "\033[0m"
