#!/usr/bin/env bash
# Header_start
#################################################################################
#                                                                               #
#       Fichier de Configuration du Script de creation du boot alterné        #
# ----------------------------------------------------------------------------- #
#       Author: Alfred TCHONDJO - Iriven France                                 #
#       Date: 2018-05-14                                                        #
# ----------------------------------------------------------------------------- #
#       Revisions                                                               #
#                                                                               #
#       G1R0C0 :        Creation du script le 14/05/2019 (AT)                   #
#       G1R0C1 :        Update - détection auto des FS le 30/09/2019 (AT)       #
#                                                                               #
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

function getOSVersion()
{
  local OSVersion=$(cat /etc/*-release | sed 's/\"//g' | awk -F= '/^VERSION=/ { print $NF;}'|awk '{ print $1;}'| awk -F. '{ print $1;}')
  ${ECHO} "${OSVersion}"
}

function getOSRelease()
{
  local OSRelease=$(cat /etc/*-release | awk '{ match($0, /([0-9]+.[0-9]+)/, arr); if(arr[1] != "") print arr[1] }'|head -n 1)
  ${ECHO} "${OSRelease}"
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

function alternateEntityName(){
  local entityname="$1"
  local suffix=${2:-_alt}
  isAlternate "${entityname}" "${suffix}" && output=$(${ECHO} "${entityname}" | ${SED} -e "s/^\(.*\)${suffix}$/\1/") || output="${entityname}${suffix}"
  ${ECHO} "${output}"
}

function isAlternate(){
  local entityname="$1"
  local suffix=${2:-_alt}
  case "${entityname}" in
    *${suffix}) return 0;;
    *) return 1;;
  esac
}

function getCurrentOSDevice(){
    local rootFS=$(${DF} -P / | ${TAIL} -1 | ${AWK} '{ print $1 }' | ${SED} "s/\/dev\(\/[^\/]*\/*\)\([^-]*\)\([-\/]\)\([^-]*\)$/\/dev\/\\2\/\\4/")
    ${DF} -P / | ${TAIL} -1 | ${AWK} '{ print $1 }' | ${GREP} "\/dev\(\/[^\/]*\/*\)\([^-]*\)\([-\/]\)\([^-]*\)$" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        local rootvg=$(${DF} -P / | ${TAIL} -1 | ${AWK} '{ print $1 }' | ${SED} "s/\/dev\(\/[^\/]*\/*\)\([^-]*\)\([-\/]\)\([^-]*\)$/\\2/" )
        rootFS=$(${PVS} 2>/dev/null| ${GREP} "[[:space:]]${rootvg}[[:space:]]" | ${AWK} '{ print $1 }')
    fi
    ${ECHO} ${rootFS} | ${GREP} -E 'c[[:digit:]]+d[[:digit:]]+p[[:digit:]]+|mpath.*p[[:digit:]]+' -q
    if [ $? -eq 0 ]; then
        local SystemDisk=$(${ECHO} ${rootFS} | ${SED} 's/p[[:digit:]]\+$//')
    else
        local SystemDisk=$(${ECHO} ${rootFS} | ${SED} 's/[[:digit:]]\+$//')
    fi
    ${ECHO} ${SystemDisk}
}

function humanReadableSize(){
  local inputSize="${1}"
  ${ECHO} ${inputSize}| ${AWK} '{ split( "KB MB GB" , v ); s=1; while( $1>1024 ){ $1/=1024; s++ } print int($1) v[s] }'
}