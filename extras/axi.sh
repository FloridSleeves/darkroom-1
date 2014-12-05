cd out;
INPUT_FILE=$(terra ../../extractMetadata.t $1.axi.metadata.lua inputFile1)
# if we write to /home/root the drive may fill up and silently corrupt files
WRITE_PATH=/var/volatile
ADDR=192.168.2.2
echo $INPUT_FILE
rm /home/jhegarty/.ssh/known_hosts
terra ../../pad.t $1 $1.axi.metadata.lua
# sshpass -p 'root'
scp ../../helloaxi/processimage $1.axi.bit $1.$INPUT_FILE root@192.168.2.2:$WRITE_PATH
ssh root@$ADDR "cat $WRITE_PATH/$1.axi.bit > /dev/xdevcfg"
ssh root@192.168.2.2 "$WRITE_PATH/processimage 805339136 $WRITE_PATH/$1.$INPUT_FILE $WRITE_PATH/out.raw"
scp root@192.168.2.2:$WRITE_PATH/out.raw $1.axi.raw
ssh root@192.168.2.2 "rm $WRITE_PATH/processimage $WRITE_PATH/$1.$INPUT_FILE $WRITE_PATH/out.raw $WRITE_PATH/$1.axi.bit"
terra ../../raw2bmp.t $1.axi.raw $1.axi.bmp $1.axi.metadata.lua
