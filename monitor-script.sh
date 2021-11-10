#!/bin/bash

# Functions
################################################################
log(){
    if [ -f $2]
    then
        echo "[`date "+%Y-%m-%d %H:%M:%s"`] $1" >> $2
    else
        echo "[`date "+%Y-%m-%d %H:%M:%s"`] $1" > $2
    fi
}
################################################################

# Initial definitions
################################################################
execution_date=`date "+%Y-%m-%d"`
execution_hour=`date "+%H:%M"`
date_hour=`date "+%Y%m%d%H%M"`
server_ip=`hostname -i`
hostname=`hostname --fqdn`
instance_id=`ls -l /var/lib/cloud/instances | awk '{print $9}' | tail -1`
access_group=`aws ec2 describe-tags --filters "Name=resource-id,Values=${instance_id}" "Name=tag-key,Values=/Tags/access_group" | grep Value | awk {'print $2'} | sed s'/"//g'`

DIR_OUT=/workspace/Monitoramento/server_${server_ip}/OUT
DIR_LOG=/workspace/Monitoramento/server_${server_ip}/LOGS
LOG_FILE=${DIR_LOG}/monitor_server_${server_ip}_${date_hour}.log
PROCESSES=${DIR_OUT}/monitor_server_processes_${server_ip}_${date_hour}.txt
CONNECTIONS=${DIR_OUT}/monitor_server_connections_${server_ip}_${date_hour}.txt
GENERAL=${DIR_OUT}/monitor_server_general_${server_ip}_${date_hour}.txt
MEMORY_USAGE=${DIR_OUT}/monitor_server_memory_usage_${server_ip}_${date_hour}.txt
USERS=${DIR_OUT}/monitor_server_users_${server_ip}_${date_hour}.txt

if ! [ -d /workspace/Monitoramento ]
then
    mkdir /workspace/Monitoramento
    chown root:g_admin /workspace/Monitoramento
    chmod g+s /workspace/Monitoramento
fi
mkdir -p $DIR_OUT
mkdir -p $DIR_LOG
cd /workspace/Monitoramento/server_${server_ip}

log "Início da execução." $LOG_FILE
################################################################

# Capture of users information
################################################################
log "Capturando informações de usuários." $LOG_FILE

getent group ${access_group} | cut -d":" -f4 | sed 's/,/\n/g' > usrs_list.txt
number_users=`cat usrs_list.txt | wc -l`

echo "EXTERNAL_IP|EXECUTION_DATE|EXECUTION_HOUR|ACCESS_GROUP|ETIMES|USER|PID|COMMAND|ACTIVE_FLAG" > ${PROCESSES}
echo "EXTERNAL_IP|EXECUTION_DATE|EXECUTION_HOUR|ACCESS_GROUP|USER|WORKSPACE_USAGE|HOT_USAGE" > ${USERS}

cat usrs_list.txt | while read usr
do
    rm -rf usrs_aux.txt

    log "Capturando processos do usuário ${usr}." $LOG_FILE

    ps h -o etimes -o "|%u" -o "|%p|" -o "cmd:200" --user=${usr} | tr -s " " | sort -n -k1 | while read i; do echo "$server_ip|$execution_date|$execution_hour|$access_group|`echo $i`" ; done > usrs_aux.txt
    
    if [ ! -s usrs_aux.txt ]
    then
        echo "$server_ip|$execution_date|$execution_hour|$access_group||$usr|||Não" >> ${PROCESSES}
    else
        # Verifica se o processo mais novo está em execução há menos de 604800s (D-7): Se sim, conta como usuário ativo
        if [ `head -1 usrs_aux.txt | cut -d"|" -f5` -le 604800 ]
        then
            cat usrs_aux.txt | while read j
            do
                echo "$j|Sim" >> ${PROCESSES}
            done
        else
            cat usrs_aux.txt | while read j
            do
                echo "$j|Não" >> ${PROCESSES}
            done
        fi
    fi

    log "Ok" $LOG_FILE
    log "Capturando uso de workspace e hot do usuário ${usr}" $LOG_FILE

    echo "$server_ip|$execution_date|$execution_hour|$access_group|$usr|`du -d0 /workspace/$usr | awk '{print $1}'`|`du -d0 /opt/apl/workspace/$usr | awk '{print $1}'`" >> ${USERS}

    log "Ok" $LOG_FILE
done

echo "Fim execucao" >> ${PROCESSES}
echo "Fim execucao" >> ${USERS}

log "Coleta de dados dos usuários encerrada." $LOG_FILE

rm -rf usrs_list.txt
rm -rf usrs_aux.txt
################################################################

# Captura de informações gerais do server
################################################################
# Memória (Tamanho em GB)
log "Capturando informações sobre o uso de memória." $LOG_FILE

total_memory=`free -g | grep Mem | awk '{print $2}'`
in_use_memory=`free -g | grep Mem | awk '{print $3}'`
swap_memory=`free -g | grep Swap | awk '{print $3}'`

log "Ok" $LOG_FILE

top -b -n1 | awk '{print $1,$2,$10}' > top_aux.txt
sed -i '1,7d' top_aux.txt
echo "EXTERNAL_IP|EXECUTION_DATE|EXECUTION_HOUR|PID|USER|MEMORY_USAGE" > ${MEMORY_USAGE}
cat top_aux.txt | grep -v root | sort -k3 -n -r | sed 's/ /|/g' | while read i; do echo "$server_ip|$execution_date|$execution_hour|$i" >> ${MEMORY_USAGE}; done
echo "Fim execucao" >> ${MEMORY_USAGE}

