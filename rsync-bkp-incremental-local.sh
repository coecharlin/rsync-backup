#!/bin/bash

# v1.1.0

# Configuration variables (change as you wish)
src="${1:-pathtosource}"
dst="${2:-pathtotarget}"
timeout=${timeout:-1800}
partialFolderName="${partialFolderName:-.rsync-partial}"
interactiveMode="${interactiveMode:-no}"
maxLogFiles="${maxLogFiles:-8}"
hostname="${hostname:-`hostname`}"

# Combinate previously defined variables for use (don't touch this)
localBkp="${dst}"
partialFolderPath="${dst}/${partialFolderName}"

dateCmd="${dateCmd:-date}"
ownFolderName="${ownFolderName:-.rsync}"
ownFolderPath="${HOME}/${ownFolderName}"

dbFolderName="${dbFolderName:-data}"
dbPath="${ownFolderPath}/${dbFolderName}"
dbName="${dbName:-zabbix-$(${dateCmd} +%Y-%m-%d)-$(${dateCmd} +%HH-%MM).sql}"
dbFile="${dbPath}/${dbName}"

logFolderName="${logFolderName:-log}"
logPath="${ownFolderPath}/${logFolderName}"
logName="${logName:-rsync-$(${dateCmd} +%Y-%m-%d)_$(${dateCmd} +%HH-%MM).log}"
logFile="${logPath}/${logName}"

# Prepare own folder
mkdir -p "${logPath}"
touch "${logFile}"

telegramNotification() {
    if [ "${1}" = 'fail' ]
    then
        telegram-sendMessage.sh "${hostname} - Falha no backup!"
        telegram-sendDocument.sh "${logFile}"
    else
        telegram-sendMessage.sh "${hostname} - Backup finalizado!"
    fi
}
writeToLog() {
	echo -e "${1}" | tee -a "${logFile}"
}

writeToLog "********************************"
writeToLog "*                              *"
writeToLog "*   rsync-incremental-backup   *"
writeToLog "*                              *"
writeToLog "********************************"
writeToLog "\\n[$(${dateCmd} -Is)] Iniciando backup:"
writeToLog "\\tDe:      ${src}"
writeToLog "\\tPara:    ${localBkp}"
writeToLog "\\tCom Parametros:"
writeToLog "\\t\\tmaxLogFiles = ${maxLogFiles}"
writeToLog "\\t\\tinteractiveMode = ${interactiveMode}"
writeToLog ""

# Do the backup
writeToLog "\\nIniciando sincronizacao com servidor ${remote} \\n"
if rsync "${rsyncShellParams[@]}" -ahv --progress \
	--partial-dir="${partialFolderName}" \
    --timeout="${timeout}" \
    --log-file="${logFile}" \
	"${src}/" "${localBkp}/"
then
    writeToLog "\\nSincronizacao finalizada!!"
    chown -R charlesandrade:santana "${localBkp}"
    chmod 
    #limpando pasta de logs
    if [ "${maxLogFiles}" -ne 0 ]
    then
    ls -r "${logPath}"/*.log | tail +"${maxLogFiles}" | xargs -r rm
    else
    writeToLog "Falha na exclusao dos arquivos de logs"
    telegramNotification "fail"
    fi
else
    writeToLog "\\nFalha ao sincronizar o backup com servidor ${remote}"
    telegramNotification "fail"
    exit
fi

telegramNotification "OK"
exit
