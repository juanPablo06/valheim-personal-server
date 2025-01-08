#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

sudo apt update && sudo apt upgrade -y 

# Detect the NVMe device
DEVICE_NAME=$(lsblk -o NAME,SIZE | grep 8G | awk '{print $1}')
DEVICE_PATH="/dev/$DEVICE_NAME"

# Format and mount the EBS volume if not already formatted
if ! blkid $DEVICE_PATH; then
  sudo mkfs.ext4 $DEVICE_PATH
fi

sudo mkdir -p /usr/games/serverconfig
sudo mount $DEVICE_PATH /usr/games/serverconfig
echo "$DEVICE_PATH /usr/games/serverconfig ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

sudo apt install unzip apt-transport-https ca-certificates curl gnupg lsb-release -y

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Set up the Docker repository
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

# Install Docker Engine
sudo apt install docker-ce docker-ce-cli containerd.io -y

# Install AWS CLI
sudo curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo unzip awscliv2.zip
sudo ./aws/install

# Create random string for password
VHPW=$(echo $RANDOM | md5sum | head -c 20)
PARAMNAME=mcValheimPW

# Store password in SSM in the specified region
aws ssm put-parameter --name $PARAMNAME --value $VHPW --type "SecureString" --region sa-east-1 --overwrite

# Download world files from S3
sudo mkdir -p /usr/games/serverconfig/valheim/saves/worlds
sudo chown -R ubuntu:ubuntu /usr/games/serverconfig/valheim/saves/worlds

if [ ! -f /usr/games/serverconfig/valheim/saves/worlds/Aurinosgard.db ]; then
  aws s3 cp s3://terraform-backend-ue1/valheim/worlds/Aurinosgard.db /usr/games/serverconfig/valheim/saves/worlds/
fi

if [ ! -f /usr/games/serverconfig/valheim/saves/worlds/Aurinosgard.fwl ]; then
  aws s3 cp s3://terraform-backend-ue1/valheim/worlds/Aurinosgard.fwl /usr/games/serverconfig/valheim/saves/worlds/
fi

# Install Docker Compose
sudo apt install docker-compose -y
sudo usermod -aG docker $USER
sudo mkdir -p /usr/games/serverconfig
cd /usr/games/serverconfig
sudo bash -c 'echo "version: \"3\"
services:
  valheim:
    image: mbround18/valheim:latest
    ports:
      - 2456:2456/udp
      - 2457:2457/udp
      - 2458:2458/udp
    environment:
      - PORT=2456
      - NAME=\"Aurinosgard\"
      - WORLD=\"Aurinosgard\"
      - PASSWORD=\"'"$VHPW"'\"
      - TZ=America/Sao_Paulo
      - PUBLIC=0
      - AUTO_UPDATE=1
      - AUTO_UPDATE_SCHEDULE=\"0 1 * * *\"
      - AUTO_BACKUP=1
      - AUTO_BACKUP_SCHEDULE=\"*/15 * * * *\"
      - AUTO_BACKUP_REMOVE_OLD=1
      - AUTO_BACKUP_DAYS_TO_LIVE=3
      - AUTO_BACKUP_ON_UPDATE=1
      - AUTO_BACKUP_ON_SHUTDOWN=1
    volumes:
      - ./valheim/saves:/home/steam/.config/unity3d/IronGate/Valheim
      - ./valheim/server:/home/steam/valheim
      - ./valheim/backups:/home/steam/backups" > docker-compose.yml'
sudo bash -c 'echo "@reboot root (cd /usr/games/serverconfig/ && docker-compose up)" > /etc/cron.d/gameserver'

# Create the backup script
sudo bash -c 'cat <<EOF > /home/ubuntu/backup_worlds.sh
#!/bin/bash
# Define the local and S3 paths
LOCAL_PATH="/usr/games/serverconfig/valheim/saves/worlds_local"
S3_BUCKET="s3://terraform-backend-ue1/valheim/worlds"

# Copy the .db and .fwl files to S3, overwriting the existing ones
aws s3 cp \$LOCAL_PATH/Aurinosgard.db \$S3_BUCKET/Aurinosgard.db --region sa-east-1 --acl private
aws s3 cp \$LOCAL_PATH/Aurinosgard.fwl \$S3_BUCKET/Aurinosgard.fwl --region sa-east-1 --acl private
EOF'

# Make the backup script executable
sudo chmod +x /home/ubuntu/backup_worlds.sh

# Add a cron job to run the backup script every 15 minutes
sudo bash -c 'echo "*/15 * * * * /home/ubuntu/backup_worlds.sh" >> /etc/crontab'

sudo docker-compose up