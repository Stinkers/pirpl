#!/bin/bash

# To do list:
# 
# 1a. Add a "status" field to template. 
# 5.  Add mpfinfo files to directories with volume info etc.
# 8.  Prettify playlist chooser.

# New functions: 
#    "Play" resumes playing according to status file. If no status file then:
#    "Restart" Creates playlist (flag for random) and intial status file.
# New file structure:
#    <md5 of playlist location>.dat : Playlist
#    <md5 of playlist location>.stat : Playlist status

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

function gethash
{
echo $1 | md5sum | cut -f1 -d" "
}

function init_playlist
{
	local path=$1
	local plfile=$2
	local plstat=$3
	local flags=$4
	echo init playlist: $path, $plfile, $plstat, $flags

	if [[ -d $path ]]; then
		find "$path" -name "*.mp3" 2>/dev/null | sort >"$plfile"
	else
		cp "$path" "$plfile"
	fi

	if [[ $flags =~ .*s.* ]]; then
		pltemp="$(mktemp $TMPNAME.XXXXXX)"
		sort -R <"$plfile" >"$pltemp"
		mv -f "$pltemp" "$plfile"
		rm "$pltemp" 2>/dev/null
	fi

	playlistsize=$(wc -l "$plfile" | cut -f1 -d " " )
	if [[ $playlistsize -eq 0 ]]; then
		logger "$0: No tracks in playlist $playlist"
		return 1
	fi

	write_status "$plstat" $playlistsize 0 0
	return 0
}

function write_status
{
	local plstat="$1" 
	local plsize=$2 
	local plcurr=$3 
	local plstart=$4
	
	# Do it the stupid way until the trimming is done
	echo "Pirpl2 info v1.0" > "$plstat"
	echo $plsize >> "$plstat" # Number of tracks
	echo $plcurr >> "$plstat"	# Current track
	echo $plstart >> "$plstat"	# Current track start position
}

function trim_track
{
	write_status $1 $2 $3 $4

	local plstat="$1" 
	local plstart=$4
	local mp3track="$5"
	local pllock="$6"

	hashname=$(gethash $path)
	trimtrack="$PLAYLIST_LOCATION/$hashname.mp3"
	rm "$trimtrack" 2>/dev/null

	sox "$mp3track" -t mp3 - trim $plstart >"$trimtrack" &
	sox_pid=$!
	echo $sox_pid > "$pllock"
	wait $sox_pid

	echo done trimming
	rm "$pllock" 2>/dev/null

	# Update the web page now it's finished
	makeplaylist
		
	# Finished so add it on to the stat file
	echo "$trimtrack" >> "$plstat"	
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
	logger "$0: Missing template file $PIRPL_TEMPLATE"
	shutdown
fi

plhash="$PLAYLIST_LOCATION/$(gethash $path)"
plfile="$plhash.dat"
plstatus="$plhash.stat"
pllock="$plhash.lock"

if [[ ! -e "$plstatus" || ! -e "$plfile" ]]; then
	init_playlist "$path" "$plfile" "$plstatus" $flags
	if [[ $? -eq 1 ]]; then
		return 1
	fi
fi

template="$(<"$PIRPL_TEMPLATE")"

# Import playlist
readarray -t tracks < "$plfile"

# Get status of playlist
readarray -t status < "$plstatus"
totaltracks=${status[1]}
trackpos=${status[2]}
trackstart=${status[3]}
trimtrack=${status[4]}
trimcheck=0

while [[ $trackpos -lt $totaltracks ]]; do

	playtrack="${tracks[$trackpos]}"

	# If a partial track is in the stat file then play that instead
	if [[ $trimcheck -eq 1 || "$trimtrack" == "" ]]; then
		mp3track="$playtrack"
	else
		mp3track="$trimtrack"
		trimcheck=1
	fi

	echo $trackpos : $mp3track

	if [[ -e "$mp3track" ]]; then

		# Duration is always the original untrimmed track
		duration=$(mp3info -p "%S" "$playtrack")
		let "duration_m = $duration / 60"
		let "duration_s = $duration % 60"
		duration_txt=$(printf "%d:%02d" $duration_m $duration_s)

		start_timestamp=$(date +"%s")
		adjusted_start=$((start_timestamp-trackstart))

		taginfo="$(id3v2 -l "$playtrack")"

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
		out_template="${out_template//@@START_TIME@@/$adjusted_start}"

		statusJSON="{ \"artist\":\"$artist\", \"album\":\"$album\", \"track\":\"$number\", \"title\":\"$title\", \"duration\":$duration, \"start\":$start_timestamp, \"durationTxt\": \"$duration_txt\", \"status\": \"playing\" }"

		rm "$WEB_FILE" 2>/dev/null
		echo "$out_template" > "$WEB_FILE"
		rm "$WEB_INFO" 2>/dev/null
		echo "$statusJSON" > "$WEB_INFO"

		trim=""
		if [[ "$trackstart" != "0" && "$trimcheck" == "0" ]]; then
			trim="trim $trackstart"
		fi

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
				if [[ "$command" == "skip_track" || "$command" == "shut_down" ]]; then
					kill_processes $pifm_pid
				fi
			fi
		done
		# Go back to the playlist selector
		if [[ "$command" == "shut_down" ]]; then
			timenow=$(date +"%s")
			elapsed=$((timenow-adjusted_start))
			# Set up for the next play
			trim_track "$plstatus" $totaltracks $trackpos $elapsed "$playtrack" "$pllock" &
			
			cleanup
			return 0
		fi
	else
		logger "$0: Can't find $mp3track"
	fi # If mp3 exists
	((trackpos++))
	trackstart=0
done

# End of the playlist, so clean the playlist and status file.
rm "$plstatus"
rm "$plfile"

# Clean up temp files and shut down the transmitter
cleanup
}

