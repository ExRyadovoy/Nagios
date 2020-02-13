#!/usr/bin/env bash
#
# Check MySQL plugin for Nagios
#
# Usage: check_mysql.sh [-u user] [-p password] [-f MySQL defaults-file path]
#   -u, --user                  MySQL user name
#   -p, --port                  MySQL user password
#   -f, --defaults-file         MySQL defaults-file path
#   -w, --warning WARNING       Warning value (percent)
#   -c, --critical CRITICAL     Critical value (percent)
#   -h, --help                  Display this screen
#
# (c) 2014, Benjamin Dos Santos <benjamin.dossantos@gmail.com>
# https://github.com/bdossantos/nagios-plugins
# (c) 2020. Stan Kliuiev <demonoid.wolf@gmail.com> nksupport.com

while [[ -n "$1" ]]; do
  case $1 in
    --user | -u)
      user=$2
      shift
      ;;
    --password | -p)
      password=$2
      shift
      ;;
    --defaults-file | -f)
      default_files=$2
      shift
      ;;
    --warning | -w)
      warning=$2
      shift
      ;;
    --critical | -c)
      critical=$2
      shift
      ;;
    --help | -h)
      sed -n '2,10p' "$0" | tr -d '#'
      exit 3
      ;;
    *)
      echo "Unknown argument: $1"
      exec "$0" --help
      exit 3
      ;;
  esac
  shift
done

if ! hash mysqladmin &>/dev/null; then
  echo "CRITICAL - mysqladmin command not found"
  exit 2
fi

options=()
warning=${warning:=90}
critical=${critical:=95}

if [[ $warning -ge $critical ]]; then
  echo "UNKNOWN - warning ($warning) can't be greater than critical ($critical)"
  exit 3
fi

if [[ ! -z $user ]]; then
  options=("${options[@]}" "-u${user}")
fi

if [[ ! -z $password ]]; then
  options=("${options[@]}" "-p${password}")
fi

if [[ ! -z $default_files ]]; then
  options=("${options[@]}" "--defaults-file=${default_files}")
fi

status=$(mysqladmin "${options[@]}" status)
if [[ $? -ne 0 ]] || [[ -z $status ]]; then
  echo "CRITICAL - ${status}"
  exit 2
fi

mysql=$(echo "-u ${user}" "--password=${password}")

connected_thread=$(echo "$status" | awk '{ print $4 };')
max_connections=$(mysql $mysql -N -s -r -e 'SHOW VARIABLES LIKE "max_connections";' | \
  awk '{ print $2 };'
)

if [[ $? -ne 0 ]]; then
  echo "CRITICAL - could not fetch MySQL max_connections"
  exit 2
elif [[ -z $connected_thread ]] || [[ -z $max_connections ]]; then
  echo "CRITICAL - 'connected_thread' and 'max_connections' are empty"
  exit 2
fi

slave_io_running=$(mysql $mysql -e 'SHOW SLAVE STATUS\G;' | grep "Slave_IO_Running" | awk '{ print $2 }')
slave_sql_running=$(mysql $mysql -e 'SHOW SLAVE STATUS\G;' | grep "Slave_SQL_Running" | awk '{ print $2 }')
last_errno=$(mysql $mysql -e "SHOW SLAVE STATUS\G" | grep "Last_Errno" | awk '{ print $2 }')
seconds_behind_master=$(mysql $mysql -e 'SHOW SLAVE STATUS\G;' | grep "Seconds_Behind_Master" | awk '{ print $2 }')

used=$((connected_thread * 100 / max_connections))
status="${status} - ${connected_thread} of ${max_connections} max_connections slave_io_running: ${slave_io_running} slave_sql_running: ${slave_sql_running} last_errno: ${last_errno} seconds_behind_master: ${seconds_behind_master}";
if [[ $used -gt $critical ]]; then
  echo "CRITICAL - ${status}"
  exit 2
elif [[ $used -gt $warning ]]; then
  echo "WARNING - ${status}"
  exit 1
else
  echo "OK - ${status}"
  exit 0
fi

if [[ $slave_io_running -ne Yes ]]; then
  echo "CRITICAL - ${status}"
  exit 2
else
  echo "OK - ${status}"
  exit 0
fi

if [[ $slave_sql_running -ne Yes ]]; then
  echo "CRITICAL - ${status}"
  exit 2
else
  echo "OK - ${status}"
  exit 0
fi


if [[ $last_errno -gt 20 ]]; then
  echo "CRITICAL - ${status}"
  exit 2
elif [[ $last_errno -le 20 ]]; then
  echo "WARNING - ${status}"
  exit 1
else
  echo "OK - ${status}"
  exit 0
fi

if [[ $seconds_behind_master -gt 2000 ]]; then
  echo "CRITICAL - ${status}"
  exit 2
elif [[ $seconds_behind_master -le 2000 ]]; then
  echo "WARNING - ${status}"
  exit 1
else
  echo "OK - ${status}"
  exit 0
fi
