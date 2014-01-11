#!/bin/bash

#path=$(dirname $0)
#path=${path/\./$(pwd)}

# Cookie file.
_cookie="rrrp.cookie"

# Config file.
_config="rrrp.cfg"

# Post params for auto-refresh.
_plogin="http://www.renren.com/PLogin.do"
#_origURL="http://www.renren.com" # Will append userid later
#_domain="renren.com"

# Post params for collectrp
_collectrp="http://renpin.renren.com/action/collectrp"
_host="renpin.renren.com"
_referer="http://renpin.renren.com/ajaxproxy.htm"
_origin="http://renpin.renren.com"
_contenttype="application/x-www-form-urlencoded"

if [ $# -ne 3 ]
then
	echo "Usage: $0 <username> <password> <period>"
	exit 1
fi
_email=$1
_password=$2
_period=$3
if [ $_period -le 0 ] 
then
	echo "<period> should be an integer greater than 0."
	exit 1
fi

# Read key-value pair from $_config.
# param: <key>
# output: <value>
get_config() {
    touch "$_config" && cat "$_config" | grep -o "^$1=.*" | sed "s/$1=//g"
}

# Update (or insert if not exists) key-value pair in $_config.
# param: <key> <new_value>
# output: none
update_config() {
    local kv=$(touch "$_config" && cat "$_config" | grep -o "^$1=.*")
    if [ ! -z "$kv" ]
    then
        sed -i "s/$1=.*/$1=$2/g" "$_config"
    else
        echo "$1=$2" >> "$_config"
    fi
}

# Parse RP value from renren home page
parse_rp() {
    cat lastpage.html | grep -o '<b class="freshNum">.*</b>' | sed 's/<[^>]*>//g'
}

# Logger
logger() {
    echo "[$(date +"%F")] $1"
}

# Automatically refresh every $_period minutes, supposing this script is
# executed every minute.
# Don't the following 2 lines: line 1 is to convert empty string to 0.
_counter=$(($(get_config "refresh_counter")))
_counter=$(($_counter%$_period))
update_config "refresh_counter" $((($_counter+1)%$_period))
if [ $_counter -eq 0 ]
then
    _rp=""
    if [ -s "$_cookie" ]
    then
        curl -s -D header_refresh.log -b "$_cookie" -L "$_origURL" >lastpage.html
        _rp=$(parse_rp)
    fi
    # TODO Check whether cookie is generated successfully.
    if [ -z "$_rp" ]
    then
        curl -s -D header_refresh.log -c "$_cookie" -L -d "email=$_email&password=$_password" "$_plogin" >lastpage.html
        _rp=$(parse_rp)
    fi

    logger "Auto-refresh called: $_rp"
fi

# Collect rp every day.
_last_collectrp_day=$(get_config "last_collectrp_day")
_today=$(date +"%F")
if [[ "$_last_collectrp_day" < "$_today" ]]
then
    # Experimental: Parse XN.get_check and XN.get_check_x from lastpage.html
    _xn_reg="get_check:'([^']*)',get_check_x:'([^']*)'"
    if [[ "$(cat lastpage.html | grep -o 'XN = {.*}')" =~ $_xn_reg ]]
    then
        _XN_get_check=${BASH_REMATCH[1]}
        _XN_get_check_x=${BASH_REMATCH[2]}

        curl -s -D header_collectrp.log -b "$_cookie" -L -d "requestToken=$_XN_get_check&_rtk=$_XN_get_check_x" -H "Host:$_host" -H "Referer:$_referer" -H "Origin:$_origin" -H "Content-Type:$_contenttype" "$_collectrp" >lastcollectrp.js

        code="`cat lastcollectrp.js | grep -o '"code":[0-9]*' | sed 's/"code"://g'`"
        if [ ! -z $code ]
        then
            update_config "last_collectrp_day" "$_today"
        fi
        if [ $code -eq 0 ]
        then
            _rp="`cat lastcollectrp.js | grep -i -o '"dailyRp":[0-9]*'`"
        else
            _rp="`cat lastcollectrp.js | grep -i -o '"msg":"[^"]*"'`"
        fi
        # TODO parse new RP value.
        logger "CollectRP called: $_rp"
    fi
fi

