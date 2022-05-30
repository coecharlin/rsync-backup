#!/bin/bash

# v1.1.0

# Configuration variables (change as you wish)
src="${1:-pathtosource}"
dst="${2:-pathtotarget}"
remote="${3:-ssh_remote}"
timeout=${timeout:-1800}
partialFolderName="${partialFolderName:-.rsync-partial}"
interactiveMode="${interactiveMode:-no}"
maxLogFiles="${maxLogFiles:-8}"
hostname="${hostname:-`hostname`}"

# Combinate previously defined variables for use (don't touch this)
remoteDst="${remote}:${dst}"
remoteBkp="${remoteDst}/${pathDB}"
partialFolderPath="${dst}/${partialFolderName}"

dateCmd="${dateCmd:-date}"
ownFolderName="${ownFolderName:-.rsync}"
ownFolderPath="${HOME}/${ownFolderName}"

dbFolderName="${dbFolderName:-data}"
dbPath="${ownFolderPath}/${dbFolderName}"
dbName="${dbName:-zabbix-$(${dateCmd} +%Y-%m-%d)-$(${dateCmd} +%HH-%MM).sql}"
dbFile="${dbPath}/${dbName}"

tarName="${tarName:-zabbix-$(${dateCmd} +%Y-%m-%d)-$(${dateCmd} +%HH-%MM).tar.xz}"
tarFile="${dbPath}/${tarName}"

logFolderName="${logFolderName:-log}"
logPath="${ownFolderPath}/${logFolderName}"
logName="${logName:-rsync-$(${dateCmd} +%Y-%m-%d)_$(${dateCmd} +%HH-%MM).log}"
logFile="${logPath}/${logName}"

# Prepare own folder
mkdir -p "${logPath}"
mkdir -p "${dbPath}"
touch "${logFile}"

telegramNotification() {
    if [ "${1}" = 'fail' ]
    then
        telegram-sendMessage.sh "${hostname} - Falha no backup!"
        telegram-sendDocument.sh "${logFile}"
    else
        telegram-sendMessage.sh "${hostname} - Backup finalizado! `ls -sh ${tarFile}`"
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
writeToLog "\\tPara:    ${remoteBkp}"
writeToLog "\\tCom Parametros:"
writeToLog "\\t\\tmaxLogFiles = ${maxLogFiles}"
writeToLog "\\t\\tinteractiveMode = ${interactiveMode}"
writeToLog ""

#Fazendo backup do banco de dados
if cmdMysql="$( ( sudo mysqldump zabbix > "${dbFile}" ) 2>&1 )"
then
    writeToLog "Backup finalizado sem erros!\\n"
    #Compactando o arquivo .sql
    cmdTar="$( ( tar -Jcf "${tarFile}" "${dbFile}" ) 2>&1 )"
    #Deletando arquivo .sql depois de compactado
    writeToLog "Deletando arquivo ${dbFile} e matendo o arquivo .tar.xz"
    rm "${dbFile}"
else
    writeToLog "Backup finalizado com erros: \\n\\t${cmdMysql}"
    telegramNotification "fail"
    #Remove arquivo .sql com erro
    rm "${dbFile}"
    exit
fi

# Prepare ssh parameters for socket connection, reused by following sessions
sshParams=(-o "ControlPath=\"${ownFolderPath}/ssh_conn_socket_%h_%p_%r\"" -o "ControlMaster=auto" \
	-o "ControlPersist=10")

# Prepare rsync transport shell with ssh parameters (escape for proper space handling)
rsyncShellParams=(-e "ssh$(for i in "${sshParams[@]}"; do echo -n " '${i}'"; done)")

batchMode="yes"
if [ "${interactiveMode}" = "yes" ]
then
	batchMode="no"
fi

# Check remote connection and create master socket connection
if ! ssh "${sshParams[@]}" -q -o BatchMode="${batchMode}" -o ConnectTimeout=10 "${remote}" exit
then
	writeToLog "\\n[$(${dateCmd} -Is)] O destino remoto indisponivel"
    telegramNotification "fail"
	exit 1
fi

# Do the backup
writeToLog "\\nIniciando sincronizacao com servidor ${remote} \\n"
if rsync "${rsyncShellParams[@]}" -ahv --progress \
	--partial-dir="${partialFolderName}" \
    --timeout="${timeout}" \
    --log-file="${logFile}" \
    --exclude='*.sql' \
	"${src}/" "${remoteBkp}/"
then
    writeToLog "\\nSincronizacao finalizada!!"
    ls -r "${dbPath}"/*.tar.xz | tail +"${maxLogFiles}" | xargs -r rm
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

# Close master socket connection quietly
ssh "${sshParams[@]}" -q -O exit "${remote}"

telegramNotification "OK"
exit
