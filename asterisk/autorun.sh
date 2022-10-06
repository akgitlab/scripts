HOST=10.1.1.29
MYSQLUSERNAME=qstatsUser
MYSQLPASSWORD=qstatsPassw0rd
MYSQLDATABASE=qstats

# Returns true once mysql can connect.
mysql_ready() {
        mysqladmin ping --host=$HOST --user=$MYSQLUSER --password=$MYSQLPASSWORD > /dev/null 2>&1
}

while !(mysql_ready)
do
        sleep 3
done

screen -dmS tailqueuelog perl /usr/local/parselog/tailqueuelog -u $MYSQLUSERNAME -p $MYSQLPASSWORD -d $MYSQLDATABASE -l /var/log/asterisk/queue_log
