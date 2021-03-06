#!/bin/sh

SERVERNAME="beispiel"

hood="hoodeintragen"
project="fff"
port=10004

SERVERNAME="$SERVERNAME.$hood"

hostname=$SERVERNAME

if [ ! -d /etc/fastd ]
then
        mkdir /etc/fastd
fi

if [ ! -d /etc/fastd/$project.$hood ]
then
        mkdir /etc/fastd/$project.$hood
        mkdir /etc/fastd/$project.$hood/peers
        
        #fastd config
        (
          echo "# Log warnings and errors to stderr"
          echo "log level error;"
          echo "# Log everything to a log file"
          echo "log to syslog as \"${project}${hood}\" level info;"
          echo "# Set the interface name"
          echo "interface \"${project}${hood}VPN\";"
          echo "# Support xsalsa20 and aes128 encryption methods, prefer xsalsa20"
          echo "#method \"xsalsa20-poly1305\";"
          echo "#method \"aes128-gcm\";"
          echo "method \"null\";"
          echo "# Bind to a fixed port, IPv4 only"
          echo "bind any:${port};"
          echo "# Secret key generated by \"fastd --generate-key\""
          echo "secret \"$(fastd --generate-key | grep -i Secret | awk '{print $2}')\";"                                                                      
          echo "# Set the interface MTU for TAP mode with xsalsa20/aes128 over IPv4 with a base MTU of 1492 (PPPoE)"                                          
          echo "# (see MTU selection documentation)"                                                                                                          
          echo "mtu 1426;"                                                                                                                                    
          echo "on up \"/etc/fastd/${project}.${hood}/up.sh\";"                                                                                               
          echo "on post-down \"/etc/fastd/${project}.${hood}/down.sh\";"                                                                                      
          echo "# Include peers from the directory 'peers'"                                                                                                   
          echo "include peers from \"/etc/fastd/${project}.${hood}/peers\";"                                                                                  
          echo "secure handshakes no;"
        ) >> "/etc/fastd/$project.$hood/$project.$hood.conf"
        
        #fastd-up
        (
          echo "#!/bin/sh"
          echo "/sbin/ifdown \$INTERFACE"
        ) >> /etc/fastd/$project.$hood/down.sh

        chmod +x /etc/fastd/$project.$hood/down.sh

        (
          echo "#!/bin/sh"
          echo "/sbin/ifup \$INTERFACE" >> /etc/fastd/$project.$hood/up.sh
        ) >> /etc/fastd/$project.$hood/up.sh
        chmod +x /etc/fastd/$project.$hood/up.sh
fi

pubkey=$(fastd -c /etc/fastd/$project.$hood/$project.$hood.conf --show-key --machine-readable)
port=$(grep ^bind /etc/fastd/$project.$hood/$project.$hood.conf | cut -d: -f2 | cut -d\; -f1)

# fire up
if [ "$(/sbin/ifconfig -a | grep -i ethernet | grep ${project}${hood}VPN)" = "" ]
then
  /bin/rm /var/run/fastd.$project.$hood.pid
  fastd -c /etc/fastd/$project.$hood/$project.$hood.conf -d --pid-file /var/run/fastd.$project.$hood.pid
fi

# register
wget -T15 -q "http://keyserver.freifunk-franken.de/${project}/?name=$hostname&port=$port&key=$pubkey" -O /tmp/fastd_${project}.${hood}_output 
if [ "$?" != "0" ]
then
        echo "Update failed"
        echo "Exiting, no clean up, no refresh"
        exit
fi

touch /tmp/fastd_${project}.${hood}_starting

filenames=$(cat /tmp/fastd_${project}.${hood}_output| grep ^#### | sed -e 's/^####//' | sed -e 's/.conf//g')
for file in $filenames
do
  grep -A100 ^####$file.conf$ /tmp/fastd_${project}.${hood}_output | grep -v ^####$file.conf$ | grep -m1 ^### -B100 | grep -v ^### | sed 's/ float;/;/g' > "/etc/fastd/$project.$hood/peers/$file"
  echo 'float yes;' >> "/etc/fastd/$project.$hood/peers/$file"
done

#find old peers
OLD=$(find /etc/fastd/$project.$hood/peers/ -exec test -f '{}' -a /tmp/fastd_${project}.${hood}_starting -nt '{}' \; -print)

if [ -n "${OLD}" ] ; then
  echo "Lösche alte:"
  echo $OLD
  
  find /etc/fastd/$project.$hood/peers/ -exec test -f '{}' -a /tmp/fastd_${project}.${hood}_starting -nt '{}' \; -print | xargs /bin/rm /tmp/fastd_${project}.${hood}_starting
fi

#reload
kill -HUP "$(cat /var/run/fastd.$project.$hood.pid)"

exit 0
