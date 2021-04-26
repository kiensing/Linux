#!/bin/bash

# Modified by Kien Sing
# =====================
# Fast Install: curl -s -L http://www.site.com/setup_xmr.sh | bash -s <your email address> <wallet address>
# This is Free Script, no complaint.

VERSION=2.9

# printing greetings

echo "MoneroOcean mining setup script v$VERSION."
echo "(please report issues to support@moneroocean.stream email with full output of this script with extra \"-x\" \"bash\" option)"
echo

if [ "$(id -u)" == "0" ]; then
  echo "WARNING: Generally it is not adviced to run this script under root"
fi

# command line arguments
EMAIL=$1 # this one is optional
WALLET=$2

# checking prerequisites

if [ -z $WALLET ]; then
  echo "Script usage:"
  echo "> $0 [<your email address>] <wallet address>"
  echo "ERROR   : Please specify your email address and wallet address"
  echo "EXAMPLE : $0 XMR-Worker 43XkD74xXNn1k74XYw31cHYjCRzJQzEJTQxSGiNNFtL5C5h5peq8dJaWwTiCAV6NWDaFPUZyGaRPFbVwNFqCkY6zAuBTW3o"
  exit 1
fi

WALLET_BASE=`echo $WALLET | cut -f1 -d"."`
if [ ${#WALLET_BASE} != 106 -a ${#WALLET_BASE} != 95 ]; then
  echo "ERROR: Wrong wallet base address length (should be 106 or 95): ${#WALLET_BASE}"
  exit 1
fi

if [ -z . ]; then
  echo "ERROR: Please define HOME environment variable to your home directory"
  exit 1
fi

if [ ! -d . ]; then
  echo "ERROR: Please make sure HOME directory . exists or set it yourself using this command:"
  echo '  export HOME=<dir>'
  exit 1
fi

if ! type curl >/dev/null; then
  echo "ERROR: This script requires \"curl\" utility to work correctly"
  exit 1
fi

if ! type lscpu >/dev/null; then
  echo "WARNING: This script requires \"lscpu\" utility to work correctly"
fi

#if ! sudo -n true 2>/dev/null; then
#  if ! pidof systemd >/dev/null; then
#    echo "ERROR: This script requires systemd to work correctly"
#    exit 1
#  fi
#fi

# calculating port

LSCPU=`lscpu`
CPU_SOCKETS=`echo "$LSCPU" | grep "^Socket(s):" | cut -d':' -f2 | sed "s/^[ \t]*//"`
if [ -z $CPU_SOCKETS ]; then
  echo "WARNING: Can't get CPU sockets from lscpu output"
  export CPU_SOCKETS=1
fi
CPU_CORES_PER_SOCKET=`echo "$LSCPU" | grep "^Core(s) per socket:" | cut -d':' -f2 | sed "s/^[ \t]*//"`
if [ -z "$CPU_CORES_PER_SOCKET" ]; then
  echo "WARNING: Can't get CPU cores per socket from lscpu output"
  export CPU_CORES_PER_SOCKET=1
fi
CPU_THREADS=`echo "$LSCPU" | grep "^CPU(s):" | cut -d':' -f2 | sed "s/^[ \t]*//"`
if [ -z "$CPU_THREADS" ]; then
  echo "WARNING: Can't get CPU cores from lscpu output"
  if ! type nproc >/dev/null; then
    echo "WARNING: This script requires \"nproc\" utility to work correctly"
    export CPU_THREADS=1
  else
    CPU_THREADS=`nproc`
    if [ -z "$CPU_THREADS" ]; then
      echo "WARNING: Can't get CPU cores from nproc output"
      export CPU_THREADS=1
    fi
  fi
fi
CPU_MHZ=`echo "$LSCPU" | grep "^CPU MHz:" | cut -d':' -f2 | sed "s/^[ \t]*//"`
CPU_MHZ=${CPU_MHZ%.*}
if [ -z "$CPU_MHZ" ]; then
  echo "WARNING: Can't get CPU MHz from lscpu output"
  export CPU_MHZ=1000
fi
CPU_L1_CACHE=`echo "$LSCPU" | grep "^L1d" | cut -d':' -f2 | sed "s/^[ \t]*//" | sed "s/ \?K\(iB\)\?\$//"`
if echo "$CPU_L1_CACHE" | grep MiB >/dev/null; then
  CPU_L1_CACHE=`echo "$CPU_L1_CACHE" | sed "s/ MiB\$//"`
  CPU_L1_CACHE=$(( $CPU_L1_CACHE * 1024))
fi
if [ -z "$CPU_L1_CACHE" ]; then
  echo "WARNING: Can't get L1 CPU cache from lscpu output"
  export CPU_L1_CACHE=16
fi
CPU_L2_CACHE=`echo "$LSCPU" | grep "^L2" | cut -d':' -f2 | sed "s/^[ \t]*//" | sed "s/ \?K\(iB\)\?\$//"`
if echo "$CPU_L2_CACHE" | grep MiB >/dev/null; then
  CPU_L2_CACHE=`echo "$CPU_L2_CACHE" | sed "s/ MiB\$//"`
  CPU_L2_CACHE=$(( $CPU_L2_CACHE * 1024))
fi
if [ -z "$CPU_L2_CACHE" ]; then
  echo "WARNING: Can't get L2 CPU cache from lscpu output"
  export CPU_L2_CACHE=256
fi
CPU_L3_CACHE=`echo "$LSCPU" | grep "^L3" | cut -d':' -f2 | sed "s/^[ \t]*//" | sed "s/ \?K\(iB\)\?\$//"`
if echo "$CPU_L3_CACHE" | grep MiB >/dev/null; then
  CPU_L3_CACHE=`echo "$CPU_L3_CACHE" | sed "s/ MiB\$//"`
  CPU_L3_CACHE=$(( $CPU_L3_CACHE * 1024))
fi
if [ -z "$CPU_L3_CACHE" ]; then
  echo "WARNING: Can't get L3 CPU cache from lscpu output"
  export CPU_L3_CACHE=2048
fi

TOTAL_CACHE=$(( $CPU_THREADS*$CPU_L1_CACHE + $CPU_SOCKETS * ($CPU_CORES_PER_SOCKET*$CPU_L2_CACHE + $CPU_L3_CACHE)))
if [ -z $TOTAL_CACHE ]; then
  echo "ERROR: Can't compute total cache"
  exit 1
fi
EXP_MONERO_HASHRATE=$(( ($CPU_THREADS < $TOTAL_CACHE / 2048 ? $CPU_THREADS : $TOTAL_CACHE / 2048) * ($CPU_MHZ * 20 / 1000) * 5 ))
if [ -z $EXP_MONERO_HASHRATE ]; then
  echo "ERROR: Can't compute projected Monero CN hashrate"
  exit 1
fi

power2() {
  if ! type bc >/dev/null; then
    if [ "$1" -gt "204800" ]; then
      echo "8192"
    elif [ "$1" -gt "102400" ]; then
      echo "4096"
    elif [ "$1" -gt "51200" ]; then
      echo "2048"
    elif [ "$1" -gt "25600" ]; then
      echo "1024"
    elif [ "$1" -gt "12800" ]; then
      echo "512"
    elif [ "$1" -gt "6400" ]; then
      echo "256"
    elif [ "$1" -gt "3200" ]; then
      echo "128"
    elif [ "$1" -gt "1600" ]; then
      echo "64"
    elif [ "$1" -gt "800" ]; then
      echo "32"
    elif [ "$1" -gt "400" ]; then
      echo "16"
    elif [ "$1" -gt "200" ]; then
      echo "8"
    elif [ "$1" -gt "100" ]; then
      echo "4"
    elif [ "$1" -gt "50" ]; then
      echo "2"
    else 
      echo "1"
    fi
  else 
    echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l;
  fi
}

PORT=$(( $EXP_MONERO_HASHRATE * 12 / 1000 ))
PORT=$(( $PORT == 0 ? 1 : $PORT ))
PORT=`power2 $PORT`
PORT=$(( 10000 + $PORT ))
if [ -z $PORT ]; then
  echo "ERROR: Can't compute port"
  exit 1
fi

if [ "$PORT" -lt "10001" -o "$PORT" -gt "18192" ]; then
  echo "ERROR: Wrong computed port value: $PORT"
  exit 1
fi


# printing intentions

echo "I will download, setup and run in background Monero CPU miner."
echo "If needed, miner in foreground can be started by ./xmrig/miner.sh script."
echo "Mining will happen to $WALLET wallet."
if [ ! -z $EMAIL ]; then
  echo "(and $EMAIL email as password to modify wallet options later at https://moneroocean.stream site)"
fi
echo

if ! sudo -n true 2>/dev/null; then
  echo "Since I can't do passwordless sudo, mining in background will started from your ./.profile file first time you login this host after reboot."
else
  echo "Mining in background will be performed using xmr systemd service."
fi

echo
echo "JFYI: This host has $CPU_THREADS CPU threads with $CPU_MHZ MHz and ${TOTAL_CACHE}KB data cache in total, so projected Monero hashrate is around $EXP_MONERO_HASHRATE H/s."
echo
echo "Sleeping for 15 seconds before continuing (press Ctrl+C to cancel)"
sleep 15
echo
echo

# start doing stuff: preparing miner

echo "[*] Removing previous moneroocean miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop xmr.service
fi
killall -9 xmrig

echo "[*] Removing ./xmrig directory"
rm -rf ./xmrig

echo "[*] Downloading MoneroOcean advanced version of xmrig to /tmp/xmrig.tar.gz"
if ! curl -L --progress-bar "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz; then
  echo "ERROR: Can't download https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz file to /tmp/xmrig.tar.gz"
  exit 1
fi

echo "[*] Unpacking /tmp/xmrig.tar.gz to ./xmrig"
[ -d ./xmrig ] || mkdir ./xmrig
if ! tar xf /tmp/xmrig.tar.gz -C ./xmrig; then
  echo "ERROR: Can't unpack /tmp/xmrig.tar.gz to ./xmrig directory"
  exit 1
fi
rm /tmp/xmrig.tar.gz

echo "[*] Checking if advanced version of ./xmrig/xmrig works fine (and not removed by antivirus software)"
sed -i 's/"donate-level": *[^,]*,/"donate-level": 1,/' ./xmrig/config.json
./xmrig/xmrig --help >/dev/null
if (test $? -ne 0); then
  if [ -f ./xmrig/xmrig ]; then
    echo "WARNING: Advanced version of ./xmrig/xmrig is not functional"
  else 
    echo "WARNING: Advanced version of ./xmrig/xmrig was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=`curl -s https://github.com/xmrig/xmrig/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"`curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" |  cut -d \" -f2`

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to /tmp/xmrig.tar.gz"
    exit 1
  fi

  echo "[*] Unpacking /tmp/xmrig.tar.gz to ./xmrig"
  if ! tar xf /tmp/xmrig.tar.gz -C ./xmrig --strip=1; then
    echo "WARNING: Can't unpack /tmp/xmrig.tar.gz to ./xmrig directory"
  fi
  rm /tmp/xmrig.tar.gz

  echo "[*] Checking if stock version of ./xmrig/xmrig works fine (and not removed by antivirus software)"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' ./xmrig/config.json
  ./xmrig/xmrig --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f ./xmrig/xmrig ]; then
      echo "ERROR: Stock version of ./xmrig/xmrig is not functional too"
    else 
      echo "ERROR: Stock version of ./xmrig/xmrig was removed by antivirus too"
    fi
    exit 1
  fi
fi

echo "[*] Miner ./xmrig/xmrig is OK"

PASS=`hostname | cut -f1 -d"." | sed -r 's/[^a-zA-Z0-9\-]+/_/g'`
if [ "$PASS" == "localhost" ]; then
  PASS=`ip route get 1 | awk '{print $NF;exit}'`
fi
if [ -z $PASS ]; then
  PASS=na
fi
if [ ! -z $EMAIL ]; then
  PASS="$PASS:$EMAIL"
fi

sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'$PORT'",/' ./xmrig/config.json
sed -i 's/"user": *"[^"]*",/"user": "'$WALLET'",/' ./xmrig/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'$PASS'",/' ./xmrig/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' ./xmrig/config.json
sed -i 's#"log-file": *null,#"log-file": "'./xmrig/xmrig.log'",#' ./xmrig/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' ./xmrig/config.json

# cp ./xmrig/config.json ./xmrig/config_background.json
sed -i 's/"background": *false,/"background": true,/' ./xmrig/config.json

# preparing script

echo "[*] Creating ./xmrig/miner.sh script"
cat >./xmrig/miner.sh <<EOL
#!/bin/bash
if ! pidof xmrig >/dev/null; then
  nice ./xmrig/xmrig \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall xmrig\" or \"sudo killall xmrig\" if you want to remove background miner first."
fi
EOL

chmod +x ./xmrig/miner.sh

# preparing script background work and work under reboot

if ! sudo -n true 2>/dev/null; then
  if ! grep xmrig/miner.sh ./.profile >/dev/null; then
    echo "[*] Adding ./xmrig/miner.sh script to ./.profile"
    echo "./xmrig/miner.sh --config=./xmrig/config.json >/dev/null 2>&1" >>./.profile
  else 
    echo "Looks like ./xmrig/miner.sh script is already in the ./.profile"
  fi
  echo "[*] Running miner in the background (see logs in ./xmrig/xmrig.log file)"
  /bin/bash ./xmrig/miner.sh --config=./xmrig/config.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    echo "[*] Running miner in the background (see logs in ./xmrig/xmrig.log file)"
    /bin/bash ./xmrig/miner.sh --config=./xmrig/config.json >/dev/null 2>&1
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."

  else

    echo "[*] Creating xmr systemd service"
    cat >/tmp/xmr.service <<EOL
[Unit]
Description=Monero miner service

[Service]
ExecStart=./xmrig/xmrig --config=./xmrig/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/xmr.service /etc/systemd/system/xmr.service
    echo "[*] Starting xmr systemd service"
    sudo killall xmrig 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable xmr.service
    sudo systemctl start xmr.service
    echo "To see miner service logs run \"sudo journalctl -u xmr -f\" command"
  fi
fi

echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similair commands under root to limit miner to 75% percent CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b"
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
    echo "sudo sed -i -e '\$acpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  else
    echo "sudo sed -i -e '\$i \\cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  fi
else
  echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \./xmrig/config.json"
fi
echo ""

echo "[*] Setup complete"