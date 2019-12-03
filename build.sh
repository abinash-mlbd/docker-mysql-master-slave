#!/bin/bash

docker-compose down

# Remove data
sudo rm -rf ./master/data/*
sudo rm -rf ./slave1/data/*
sudo rm -rf ./slave2/data/*

docker-compose build
docker-compose up -d

until docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -u root -p$MYSQL_PWD -e ";"'
do
    echo "Waiting for mysql_master database connection..."
    sleep 4
done

# Create slave 1
priv_stmt1='CREATE USER "mydb_slave1_user"@"%";GRANT REPLICATION SLAVE ON *.* TO "mydb_slave1_user"@"%" IDENTIFIED BY "mydb_slave1_pwd"; FLUSH PRIVILEGES;'
docker exec mysql_master sh -c "export MYSQL_PWD=111; mysql -u root -e '$priv_stmt1'"

until docker-compose exec mysql_slave1 sh -c 'export MYSQL_PWD=111; mysql -u root -e ";"'
do
    echo "Waiting for mysql_slave database connection..."
    sleep 4
done

# Create slave 2
priv_stmt2='CREATE USER "mydb_slave2_user"@"%";GRANT REPLICATION SLAVE ON *.* TO "mydb_slave2_user"@"%" IDENTIFIED BY "mydb_slave2_pwd"; FLUSH PRIVILEGES;'
docker exec mysql_master sh -c "export MYSQL_PWD=111; mysql -u root -e '$priv_stmt2'"

until docker-compose exec mysql_slave2 sh -c 'export MYSQL_PWD=111; mysql -u root -e ";"'
do
    echo "Waiting for mysql_slave database connection..."
    sleep 4
done

# Get docker container IP
docker-ip() {
    docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$@"
}

# Get master current log position
MS_STATUS=`docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -u root -p$MYSQL_PWD -e "SHOW MASTER STATUS"'`
CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`

# Changes the parameters that the slave 1 server uses for connecting to the master server
start_slave_stmt1="CHANGE MASTER TO MASTER_HOST='$(docker-ip mysql_master)',MASTER_USER='mydb_slave1_user',MASTER_PASSWORD='mydb_slave1_pwd',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
start_slave1_cmd='export MYSQL_PWD=111; mysql -u root -e "'
start_slave1_cmd+="$start_slave_stmt1"
start_slave1_cmd+='"'
docker exec mysql_slave1 sh -c "$start_slave1_cmd"

# Changes the parameters that the slave 2 server uses for connecting to the master server
start_slave_stmt2="CHANGE MASTER TO MASTER_HOST='$(docker-ip mysql_master)',MASTER_USER='mydb_slave2_user',MASTER_PASSWORD='mydb_slave2_pwd',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
start_slave2_cmd='export MYSQL_PWD=111; mysql -u root -e "'
start_slave2_cmd+="$start_slave_stmt2"
start_slave2_cmd+='"'
docker exec mysql_slave2 sh -c "$start_slave2_cmd"

# View slaves status
docker exec mysql_slave1 sh -c "export MYSQL_PWD=111; mysql -u root -e 'SHOW SLAVE STATUS \G'"
docker exec mysql_slave2 sh -c "export MYSQL_PWD=111; mysql -u root -e 'SHOW SLAVE STATUS \G'"
