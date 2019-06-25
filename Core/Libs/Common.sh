#!/usr/bin/env bash
# Header_start
#################################################################################
#                                                                               #
#       Script de creation de Boot Alterné sur des serveurs redhat              #
# ----------------------------------------------------------------------------- #
#       Author: Alfred TCHONDJO - Iriven France                                 #
#       Date: 2019-05-02                                                        #
# ----------------------------------------------------------------------------- #
#       Revisions                                                               #
#                                                                               #
#       G1R0C0 :        Creation du script le 02/05/2019 (AT)                   #
#################################################################################
# Header_end
# set -x
#-------------------------------------------------------------------
#               DECLARATION DES VARIABLES
#-------------------------------------------------------------------
function isTrue()
{    
   local mode="$1"
   case "${mode}" in
      [Tt][rR][uU][eE]*|1|[yY]|[yY][eE][sS]*) return 0 ;;
      *) return 1 ;;
   esac
}

function escapeSlashes()
{
  local item="$1"
   echo "${item}" | sed 's/\//\\\//g' 
}

function ValidateConfigSyntax()
{
   local filepath="$1"
   local syntax="(^\s*#|^\s*$|^\s*[a-zA-Z_]+=[^',;&]*$)"
   require "${filepath}"
   if egrep -q -v "${syntax}" "${filepath}"; then
      printf " \e[31m %s \n\e[0m" "Erreur de configuration." >&2
      printf " \e[31m %s \n\e[0m" "Cette ligne du fichier de configuration contient des caractères inapropriés"
      egrep -vn "${syntax}" "${filepath}"
      exit 5
   fi
}

function getRedhatVersion()
{
  #${PERL} -pe 's/(.*release.*)\s(\d).+/$2/' /etc/redhat-release
  awk '{ match($0, /([0-9]+)/, arr); if(arr[1] != "") print arr[1] }' < /etc/redhat-release
}

function getRedhatRelease()
{
  
  awk '{ match($0, /([0-9]+.[0-9]+)/, arr); if(arr[1] != "") print arr[1] }' < /etc/redhat-release
  #${PERL} -pe 's/(.*release.*)\s(\d.\d).+/$2/' /etc/redhat-release
}

function writeLog(){
   [ $# -lt 1 -o -z "$1" ] && printf "Usage:  [string MSG] [string LEVEL]" && exit 1
   local msg=$1 level=${2:-error}
   case ${level} in
      info) msg="INFO: ${msg}";logger -p local7.info -t bootalt ${msg} ;;
      *) msg="ERROR: ${msg}";logger -p local7.err -t bootalt ${msg} ;;
   esac
   local EVNTDATE=$(date +'%F %X')
   if [ "${level}" == "error" ] 
   then
      printf " \e[31m %s \n\e[0m" "${EVNTDATE}: $msg" 1>&2
      exit -1
   else
      printf " %s \n" "${EVNTDATE}: $msg" 1>&2
   fi
}

function numberCompare(){
   local expression1=$1 operator=$2 expression2=$3
   case $operator in
      ">"|">="|"<"|"<="|"=");;
      *)operator=">";;
   esac
   local result=$(echo "${expression1} ${operator} ${expression2}"| bc -q 2>/dev/null)
   case $result in
      0|1);;
      *)result=0;;
   esac
   local stat=$((result == 0))
   return $stat
}

function trim() {
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   
    echo -n "$var"
}

function isNumeric() {  
    local input="$1"
    case "$input" in
    *[!0-9,]*|*[!0-9]*|,*|'') return 1;;
    *) return 0;;
    esac          
  }

function removeTextBetweenMarkers() {
    local start="$1"
    local end="$2"
    local filepath="$3"   
    local cachefile="/tmp/textreplace.txt"
    [ -f "${filepath}" ] || writeLog "Le fichier de Configuration du grub est introuvable"
    startingLine=$(${GREP} -n "${start}" ${filepath}| ${SED} 's/\(.*\):.*/\1/g')
    endingLine=$(${GREP} -n "${end}" ${filepath} | ${SED} 's/\(.*\):.*/\1/g')
    if [ "${startingLine}" -lt "${endingLine}" ] 
    then
        ${ECHO} "" > ${cachefile}
        ${CAT} <(${HEAD} -n $(${EXPR} $startingLine - 1) ${filepath}) ${cachefile} <(${TAIL} -n +$(${EXPR} $endingLine + 1) ${filepath}) >temp
        ${MV} temp ${filepath}
        ${RM} -f ${cachefile}
    fi
}
