
. pirpl_conf

# Exit nicely when sent SIGINT
trap shutdown INT

# Called on CTRL-C or SIGINT.  Turns things off nicely and cleans up.
function shutdown
{
echo Shutting down...

kill $server_pid

# Shutdown the transmitter
$PIFM_BINARY &>/dev/null

# Clean up the temporary files
rm $TMPNAME.* 2>/dev/null
rm $WEB_FILE 2>/dev/null
rm $CMD_FILE 2>/dev/null

exit 0
}

function gethash
{
echo $1 | md5sum | cut -f1 -d" "
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
echo playing $1

if [[ ! -e "$PIRPL_TEMPLATE" ]]; then
	echo "Missing template file $PIRPL_TEMPLATE" 1>&2
	shutdown
fi

plhash="$PLAYLIST_LOCATION/$(gethash $path)"
plfile="$plhash.dat"
plstatus="$plhash.stat"

echo playlist: $plfile
echo status: $plstatus
}

play "/home/naich/wibble"
