#!/bin/bash

# Change Wine file associations in native OS
# Andrey Kuznetsov, 2023.09.04
# Telegram: https://t.me/akmsg


# Get variables
WINEPRFX="${HOME}/.wine"
NEED_EXT="bmp gif png jpg jpeg svg pdf tif tiff rtf doc docx xls xlsx odt ods vsd zip rar 7z eml"
output="REGEDIT4"$'\n'$'\n'
# end variables

# Check
if [ ! -d "${WINEPRFX}" ]; then
    echo "Не существует такого WINE префикса ${WINEPRFX}"
    exit
fi

# Create backup reg
cp -f "${WINEPRFX}/system.reg" "${WINEPRFX}/system.reg.bak"
cp -f "${WINEPRFX}/user.reg" "${WINEPRFX}/user.reg.bak"
cp -f "${WINEPRFX}/userdef.reg" "${WINEPRFX}/userdef.reg.bak"

# Create script
mkdir -p ${HOME}/bin/

cat > "${HOME}/bin/run_linux_app" <<-'_RUN_LINUX_APP_SCRIPT'
#!/bin/bash
xdg-open "$(winepath --unix "$1")"
_RUN_LINUX_APP_SCRIPT

chmod a+x "${HOME}/bin/run_linux_app"
winpath2script=$(winepath --windows "${HOME}/bin/run_linux_app")
#echo ${winpath2script}
command="${winpath2script//\\/\\\\} \\\"%1\\\""
#echo ${command}

# Create reg file
for ext in ${NEED_EXT}; do
    #echo ${ext}
    output+="[HKEY_CLASSES_ROOT\\.${ext}]"$'\n'
    output+="@=\"UniversalHandlerW2L\""$'\n\n'
done

output+="[HKEY_CLASSES_ROOT\\UniversalHandlerW2L\\shell\\open\\command]"$'\n'
output+="@=\"${command}\""$'\n'
output+=$'\n'

printf '%s' "$output" > "${HOME}/bin/dump.reg"

env WINEPREFIX="${WINEPRFX}" wine regedit "${HOME}/bin/dump.reg"
rm -f "${HOME}/bin/dump.reg"

exit 0
