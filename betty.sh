#!/bin/bash

#PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Hosted Zone ID
ZONEID="Z1395DSCRDTCOQ"
RECORDSET="betty.phasehosting.io"
LOCKFILE=/tmp/ddns.lock

TTL=10
COMMENT="Auto updating @ `date`"
TYPE="A"

IP=`dig +short myip.opendns.com @resolver1.opendns.com`

function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

update_route53() {
    DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    LOGFILE="$DIR/update-route53.log"
    IPFILE="$DIR/update-route53.ip"

    if ! valid_ip $IP; then
        echo "Invalid IP address: $IP" >> "$LOGFILE"
        exit 1
    fi

    if [ ! -f "$IPFILE" ]
        then
        touch "$IPFILE"
    fi

    if grep -Fxq "$IP" "$IPFILE"; then
        echo "IP is still $IP. Exiting" >> "$LOGFILE"
        exit 0
    else
        echo "IP has changed to $IP" >> "$LOGFILE"
        TMPFILE=$(mktemp /tmp/temporary-file.XXXXXXXX)
        cat > ${TMPFILE} << EOF
        {
          "Comment":"$COMMENT",
          "Changes":[
            {
              "Action":"UPSERT",
              "ResourceRecordSet":{
                "ResourceRecords":[
                  {
                    "Value":"$IP"
                  }
                ],
                "Name":"$RECORDSET",
                "Type":"$TYPE",
                "TTL":$TTL
              }
            }
          ]
        }
    EOF

        # Update the Hosted Zone record
        aws route53 change-resource-record-sets \
            --hosted-zone-id $ZONEID \
            --change-batch file://"$TMPFILE" >> "$LOGFILE"
        echo "" >> "$LOGFILE"

        # Clean up
        rm $TMPFILE
    fi

    echo "$IP" > "$IPFILE"
}

if ( set -o noclobber; echo "$$" > "$LOCKFILE") 2> /dev/null;
then
    trap 'rm -f "$LOCKFILE"; exit $?' INT TERM EXIT

    while true; do
        update_route53;
        sleep 10
    done

    rm -f "$LOCKFILE"
    trap - INT TERM EXIT
else
    out "Already running"
    exit 1
fi
