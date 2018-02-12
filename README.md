Pirpl - Pi Radio Playlist
=========================
## What is it?
Pirpl is a Web-interfaced controlled, playlist-based pirate radio jukebox type thing. Create playlists yourself or just point it to a directory containing MP3s and it'll recursively scan it to create a playlist from them.  Playlists can be shuffled.

**Now with streaming of internet radio stations!** Just put the URL of the "m3u" instead of the path and the flag is the gain for that station.

The playlist is played through a version of the [PiFM FM transmitter program](https://github.com/Stinkers/PiFMRDS-Extra) and broadcasts in stereo with RDS.
## Why is it written in Bash?
It started as a simple script to just play all the tracks in a directory, but it got out of hand. This project is the embodiment of the ["Sunk Cost Fallacy"](https://www.logicallyfallacious.com/tools/lp/Bo/LogicalFallacies/173/Sunk_Cost_Fallacy), taken to its awful extreme.
## Why don't you stop doing it and write it in a more suitable language?
Basically, [Stockholm Syndome](https://en.wikipedia.org/wiki/Stockholm_syndrome). I'm starting to like Bash.
## Is it ready to use?
Sure, why not? If you hate yourself enough.
## Requirements
1. piFMRDS-Extra
2. sox
3. id3v2
4. mp3info
5. socat
6. A masochistic streak a mile wide

