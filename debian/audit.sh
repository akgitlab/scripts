# User shell activity audit
PREF="audit"
RUSER=$(who | awk '{print $1}')
IP=$(who am i | awk '{ print $5 }' | sed 's/(//g' | sed 's/)//g')
function h2log {
  declare CMD
  declare _PWD
    CMD=$(history 1)
    CMD=$(echo $CMD | awk '{print substr($0,length($1)+2)}')
    _PWD=$(pwd)
      if [ "$CMD" != "$pCMD" ]; then
        logger -p local7.notice -t bash -- "user \"${RUSER}\" from source ip \"${IP}\" being in the directory \"${_PWD}\" executed on behalf \
        of \"${USER}\" the shell command: \"${CMD}\""
      fi
    pCMD=$CMD
}
trap h2log DEBUG || EXIT
