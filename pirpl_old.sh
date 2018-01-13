#!/bin/bash

# To do list:
# 
# 00 Reads tracks from temp file one at a time, deleting it from the top.
# 0 Change the way it plays tracks from the tmpfile.  Only generates
#   tmpfile if a) told to, b) missing.  Otherwise it uses the existing one.
# 1a. Add a "status" field to template. 
# 2.  Add pause function to player within play loop (ajax) - restart at 
#     beginning of mp3.  Update status flag.
# 3.  Add function to start playing mp3 n seconds in (ajax).
# 5.  Add mpfinfo files to directories with volume info etc.
# 7.  Improve controls - use ajax to load track info.
# 8.  Prettify playlist chooser.

if [[ "$1" = "-h" ||  "$1" = "--help" ]]; then
	cat <<EOF
	
pirpl : Pi-rate Radio PLaylist
 
 Web-interfaced controlled, playlist-based pirate radio jukebox type thing.  
 Create playlists yourself or just point it to a directory containing MP3s 
 and it'll recursively scan it to create a playlist from them.  Playlists 
 can be shuffled.

 More wibble...
  
Usage: pirpl.sh [-h | --help]|<config file>

  -h --help : Display this help
  config file : List of settings and paths.  Edit it to change things like 
                transmission frequency, server port etc.

Example: ./pirpl.sh ./pirpl_conf

EOF
	exit 0
else
	if [[ "$1" = "" || ! -f "$1" ]]; then
		echo "Usage: pirpl.sh [-h | --help]|<config file>"
		exit 1
	fi
	PIRPL_CONF="$1"
fi

. "$PIRPL_CONF"

# Exit nicely when sent SIGINT
trap shutdown INT

# kill_processes <pid1> [pid2] ...
# Makes sure the processes are dead before returning.
function kill_processes
{
ARGS=("$*")
arg_count=$#
argc=$arg_count

while [[ $argc > 0 ]]; do
	argc=$arg_count
	for kp_pid in $ARGS; do
		if [[ -e /proc/$kp_pid ]]; then
			kill -15 $kp_pid
		else
			(( argc-- ))
		fi
	done
	if [[ $argc > 0 ]]; then 
		sleep 1; 
	fi
done
}

# Called on CTRL-C or SIGINT.  Turns things off nicely and cleans up.
function shutdown
{
echo Shutting down...

kill $server_pid

cleanup
exit 0
}

function cleanup
{
# Shutdown the transmitter
$PIFM_BINARY &>/dev/null

# Clean up the temporary files
rm $TMPNAME.* 2>/dev/null
rm $WEB_FILE 2>/dev/null
rm $CMD_FILE 2>/dev/null
}

function new_playlist
{
path=$1
flags=$2
}

# play <path> <flags> 
#   path: Path to playlist or directory containing MP3s
#   flags: s - shuffle
# 
# If path is a directory, it is recursively scanned for MP3s and they are 
# made into a playlist.  If path is a file, the playlist is the contents of
# the file.
function play
{
path=$1
flags=$2
# echo playing $1

if [[ ! -e "$PIRPL_TEMPLATE" ]]; then
	echo "Missing template file $PIRPL_TEMPLATE" 1>&2
	shutdown
fi

if [[ -d $path ]]; then
	playlistfile="$(mktemp $TMPNAME.XXXXXX)"
	find "$path" -name "*.mp3" 2>/dev/null | sort >"$playlistfile"
else
	playlistfile="$path"
fi

if [[ $flags =~ .*s.* ]]; then
	playlist="$(mktemp $TMPNAME.XXXXXX)"
	sort -R <"$playlistfile" >"$playlist"
else
	playlist="$playlistfile"
fi
	
playlistsize=$(wc -l "$playlist" | cut -f1 -d " " )                        
if [[ $playlistsize -eq 0 ]]; then
	echo "No tracks in playlist $playlist" 1>&2
	return
fi

template="$(<"$PIRPL_TEMPLATE")"

while read mp3track; do
	echo $mp3track
	if [[ -e "$mp3track" ]]; then

		duration=$(mp3info -p "%S" "$mp3track")
		let "duration_m = $duration / 60"
		let "duration_s = $duration % 60"
		duration_txt=$(printf "%d:%02d" $duration_m $duration_s)

		start_timestamp=$(date +"%s")

		taginfo="$(id3v2 -l "$mp3track")"

		# id3v2 gives different outputs for different versions
		case "${taginfo:0:5}" in

		# v1 Uses fixed width fields with more than one tag per line
		"id3v1")
			title=$(expr "$taginfo" : '.*Title  : \(.\{31\}\).*' | sed 's/ *$//')
			number=$(expr "$taginfo" : '.*Track: \([0-9/]*\).*')
			artist=$(expr "$taginfo" : '.*Artist: \(.\{20\}\).*' | sed 's/ *$//')
			album=$(expr "$taginfo" : '.*Album  : \(.\{31\}\).*' | sed 's/ *$//')
			;;

		# v2 doesn't
		"id3v2")
			title=$(expr "$taginfo" : '.*TIT2[^:]*: \([^[:cntrl:]]*\).*')
			number=$(expr "$taginfo" : '.*TRCK[^:]*: \([0-9/]*\).*')
			artist=$(expr "$taginfo" : '.*TPE1[^:]*: \([^[:cntrl:]]*\).*')
			album=$(expr "$taginfo" : '.*TALB[^:]*: \([^[:cntrl:]]*\).*')
			;;
		*)
			title="Unknown"
			number="0"
			artist="Unknown"
			album="Unknown"
			;;
		esac

		out_template="${template//@@ARTIST_NAME@@/$artist}"
		out_template="${out_template//@@ALBUM_NAME@@/$album}"
		out_template="${out_template//@@TRACK_NUMBER@@/$number}"
		out_template="${out_template//@@TRACK_NAME@@/$title}"
		out_template="${out_template//@@TRACK_DURATION_S@@/$duration}"
		out_template="${out_template//@@TRACK_DURATION_TXT@@/$duration_txt}"
		out_template="${out_template//@@START_TIME@@/$start_timestamp}"

		statusJSON="{ \"artist\":\"$artist\", \"album\":\"$album\", \"track\":\"$number\", \"title\":\"$title\", \"duration\":$duration, \"start\":$start_timestamp, \"durationTxt\": \"$duration_txt\", \"status\": \"playing\" }"

		rm "$WEB_FILE" 2>/dev/null
		echo "$out_template" > "$WEB_FILE"
		rm "$WEB_INFO" 2>/dev/null
		echo "$statusJSON" > "$WEB_INFO"

		# Play the track in the background
		sox "$mp3track" $SOX_ARGS -t wav - channels 1 rate 22050 vol 1 | $PIFM_BINARY - $PIFM_FREQUENCY &
		pifm_pid=$!

		# Keep polling for commands or the end of the mp3
		while [ -e /proc/$pifm_pid ]; do
			sleep 0.5

			# Check for commands from the web server
			if [[ -e "$CMD_FILE" ]]; then
				command=$(<"$CMD_FILE")
				rm "$CMD_FILE" 2>/dev/null
			
				# Either skipping or returning to playlist requires killing sox and pifm
				if [[ "$command" = "skip_track" || "$command" = "shut_down" ]]; then
					kill_processes $pifm_pid
				fi
			fi
		done
		# Go back to the playlist selector
		if [[ "$command" = "shut_down" ]]; then
			break
		fi
	fi # If mp3 exists