function makeplaylist
{
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

		if [[ -e "$PLAYLIST_LOCATION/$(gethash $playlist_path).lock" ]]; then
			list="${list//@@showstepnext@@/display: inline;}"
			list="${list//@@showplay@@/display: none;}"
		else
			list="${list//@@showstepnext@/display: none;}"
			list="${list//@@showplay@@/display: inline;}"
		fi
	
		if [[ $playlist_flags =~ .*s.* ]]; then
			rand_flag="random"
		else
			rand_flag="ordered"
		fi
		list="${list//@@RANDOM_FLAG@@/$rand_flag}"
		list_out=$list_out$list

		(( id++ ))
	fi
done <"$PLAYLIST_CONF"

rm "$WEB_FILE" 2>/dev/null
echo "$prelist $list_out $postlist" >"$WEB_FILE"

}	

# -----------------------------------------------------------------------------
# End of the functions.  Execution starts here.
# -----------------------------------------------------------------------------

# Do a couple of checks to make sure things are OK before we start
if [[ $SERVER_PORT -lt 1024 ]]; then
	logger "$0: Invalid port for server.  It must be more than 1024"
	exit 1
fi

if [[ ! -e "$PLAYLIST_TEMPLATE" ]]; then
	logger "$0: Missing playlist template: $PLAYLIST_TEMPLATE"
	exit 1
fi

socat TCP4-LISTEN:$SERVER_PORT,reuseaddr,fork EXEC:"$PIRPL_SERVER $PIRPL_CONF",fdin=3,fdout=4 &
server_pid=$!

# Creates the list of playlists for the web server and waits for the command
# to start playing one of them.
while [[ 1 ]]; do

	makeplaylist

	id=0
	while IFS=":" read -ra playlist_line; do

		playlist_path=${playlist_line[0]}
		playlist_name=${playlist_line[1]}
		playlist_flags=${playlist_line[2]}

		if [[ ${playlist_line:0:1} != "#" && -n "$playlist_name" ]]; then
			# Populate internal data
			paths[$id]="$playlist_path"
			flags[$id]=$playlist_flags
			(( id++ ))
		fi
	done <"$PLAYLIST_CONF"
	
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
			if [[ "$command" == stepnext* ]]; then
				play_id=$(expr "$command" : '.*stepnext:\([0-9]*\).*')
				hashname="$PLAYLIST_LOCATION/$(gethash ${paths[play_id]})"
				lockname="$hashname.lock"
				statname="$hashname.stat"
				
				if [[ -e "$lockname" ]]; then

					# Kill off the Sox process that is trimming the mp3
					trim_pid=$(<"$lockname")					
					kill $trim_pid
					rm "$lockname" 2>/dev/null
				fi

				readarray statfile <"$statname"
				
				local i=0
				for statline in "${statfile[@]}"; do
					statfile[$i]=$(echo -e $statline | sed -e 's/^[[:cntrl:]]*//')
					(( i++ ))
				done
				
				# Move to the next track or rewind to the start if it's at the end
				if [[ "${statfile[2]}" -lt "${statfile[1]}" ]]; then
					(( statfile[2]++ ))
				else
					statfile[2]=0
				fi
				
				# Start at t=0
				statfile[3]=0
				
				printf "%s\n" "${statfile[@]}" > "$statname"
				
				done=1
			fi
		else
			sleep 1
		fi
	done
	
done	# Main loop never exits
