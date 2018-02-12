# Common config file for pirpl.  All these values can be changed, but only the first few are useful to change.

# Change these lines to match your system and preferences
PIFM_FREQUENCY="107.3" # Transmitter frequency
PIFM_FLAGS="-preemph eu -ag 4" # EU pre-emphasis, gain of 2
PIFM_NAME="WibbleFM" # Station name, 8 chars
PIFM_RTEXT="Add some Wibble to your life" # Radio text, 64 chars
PIFM_BASE="/home/naich/pirpl" # Directory this was installed in
PIFM_RESOURCES="$PIFM_BASE/resources"
SERVER_PORT="8081" # Point your browser to http://your_pi_ip:8080
# PIFM_BINARY="/home/naich/pi/PiFMRDS-Extra/pi_fm_rds"
PIFM_BINARY="/home/naich/PiFMRDS-Extra/src/pi_fm_rds" # pifm binary

# Other arguments to pass to SOX, e.g.
# SOX_ARGS="compand 0.3,0.8 6:-70,-60,-20 -11 -90 0.2"
# SOX_ARGS="--norm"
SOX_ARGS=""
SOX_FILTER="vol 1.5 loudness"

# Debugging
DEBUG="true"
# DEBUG="false"
set -u

# The rest can be left as defaults unless you want to change them

# Files served by the server
declare -A resources mimetypes
resources["jquery"]="$PIFM_RESOURCES/jquery-2.1.3.min.js"
mimetypes["jquery"]="text/javascript"
resources["playcss"]="$PIFM_RESOURCES/playcss.css"
mimetypes["playcss"]="text/css"
resources["playlistcss"]="$PIFM_RESOURCES/list.css"
mimetypes["playlistcss"]="text/css"
resources["pauseicon"]="$PIFM_RESOURCES/media-pause-6x.png"
mimetypes["pauseicon"]="image /png"
resources["stopicon"]="$PIFM_RESOURCES/media-stop-6x.png"
mimetypes["stopicon"]="image/png"
resources["nexticon"]="$PIFM_RESOURCES/media-step-forward-6x.png"
mimetypes["nexticon"]="image/png"
resources["smallplayicon"]="$PIFM_RESOURCES/media-play-4x.png"
mimetypes["smallplayicon"]="image/png"
resources["randomicon"]="$PIFM_RESOURCES/random-4x.png"
mimetypes["randomicon"]="image/png"
resources["skipbackicon"]="$PIFM_RESOURCES/media-skip-backward-4x.png"
mimetypes["skipbackicon"]="image/png"
resources["stepforwardicon"]="$PIFM_RESOURCES/media-step-forward-4x.png"
mimetypes["stepforwardicon"]="image/png"

PIRPL_SERVER="$PIFM_BASE/pirpl_server.sh"
WEB_FILE="$PIFM_BASE/pirpl_web.html" # Web page to be output
WEB_INFO="$PIFM_BASE/pirpl_info.txt" # Info for the web server
CMD_FILE="$PIFM_BASE/pirpl_cmd.txt" # Command file from web server
PIRPL_TEMPLATE="$PIFM_RESOURCES/pirpl_template.html" # Template for the web server pa
STREAM_TEMPLATE="$PIFM_RESOURCES/stream_template.html" # Template for steaming.
PLAYLIST_CONF="$PIFM_BASE/pirpl_playlist.conf"
PLAYLIST_TEMPLATE="$PIFM_RESOURCES/pirpl_playlist_template.html"
PLAYLIST_LOCATION="$PIFM_BASE/playlists"
CURRENTLY_PLAYING="$PIFM_BASE/currently_playing.txt"
TMPNAME="/tmp/pirpltmp"