done <"$playlist"

# Clean up temp files and shut down the transmitter
cleanup
}

# End of the functions.  Execution starts here.
# Do a couple of checks to make sure things are OK before we start
if [[ $SERVER_PORT -lt 1024 ]]; then
	echo "Invalid port for server.  It must be more than 1024" 1>&2
	exit 1
fi

if [[ ! -e "$PLAYLIST_TEMPLATE" ]]; then
	echo "Missing playlist template: $PLAYLIST_TEMPLATE" 1>&2
	exit 1
fi

socat TCP4-LISTEN:$SERVER_PORT,reuseaddr,fork EXEC:"$PIRPL_SERVER $PIRPL_CONF",fdin=3,fdout=4 &
server_pid=$!

# Creates the list of playlists for the web server and waits for the command
# to start playing one of them.
while [[ 1 ]]; do

	playlist_template="$(<"$PLAYLIST_TEMPLATE")"
	prelist=$(expr "$playlist_template" : '^\(.*\)@@P_START@@')
	postlist=$(expr "$playlist_template" : '.*@@P_END@@\(.*\)')
	list_template=$(expr "$playlist_template" : '.*@@P_START@@\(.*\)@@P_END@@.*')

	list_out=""
	id=0
	while IFS=":" read -ra playlist_line; do

		playlist_path=${playlist_line[0]}
		playlist_name=${playlist_line[1]}
		playlist_flags=${playlist_line[2]}
		playlist_tracks=${playlist_line[3]}

		if [[ ${playlist_line:0:1} != "#" && -n "$playlist_name" ]]; then

			# Make playlist for template
			list="${list_template//@@P_ID@@/$id}"
			list="${list//@@PLAYLIST@@/$playlist_name}"
			list="${list//@@PLAYLIST_TRACKS@@/$playlist_tracks}"
			if [[ $playlist_flags =~ .*s.* ]]; then
				rand_flag="random"
			else
				rand_flag="ordered"
			fi
			list="${list//@@RANDOM_FLAG@@/$rand_flag}"
			list_out=$list_out$list

			# Populate internal data
			paths[$id]="$playlist_path"
			flags[$id]=$playlist_flags
			(( id++ ))
		fi
	done <"$PLAYLIST_CONF"
	
	rm "$WEB_FILE" 2>/dev/null
	echo "$prelist $list_out $postlist" >"$WEB_FILE"

	statusJSON="{ \"status\": \"stopped\" }"
	rm "$WEB_INFO" 2>/dev/null
	echo "$statusJSON" > "$WEB_INFO"

	# Wait for a command.  The web server writes the commands to $CMD_FILE
	done=0
	while [[ $done -eq 0 ]]; do

		if [[ -e "$CMD_FILE" ]]; then
			command=$(<"$CMD_FILE")
			rm "$CMD_FILE" 2>/dev/null

			# Playlist selected
			if [[ "$command" == playlist* ]]; then
				play_id=$(expr "$command" : '.*playlist:\([0-9]*\).*')
				play "${paths[$play_id]}" ${flags[$play_id]} 2>/dev/null
				done=1
			fi				
		else
			sleep 1
		fi
	done
	
done	# Main loop never exits
