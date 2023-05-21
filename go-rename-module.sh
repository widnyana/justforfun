#!/usr/bin/env bash
set -euo pipefail

SCRIPTNAME=$(basename "$0")
COLOR_GRAY="\033[1;38;5;243m"
COLOR_BLUE="\033[1;34m"
COLOR_GREEN="\033[1;32m"
COLOR_RED="\033[1;31m"
COLOR_NONE="\033[0m"

info() {
    echo -e "${COLOR_GRAY}${1}${COLOR_NONE}"
}

success() {
    echo -e "${COLOR_GREEN}${1}${COLOR_NONE}"
}

error() {
    echo -e "${COLOR_RED}${1}${COLOR_NONE}"
}

help() {
    __usage="
${COLOR_GREEN}                                                Golang Package renamer
 ____________________________________________________|_._._._._._._._,
 \___________________________________________________|_|_|_|_|_|_|_|_|
                                                     !          ${COLOR_NONE}

${COLOR_GREEN}Usage:${COLOR_NONE}
${SCRIPTNAME} \"<old package name>\" \"<new package name>\"

${COLOR_GREEN}Example:${COLOR_NONE}
1) ${SCRIPTNAME} \"lame.tld/name\"\t\t\t\"cool.tld/name\"
2) ${SCRIPTNAME} \"lame.tld/package/name\"\t\t\"cool.tld/package/name\"
3) ${SCRIPTNAME} \"lame.tld/package/name\"\t\t\"cool.tld/package-name\"

Got bugs? solve it on your own. (✿◠‿◠)
"

echo -en "$__usage"
}

#: perform rename
rename() {
    OLD_MODULE_NAME="${1}"
    NEW_MODULE_NAME="${2}"
    
    info "[>] Modifying go.mod"
    go mod edit -module "${NEW_MODULE_NAME}"

    info "[>] renaming all imported module"
    
    find . -type f -name '*.go' -print \
        -exec sed -i -e "s,${OLD_MODULE_NAME},${NEW_MODULE_NAME},g" {} \;

    success "[+] done!"
}


check_deps() {
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        error "[!] Your OS is not Linux, Too bad you can not use this script."
        error "[!] Exitting..."
        exit 1
    fi
    
    if [[ ! -x "$(command -v sed)" ]]; then
        error "[!] could not find 'sed' binary! Make sure you have it on your \$PATH"
        error "[!] Exitting..."
        exit 1
    fi
}


check_deps

if [[ $# -lt 2 ]]; then
    help
    exit 1
else
    rename "${1}" "${2}"
fi
