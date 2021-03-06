#!/bin/bash

# AVOID the same network zone/range as the SFTP receiver service
# for Wekan & OrientDB web UI
FRONTEND_IP=127.0.0.1 
# for Wekan only
FRONTEND_PORT=8080

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Get the first IP address
    IPADDR=$(hostname -I | awk '{print $1}')
    echo "Using $IPADDR"
    echo "installing dependencies..."
    sudo apt-get update  
    sudo apt install git zip bindfs curl tmux moreutils net-tools python -y 
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable edge"
    sudo apt-get update
    sudo apt-cache policy docker-ce
    sudo apt-get install -y docker-ce docker-compose
    # add current user to docker group so as to avoid sudo docker-compose but doesn't seem to work
    # sudo usermod -aG docker $USER         
    echo "starting docker service..."
    sudo /etc/init.d/docker start
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # Better to get user to install, don't want to be liable for anything here
    command -v docker >/dev/null 2>&1 || { echo >&2 "Please install docker.  Aborting..."; exit 1; }
    command -v brew >/dev/null 2>&1 || { echo >&2 "Please install brew.  Aborting..."; exit 1; }
    IPADDR=$(ipconfig getifaddr en0)
    echo "Using $IPADDR"    
    echo "install all the necessary dependencies for macOS..."
    brew list bindfs || brew install bindfs
    # otherwise orientdb 3.0.3X & 3.1.X onwards will fail to start
    # see https://github.com/orientechnologies/orientdb/issues/9278
    sed -i 's/MORE_OPTIONS=""/MORE_OPTIONS="-Dstorage.disk.useNativeOsAPI=false"/g' orientdb/entrypoint
fi

echo "UID=$UID" > .env
echo "FRONTEND_IP=$FRONTEND_IP" >> .env
echo "FRONTEND_PORT=$FRONTEND_PORT" >> .env
echo "C2_PATH=./backend/sftp/response/" >> .env
echo "SFTP_HOST=$IPADDR" >> .env

# sftp/scripts/generateSFTPconf.sh will read this file
# to generate sftpconf.zip, which is needed at client-side
echo $IPADDR > ./backend/sftp/scripts/IPaddresses

if [ -f "/usr/bin/bindfs" ]; then    
    echo "Mounting write-only uploads directory..."
    # this `uploads` directory is mounted to onewaysftp container...
    # --delete-deny  not available in Ubuntu 16
    if ! bindfs |grep delete-deny > /dev/null 2>&1; then
        sudo bindfs --create-for-user=$USER --force-group=$GROUPS --create-with-perms=g+w,o-rw -p o+w -o nonempty $PWD/backend/sftp/tobeinserted $PWD/backend/sftp/uploads
    else
        sudo bindfs --delete-deny --create-for-user=$USER --force-group=$GROUPS --create-with-perms=g+w,o-rw -p o+w -o nonempty $PWD/backend/sftp/tobeinserted $PWD/backend/sftp/uploads
    fi
    # using docker to mount sftp/response directory as read-only
    echo "UPLOAD_PATH=./backend/sftp/tobeinserted" >> .env
else
    # no bindfs, use read-write directory directly
    echo "UPLOAD_PATH=./backend/sftp/uploads" >> .env
fi

touch orientdb/orient.pid
# docker-compose will take care of the rest of the services
sudo docker-compose up -d

# this turns the script to use current user & group instead of variables
# the script is then usable from /etc/rc.local
EOF=EOF_$RANDOM; eval echo "\"$(cat <<$EOF
$(< manage/mountUploads.sh)
$EOF
)\"" > manage/mountUploads.sh

# host sftpconf.zip & install.ps1 for client-side
export IPADDR
./hostclientinstall.sh