log "Ok" $LOG_FILE

rm -rf top_aux.txt

log "Coletando informações sobre o uso de armazenamento." $LOG_FILE

in_use_workspace=`df /workspace | grep /workspace | awk '{print $3}'`
hot_total=`df /opt/apl | grep /opt/apl | awk '{print $2}'`
in_use_hot=`df /opt/apl | grep /opt/apl | awk '{print $3}'`
free_hot=`df /opt/apl | grep /opt/apl | awk '{print $4}'`
hot_usage=`df /opt/apl | grep /opt/apl | awk '{print $5}' | cut -d"%" -f1`

log "Ok" $LOG_FILE

log "Captura dos servers ativos na máquina" $LOG_FILE

ps aux | grep "/pacotes/anaconda3/bin/jupyterhub" | grep -v grep | grep -v root > active_servers.txt
cat active_servers.txt | cut -d" " -f1 | sort -u > users_active_servers.txt
active_servers_number=`cat users_active_servers.txt | wc -l`

rm -rf active_servers.txt
rm -rf users_active_servers.txt

log "Ok" $LOG_FILE
log "Coletando informações sobre conexões externas." $LOG_FILE

echo "EXTERNAL_IP|EXECUTION_DATE|EXECUTION_HOUR|USER|PID|CONNECTION_PORT|SERVER" > ${CONNECTIONS}

servers_list=("server1" "server2" "server3" "server4")
ports=("1001" "1002" "1003" "1004")
i=1
while [ $i -le ${#servers_list[@]} ]
do
    log "Coletando informações sobre conexões com o servidor ${servers_list[$i-1]}." $LOG_FILE
    netstat -natlp | grep ${ports[$i-1]} | grep ESTABLISHED > aux_${servers_list[$i-1]}.txt
    if [ ! -s aux_${servers_list[$i-1]}.txt ]
    then
        log "Nenhuma conexão com o servidor ${servers_list[$i-1]}." $LOG_FILE
        echo "$server_ip|$execution_date|$execution_hour||||${servers_list[$i-1]}" >> ${CONNECTIONS}
    else
        cat aux_${servers_list[$i-1]}.txt | while read j
        do
            connection_port=`echo $j | awk '{print $4}' | cut -d":" -f2`
            pid=`echo $j | awk '{print $7}' | cut -d"/" -f1`
            user=`ps h -o user --pid=${pid}`
            echo "$server_ip|$execution_date|$execution_hour|$user|$pid|$connection_port|${servers_list[$i-1]}" >> ${CONNECTIONS}
        done
    fi
    log "Ok" $LOG_FILE
    rm -rf aux_${servers_list[$i-1]}.txt
    i=`expr $i + 1`
done

echo "Fim execucao" >> ${CONNECTIONS}

log "Coleta de dados das conexões externas encerrada." $LOG_FILE

log "Alimentando tabela de informações gerais do servidor." $LOG_FILE

echo "EXTERNAL_IP|HOSTNAME|EXECUTION_DATE|EXECUTION_HOUR|IN_USE_WORKSPACE|MEMORY_SIZE|IN_USE_MEMORY|HOT_SIZE|HOT_FREE|ACCESS_GROUP|NUMBER_USERS|NUMBER_ACTIVE_SERVERS" > ${GENERAL}
echo "$server_ip|$execution_date|$execution_hour|$in_use_workspace|${total_memory}|${in_use_memory}|$hot_total|$in_use_hot|$free_hot|$access_group|$number_users|$active_servers_number"

echo "Fim execucao" >> ${GENERAL}

log "Ok" $LOG_FILE
################################################################

# Kill of processes
################################################################
log "Iniciando o kill de processos antigos." $LOG_FILE

KILL_PROCESSES=${DIR_OUT}/monitor_server_kill_processes_${server_ip}_${date_hour}.txt
echo "EXTERNAL_IP|EXECUTION_DATE|EXECUTION_HOUR|ETIMES|USER|PROCESS|PID|MEMORY_USAGE|MEMORY_USAGE_GB" > ${KILL_PROCESSES}

cat ${PROCESSES} | grep -v "|||Não" | while read register
do
    PID=`echo $register | cut -d"|" -f7`
    if [ `echo $register | cut -d"|" -f5` -gt 604800 ]
    then
        MEMORY_PERCENTAGE=`grep "|$PID|" $MEMORY_USAGE | cut -d"|" -f6`
        if [ -z $MEMORY_PERCENTAGE ]
        then
            log "Processo ${PID} encerrado, mas não estava entre os maiores consumos de memória." $LOG_FILE
            kill -9 $PID
        else
            echo "$register|$total_memory|$MEMORY_PERCENTAGE|`echo "($MEMORY_PERCENTAGE * $total_memory)/100" | bc -l`" >> ${KILL_PROCESSES}
            kill -9 $PID
            log "Processo ${PID} encerrado automaticamente." $LOG_FILE
        fi
    else
        log "Processo ${PID} não sofreu kill." $LOG_FILE
    fi
done

echo "Fim execucao" >> ${KILL_PROCESSES}

log "Fim do processo de kill automático." $LOG_FILE
################################################################

# Expurgo de logs
################################################################
log "Iniciando o expurgo de logs de execução." $LOG_FILE
limit_date=`date --date='-7 days' "+%Y%m%d"`
find ${DIR_LOG} -type f -name monitor_server_${server_ip}_${limit_date}*.log -exec rm '{}' \;
log "Fim da execução" $LOG_FILE
################################################################

