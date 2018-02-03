#!/bin/bash

# New web server for Pirpl.  This one can react to the request sent by the 
# browser rather than just punting out a file.  Uses socat rather than nc.

# It serves the playlist or playing page depending on the state of Pirpl.  
# It is also used as a basic API by appending the following to the URL:
#
# /load=@filename@  - The server sends "filename", as defined in pirpl_conf
# 
# /query=@querytype@  - where "querytype" can be:
#   status : Sends JSON formatted info about the current track playing.  
#            Returns a status of "stopped" if in playlist choosing mode.
#   timenow : Returns the current timestamp in JSON format.
# 
# /cmd=@command@  - Controls Pirpl.  Valid "command" strings are:
#   skip_track : Skips to the next track
#   shut_down : Stops playing and goes back to the playlist page.
# 
# The server does not control Pirpl directly, but drops a file which Pirpl
# reads and then acts on.
# 
# Be careful exposing this service to the outside world.  It has not been 
# inspected for security issues and it is strongly recommended to run it
# behind a firewall or on a port that is only accessible from an internal
# network.

if [[ -z "${1:-}" || "$1" == "" || ! -f "$1" ]]; then
	echo "Usage: $0 <config file>"
	exit 1
	fi
PIRPL_SERVER_CONF="$1"

. "$PIRPL_SERVER_CONF"

# if [[ "$DEBUG" == "true" ]]; then logger "pirpl web server accessed..."; fi

# Get the request from the browser.  socat is set up for fd3=in, fd4=out
request=""
while read -r -t 5 line; do

#	if [[ "$DEBUG" == "true" ]]; then logger "$0: Parsing - $line"; fi
	if [[ ! -z "${line:-}" && $line == *[^[:cntrl:]]* ]]; then

		if [[ ${line:0:4} == "GET " ]]; then
			request=$(expr "$line" : 'GET /\(.*\) HTTP.*')
		fi
	else
		break
	fi
done

# Send back headers for reply
printf "HTTP/1.1 200 OK\n"

if [[ -z "${request:-}" ]]; then 
	command="page"; 
else
	command=$(expr "$request" : '\(.*\)=.*')
fi

if [[ "$DEBUG" == "true" ]]; then logger "$0: Request: $request"; fi

case $command in

load)
	# Send a file - resources specified in pirpl_conf
	loadfile=$(expr "$request" : '.*load=@\(.*\)@.*')	
	if [[ "${resources[$loadfile]}" != "" ]]; then
		printf "Content-Type: ${mimetypes[$loadfile]}\n\n"
		cat ${resources[$loadfile]}
	else
		printf "Content-Type: text/html\n\n"
		printf "<html>Resource not found</html>\n"
	fi
;;

query) 
	printf "Content-Type: application/json\n\n"
	query=$(expr "$request" : '.*query=@\(.*\)@.*')

	if [[ "$query" = "timenow" ]]; then
		echo "{ \"timenow\": "`date +"%s"`" }"
	fi
	if [[ "$query" = "status" ]]; then
		cat "$WEB_INFO"
	fi
;;

cmd)
	printf "Content-Type: text/html\n\n"
	# Send any commands to the player
	cmd=$(expr "$request" : '.*cmd=@\(.*\)@.*')
	rm "$CMD_FILE" 2>/dev/null
	echo "$cmd" > "$CMD_FILE"
;;

page | *)
	printf "Content-Type: text/html\n\n"

	# If it's not a command send back the web page
	if [[ -e "$WEB_FILE" ]]; then
		cat "$WEB_FILE"
	else
		logger "$0: Server can't find web page."
		echo "Error.  Pirpl doesn't seem to be running."
	fi
;;
esac 

