#!/bin/bash

ver="0317181537"

################################################################################################################
###
### GNU General Public License v3 (GPLv3)
###
### This program is free software: you can redistribute it and/or modify
### it under the terms of the GNU General Public License as published by
### the Free Software Foundation, either version 3 of the License, or
### (at your option) any later version.
### 
### This program is distributed in the hope that it will be useful,
### but WITHOUT ANY WARRANTY; without even the implied warranty of
### MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
### GNU General Public License for more details.
### You should have received a copy of the GNU General Public License
### along with this program.  If not, see <http://www.gnu.org/licenses/>.
###
################################################################################################################
###
### vidChew2
### Copyright (C) 2018 \m/rr - emarrarr@tuta.io
###
### Usage: vidChew2 <targetFolder>
### Dependencies: ffmpeg, mediainfo (cli), bc, find, sort, cat, grep, tr, sed, awk, head, basename, bash
###
### Recursive batch video reencode script with optional video downscaling and audio downmixing via ffmpeg,
### written in BASH.
###
### - If no <targetFolder> argument is defined, vidChew2 will work inside current folder.
###
### - vidChew2 uses find to recursively scan a directory for inputs and, by default, will
###   output to the input's source folder.  Output folder can be modified via the destDir
###   config variable.
###   
### - If an input filename contains a string in the nameSkipArray, the input will be skipped. If an input 
###   file does not contain a video stream encoded with a codec contained in codecArray (mediainfo format),
###   the input will be skipped.  Output is always muxed into the Matroska container (mkv).
###
### - If downscaling is disabled, video is reeconded at its original size.
###   	 + If downscaling is enabled and input height or width is greater than maxVidWidth
###	  	   or maxVidHeight, then input is scaled to maxVidWidth and maxVidHeight.  Otherwise,
###   	   input is not scaled (input is never upscaled).
###
### - If force16 is enabled, inputs that are being downscaled will be forced to 16:9
###	  aspect ratio.
###      + If input is not being downscaled, aspect ratio never changes.
###
### - Audio track selection is as follows:
###      1) First audio track is set as fallback
###            If there are multiple audio tracks, a deep search is performed:
###               2) Stereo
###               3) Surround
###               4) Preferred language
###               5) Preferred language and stereo
###               6) Preferred language, preferred format, and stereo
###               7) Preferred language and surround
###               8) Preferred language, preferred format, and surround
###                  + The track chosen from the input is the one matching the highest criteria
###                    available in the above list.
###
### - If downmixing is disabled, audio is copied from input.
###      + If downmixing is enabled, audio is reencoded with downmixChannels using downmixCodec @
###        downmixTargBit unless the input is already downmixChannels channels.
###
### - Full channel input audio can be reencoded if reencAudio is enabled and downmix is disabled.
###
### - TrueHD (Dolby Atmos) audio is always reencoded using reencCodec @ reencTargBitSurround
###   when using reencAudio (even if bitrate is variable/unknown).
###
###	- If reencAudio & downmix are both disabled, audio is always copied from source.
###
### - vidChew2 will not run if reencAudio & downmix are both enabled.
###
### - The first targLang subtitle track (if exist) is selected for the output mux.
###   	 + If a targLang subtitle track isn't found, no subtitle track is included
###        in the output mux.
### 
### - The input subtitle track is converted to ASS if source is UTF-8/SRT/Timed Text or
###   copied if PGS/VobSub.
###      + Subtitle track is always set non-default.
###
### - No metadata (except audio/subtitle language) are copied.  Chapters are preserved.
###
### - Non-alphanumeric characters are removed from output filename.
###
### vidChew2 was born out of a desire to migrate my AVC movie & TV collection to HEVC using
### ffmpeg instead of Handbrake.  As is, vidChew2 only supports a single audio/subtitle track.
### It was obviously written specifically with 1080p/720p AVC (x264) or HEVC (x265) in mind and
### likely needs some changes to adequately support other codecs.  The config options are based 
### on ffmpeg & mediainfo codec/format syntax, so it's important to respect them or else some
### of the logic will fail.
###
### I strongly recommend testing on short clips before committing to hours (or years) of
### encoding before realizing you weren't happy with your settings ;P
### https://trac.ffmpeg.org/wiki/Seeking#Cuttingsmallsections
### ffmpeg -ss 00:15:00.0 -i "<in>" -map 0 -c copy -t 00:00:10.0 "<out>"
###
### Admittedly, the code is messy and somewhat specific to my personal needs, but it worked
### for the 1000+ files I threw at it.  This script could no doubt be signficantly improved.
### If such things are up your alley, you have my love and feel free.  I'd be quite thrilled
### if you reached out and shared your work. ;]
### 
### Taste the rainbow...
###
###		<3
###		\m/
###
################################################################################################################
###
### Version History (date +"%m%d%y%0k%M" -u)
###
### + 0317181537 - \m/rr
###      Initial release
###
################################################################################################################

################## BEGIN CONFIG ##################


### If enabled (dryRun="y"), do everything except actually encode
dryRun="y"

### Define tmp files, used to store mediainfo template and its output
### Most folks probably won't want to change this.
vcTmpIn="/tmp/vcTmpIn"
vcTmpOut="/tmp/vcTmpOut" 

### Enable log file creation for each script invocation
logging="y"
logFile="vidChew2.$(date +"%m%d%y%0k%M%S").log"

### Generate seperate ffmpeg encode reports (logs) for each input (gzipped)
genReports="y"

### Output destination with ~no~ trailing slash.  Blank (destDir="")
### will write outputs to same folder as input (with tags).
### ~Note~ that input sub-folder structure will not be maintained
### in destDir if destDir is not set to blank.
destDir=""

### Default behavior is to continue recursion if ffmpeg fails on an encode.
### Enable this to instead stop the script.
exitOnFail="n"

### If the output is larger than the input, ~DELETE~ it and copy the input to the destDir.
### If the input is larger than the output, ~DELETE~ it and copy the output to the destDir.
deleteLarger="n"
### If the above (deleteLarger) is enabled, output video needs be <= keepPerc%
### of original video's size to not be deleted.
keepPerc="80"

### + Input +

### Input filenames containing strings in nameSkipArray will be skipped
nameSkipArray=('vidChew' 'myTag')

### Only the codecs specified in codecArray will be reencoded (mediainfo "Video Format")
codecArray=('AVC' 'HEVC')

### Preferred language for audio & subtitle tracks (mediainfo "Language")
targLang="English"
### The above, but in ISO 639-2 format
### https://en.wikipedia.org/wiki/List_of_ISO_639-2_codes
tagLang="eng"

### + VIDEO +

### ffmpeg video encoder settings
targCodec="libx265"
codecPreset="medium"
targCrf="22"

### Downscaling
downscale="y"
maxVidWidth="1920"
maxVidHeight="1080"

### Force 16:9 if downscaling
force16="y"

### + AUDIO +

### Order of preference (left to right) when choosing input audio track
### (Mediainfo "Audio Format")
audioFormatPref=('AC-3' 'DTS' 'AAC')

### Surround -> stereo downmixing
downmix="n"
### ffmpeg audio encoder settings
downmixCodec="libfdk_aac"
downmixChannels="2"
downmixTargBit="192"
### Enabling downMixVbr will override above CBR downmixTargBit
downMixVbr="n"
downmixVbrQ="5"
### Mediainfo "Audio Format" corresponding to the above ffmpeg downmixCodec
downmixAudioTag="AAC"

### Reencode audio (only if NOT downmixing)
reencAudio="y"
### ffmpeg audio encoder settings
reencCodec="ac3"
### Bitrate used if input is stereo
reencTargBitStereo="256"
### Bitrate used if input is surround
reencTargBitSurround="640"
### Desired number of channels for output
reencChannelsSurround="6"
### Enabling downMixVbr will override above CBR reencTargBitStereo and reencTargBitSurround
reencVbr="n"
reencVbrQ="5"
### Mediainfo "Audio Format" corresponding to the above ffmpeg reencCodec
reencAudioTag="AC3"

### String appended to end of filename
fileTag="-myTag"

################## END CONFIG ##################

### Start timers
runTime="$(date +"%x %X")"
start=$SECONDS

### Determine input folder

if [ -z "$1" ] ; then
	targFolder="."
else
	targFolder="$1"
fi

### 'say' function (echo & log)

function say () {
	sayTimeCode=$(date +"%m%d%y%0k%M%S")
	echo "$sayTimeCode $1"
	if [ "$logging" = "y" ] ; then
		echo "$sayTimeCode $1" >> $logFile
	fi
}


### same thing but without timestamp, used mostly for blank lines

function sayB () {
	echo "$1"
	if [ "$logging" = "y" ] ; then
		echo "$1" >> $logFile
	fi
}

### Say hello!

sayB
say "!! vidChew2 by \m/rr :: $ver"
say "!! chewTime: $runTime"
say "!! targFolder: $targFolder"

if [ "$downmix" = "y" ] && [ "$reencAudio" = "y" ] ; then
	sayB
	say "!! downmix and reencAudio cannot both be enabled!"
	say "!! exiting..."
	sayB
	exit
fi

if [ "$logging" = "y" ] ; then
	say ":: logging: $logFile"
else
	say ":: logging disabled"
fi

### Create mediainfo template

echo "General;vcGen:%BitRate%\n" > $vcTmpIn
echo "Video;vcVid:id%ID%:%BitRate%:%Format%:%Width%:%Height%:%DisplayAspectRatio%\n" >> $vcTmpIn
echo "Audio;vcAudio:id%ID%:%BitRate%:%Format%:%SamplingRate%:%Format_Profile%:%Channels%:%Language/String%:%Channel(s)_Original%\n" >> $vcTmpIn
echo "Text;vcText:id%ID%:%Format%:%Language/String%\n" >> $vcTmpIn

### Use find to obtain list of inputs from Find track that is preferred format, preferred language, and surroundprovided path

find "$targFolder" ! -path . -type f | sort | while read line; do
	
	sayB
    say "!! processing: $line"
    toEncode="no"

### Determine whether or not to encode based on skipArray
	
	for i in "${nameSkipArray[@]}"
		do
			:
				if [[ ${line} = *"$i"* ]] ; then
					say "-- filename contains \"$i\""
					nameSkipTest="fail"
					break
				else
					nameSkipTest="pass"
				fi
	done
	
	if [ "$nameSkipTest" = "pass" ] ; then
		say "++ No skip string found in filename"
	fi
	
### Determine whether or not to encode based on codecArray

    videoCodec=$(mediainfo --Inform="Video;%Format%\n" "$line" | head -n1)
    
    if [ "$videoCodec" = "" ] ; then
		videoCodec="UNKNOWN"
	fi
	
	for i in "${codecArray[@]}"
		do
			: 
				if [ "$videoCodec" = "$i" ] ; then
					say "++ Supported codec found: $i"
					codecTest="pass"
					break
				else
					codecTest="fail"					
				fi
	done
	
	if [ "$codecTest" = "fail" ] ; then
		say "-- Unsupported codec found: $videoCodec"
	fi
	
	say ":: nameSkipTest: $nameSkipTest | codecTest: $codecTest"
	
	if [ "$nameSkipTest" = "fail" ] || [ "$codecTest" = "fail" ]; then
		say "!! Skipping..."
	else
	
### Begin main encode sequence
		sayB
		say "!! re-encoding!"
		sayB

### Obtain file / video track / subtitle track info
		say ":: Obtaining input info..."
		sayB
		
		mediainfo --Inform="file:///$vcTmpIn" "$line" > $vcTmpOut
		
		origSize=$(stat --printf="%s" "$line")
		origSize=$(echo "scale=2; $origSize / 1000000" | bc)
		generalBitrate=$(cat $vcTmpOut | grep vcGen | awk -F ':' '{ print $2 }')
		generalBitrate=$(echo "scale=2;$generalBitrate / 1000" | bc)
		generalBitrate=$(echo "($generalBitrate+0.5)/1" | bc)
		videoBitrate=$(cat $vcTmpOut | grep vcVid | awk -F ':' '{ print $3 }')
		if [ "$videoBitrate" = "" ] ; then
			videoBitrate="variable/unknown"
		else
			videoBitrate=$(echo "scale=2;$videoBitrate / 1000" | bc)
			videoBitrate=$(echo "($videoBitrate+0.5)/1" | bc)
		fi
		videoWidth=$(cat $vcTmpOut | grep vcVid | awk -F ':' '{ print $5 }' | head -n1)
		videoHeight=$(cat $vcTmpOut | grep vcVid | awk -F ':' '{ print $6 }' | head -n1)
		videoAspect=$(cat $vcTmpOut | grep vcVid | awk -F ':' '{ print $7 }' | head -n1)
		vidTrack=$(cat $vcTmpOut | grep vcVid | awk -F ':' '{ print $2 }' | cut -c3- | head -n1)
		targSubTrack=$(cat $vcTmpOut | grep vcText | grep $targLang | awk -F ':' '{ print $2 }' | cut -c3- | head -n1)
		subFormat=$(cat $vcTmpOut | grep vcText | grep $targLang | awk -F ':' '{ print $3 }' | head -n1)
		if [ "$subFormat" = "" ] ; then
			subFormat=$(cat $vcTmpOut | grep vcText | awk -F ':' '{ print $3 }' | head -n1)
			if [ "$subFormat" = "" ] ; then
				subFormat="none/unknown"
			fi
		fi

### Determine target audio track

say "-+- Audio Search -+-"
sayB

### Set the first audio track as the fallback

		targAudioTrack=$(cat $vcTmpOut | grep vcAudio | tr -d ' ' | sed 's/Unknown\///g' | awk -F ':' '{ print $2 }' | cut -c3- | head -n1)
		targAudioTrack=$(echo "$targAudioTrack - 1" | bc)
		if [ "$targAudioTrack" != "" ] ; then
			testLanguage=$(cat $vcTmpOut | grep vcAudio | awk -F ':' '{ print $8 }' | head -n1)
			if [ "$testLanguage" = "" ] ; then
				testLanguage="unknown"
			fi
			testChannels=$(cat $vcTmpOut | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $7 }' | head -n1 | sed 's/.*\(.\)/\1/')
			testChannelsOrig=$(cat $vcTmpOut | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $9 }' | head -n1 | sed 's/.*\(.\)/\1/')
			if [ "$testChannelsOrig" != "" ] ; then
				testChannels=$testChannelsOrig
			fi
			testFormat=$(cat $vcTmpOut | grep vcAudio | awk -F ':' '{ print $4 }' | head -n1)
			targAudioTrackMap="-map 0:$targAudioTrack"
			if [ "$testLanguage" = "$targLang" ] ; then
				targAudioTrackTag="-metadata:s:1 language=$tagLang"
			else
				targAudioTrackTag=""
			fi
			say "++ Fallback (first) audio track set!"
			sayB "                   track: $targAudioTrack | channels: $testChannels | format: $testFormat | lang: $testLanguage"
		else
			targAudioTrackMap=""
			targAudioTrackTag=""
			say "-- No first audio track found, assuming no audio."
		fi

### Determine total number of audio tracks

		numAudioTracks=$(cat $vcTmpOut | grep vcAudio | wc -l)
		
### If there is more than one, perform a deep search
		
		if [ "$numAudioTracks" -gt "1" ] ; then

			IFS=$'\r\n' GLOBIGNORE='*' command eval 'vcAudioLines=($(cat $vcTmpOut | grep vcAudio | tr -d " " | sed "s/Unknown\///g"))'
			
### Find track that is stereo

			for i in "${vcAudioLines[@]}" ; do :
				testTrack=$(echo "$i" | awk -F ':' '{ print $2 }' | cut -c3-)
				testTrackFF=$(echo "$testTrack - 1" | bc)
				testLanguage=$(echo "$i" | awk -F ':' '{ print $8 }')
				testChannels=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $7 }' | head -n1 | sed 's/.*\(.\)/\1/')
				testChannelsOrig=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $9 }' | head -n1 | sed 's/.*\(.\)/\1/')
				if [ "$testChannelsOrig" != "" ] ; then
					testChannels=$testChannelsOrig
				fi
				testFormat=$(echo "$i" | awk -F ':' '{ print $4 }')
				if [ "$testChannels" = "2" ] ; then
					targAudioTrack=$(echo "$testTrack - 1" | bc)
					targAudioTrackMap="-map 0:$targAudioTrack"
					if [ "$testLanguage" = "$targLang" ] ; then
						targAudioTrackTag="-metadata:s:1 language=$tagLang"
					else
						targAudioTrackTag=""
					fi
					say "++ Audio track (stereo) found!"
					sayB "                   track: $targAudioTrack | channels: $testChannels | format: $testFormat"
					break
				fi
			done
				
### Find track that is surround

			for i in "${vcAudioLines[@]}" ; do :
				testTrack=$(echo "$i" | awk -F ':' '{ print $2 }' | cut -c3-)
				testTrackFF=$(echo "$testTrack - 1" | bc)
				testLanguage=$(echo "$i" | awk -F ':' '{ print $8 }')
				testChannels=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $7 }' | head -n1 | sed 's/.*\(.\)/\1/')
				testChannelsOrig=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $9 }' | head -n1 | sed 's/.*\(.\)/\1/')
				if [ "$testChannelsOrig" != "" ] ; then
					testChannels=$testChannelsOrig
				fi
				testFormat=$(echo "$i" | awk -F ':' '{ print $4 }')
				if [ "$testChannels" -gt "2" ] ; then
					targAudioTrack=$(echo "$testTrack - 1" | bc)
					targAudioTrackMap="-map 0:$targAudioTrack"
					if [ "$testLanguage" = "$targLang" ] ; then
						targAudioTrackTag="-metadata:s:1 language=$tagLang"
					else
						targAudioTrackTag=""
					fi
					say "++ Audio track (surround) found!"
					sayB "                   track: $targAudioTrack | channels: $testChannels | format: $testFormat"
					break
				fi
			done

### Find track that is preferred language

			for i in "${vcAudioLines[@]}" ; do :
				testTrack=$(echo "$i" | awk -F ':' '{ print $2 }' | cut -c3-)
				testTrackFF=$(echo "$testTrack - 1" | bc)
				testLanguage=$(echo "$i" | awk -F ':' '{ print $8 }')
				testChannels=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $7 }' | head -n1 | sed 's/.*\(.\)/\1/')
				testChannelsOrig=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $9 }' | head -n1 | sed 's/.*\(.\)/\1/')
				if [ "$testChannelsOrig" != "" ] ; then
					testChannels=$testChannelsOrig
				fi
				testFormat=$(echo "$i" | awk -F ':' '{ print $4 }')
				if [ "$testLanguage" = "$targLang" ] ; then
					targAudioTrack=$(echo "$testTrack - 1" | bc)
					targAudioTrackMap="-map 0:$targAudioTrack"
					targAudioTrackTag="-metadata:s:1 language=$tagLang"
					say "++ $targLang audio track found!"
					sayB "                   track: $targAudioTrack | channels: $testChannels | format: $testFormat"
					break
				fi
			done
			
### Find track that is preferred language and stereo
			
			for i in "${vcAudioLines[@]}" ; do :
				testTrack=$(echo "$i" | awk -F ':' '{ print $2 }' | cut -c3-)
				testTrackFF=$(echo "$testTrack - 1" | bc)
				testLanguage=$(echo "$i" | awk -F ':' '{ print $8 }')
				testChannels=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $7 }' | head -n1 | sed 's/.*\(.\)/\1/')
				testChannelsOrig=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $9 }' | head -n1 | sed 's/.*\(.\)/\1/')
				if [ "$testChannelsOrig" != "" ] ; then
					testChannels=$testChannelsOrig
				fi
				testFormat=$(echo "$i" | awk -F ':' '{ print $4 }')
				if [ "$testLanguage" = "$targLang" ] && [ "$testChannels" = "2" ] ; then
					targAudioTrack=$(echo "$testTrack - 1" | bc)
					targAudioTrackMap="-map 0:$targAudioTrack"
					targAudioTrackTag="-metadata:s:1 language=$tagLang"
					say "++ $targLang (stereo) audio track found!"
					sayB "                   track: $targAudioTrack | channels: $testChannels | format: $testFormat"
					break
				fi
			done
			
### Find track that is preferred format, preferred language, and stereo
			
			trackFound="n"
			for prefFormat in "${audioFormatPref[@]}" ; do :
				for i in "${vcAudioLines[@]}" ; do :
					testTrack=$(echo "$i" | awk -F ':' '{ print $2 }' | cut -c3-)
					testTrackFF=$(echo "$testTrack - 1" | bc)
					testLanguage=$(echo "$i" | awk -F ':' '{ print $8 }')
					testChannels=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $7 }' | head -n1 | sed 's/.*\(.\)/\1/')
					testChannelsOrig=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $9 }' | head -n1 | sed 's/.*\(.\)/\1/')
					if [ "$testChannelsOrig" != "" ] ; then
						testChannels=t$estChannelsOrig
					fi
					testFormat=$(echo "$i" | awk -F ':' '{ print $4 }')
					if [ "$testLanguage" = "$targLang" ] && [ "$testChannels" = "2" ] && [ "$testFormat" = "$prefFormat" ] ; then
						targAudioTrack=$(echo "$testTrack - 1" | bc)
						targAudioTrackMap="-map 0:$targAudioTrack"
						targAudioTrackTag="-metadata:s:1 language=$tagLang"
						say "++ $targLang (stereo / preferred format) audio track found!"
						sayB "                   track: $targAudioTrack | channels: $testChannels | format: $testFormat"
						trackFound="y"
						break
					fi
				done
				if [ "$trackFound" = "y" ] ; then
					break
				fi
			done
			
### Find track that is preferred language and surround
			
			trackFound="n"
			for prefFormat in "${audioFormatPref[@]}" ; do :
				for i in "${vcAudioLines[@]}" ; do :
					testTrack=$(echo "$i" | awk -F ':' '{ print $2 }' | cut -c3-)
					testTrackFF=$(echo "$testTrack - 1" | bc)
					testLanguage=$(echo "$i" | awk -F ':' '{ print $8 }')
					testChannels=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $7 }' | head -n1 | sed 's/.*\(.\)/\1/')
					testChannelsOrig=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $9 }' | head -n1 | sed 's/.*\(.\)/\1/')
					if [ "$testChannelsOrig" != "" ] ; then
						testChannels=$testChannelsOrig
					fi
					testFormat=$(echo "$i" | awk -F ':' '{ print $4 }')
					if [ "$testLanguage" = "$targLang" ] && [ "$testChannels" -gt "2" ] ; then
						targAudioTrack=$(echo "$testTrack - 1" | bc)
						targAudioTrackMap="-map 0:$targAudioTrack"
						targAudioTrackTag="-metadata:s:1 language=$tagLang"
						say "++ $targLang (surround) audio track found!"
						sayB "                   track: $targAudioTrack | channels: $testChannels | format: $testFormat"
						trackFound="y"
						break
					fi
				done
				if [ "$trackFound" = "y" ] ; then
					break
				fi
			done
			
### Find track that is preferred format, preferred language, and surround
			
			trackFound="n"
			for prefFormat in "${audioFormatPref[@]}" ; do :
				for i in "${vcAudioLines[@]}" ; do :
					testTrack=$(echo "$i" | awk -F ':' '{ print $2 }' | cut -c3-)
					testTrackFF=$(echo "$testTrack - 1" | bc)
					testLanguage=$(echo "$i" | awk -F ':' '{ print $8 }')
					testChannels=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $7 }' | head -n1 | sed 's/.*\(.\)/\1/')
					testChannelsOrig=$(echo "$i" | grep vcAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $9 }' | head -n1 | sed 's/.*\(.\)/\1/')
					if [ "$testChannelsOrig" != "" ] ; then
						testChannels=$testChannelsOrig
					fi
					testFormat=$(echo "$i" | awk -F ':' '{ print $4 }')
					if [ "$testLanguage" = "$targLang" ] && [ "$testChannels" -gt "2" ] && [ "$testFormat" = "$prefFormat" ] ; then
						targAudioTrack=$(echo "$testTrack - 1" | bc)
						targAudioTrackMap="-map 0:$targAudioTrack"
						targAudioTrackTag="-metadata:s:1 language=$tagLang"
						say "++ $targLang (surround / preferred format) audio track found!"
						sayB "                   track: $targAudioTrack | channels: $testChannels | format: $testFormat"
						trackFound="y"
						break
					fi
				done
				if [ "$trackFound" = "y" ] ; then
					break
				fi
			done
		
		else
			say "-- Only one audio track found, skipping deep search..."
		
		fi
		
	say "!! Track chosen: $targAudioTrack"


### Determine audio format based on targAudioTrack

		searchAudio=$(echo "$targAudioTrack + 1" | bc)
		audioFormat=$(cat $vcTmpOut | grep vcAudio | grep id$searchAudio | awk -F ':' '{ print $4 }')
		
### Determine audio channels based on targAudioTrack
		
		audioChannels=$(cat $vcTmpOut | grep vcAudio | grep id$searchAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $7 }' | sed 's/.*\(.\)/\1/')
		audioChannelsOrig=$(cat $vcTmpOut | grep vcAudio | grep id$searchAudio | tr -d " " | sed "s/Unknown\///g" |  awk -F ':' '{ print $9 }' | sed 's/.*\(.\)/\1/')
		if [ "$testChannelsOrig" != "" ] ; then
			audioChannels=$audioChannelsOrig
		fi
		
### Determine audio bitrate

		audioBitrate=$(cat $vcTmpOut | grep vcAudio | grep id$searchAudio | awk -F ':' '{ print $3 }' | sed 's/[^0-9]*//g')
		
		if [ "$audioBitrate" = "" ] ; then
			audioBitrate="variable/unknown"
			audioBitrateRaw=""
		else
			audioBitrate=$(echo "scale=2;$audioBitrate / 1000" | bc)
			audioBitrate=$(echo "($audioBitrate+0.5)/1" | bc)
			audioBitrateRaw=$audioBitrate
		fi
	
		
		if [ "$audioFormat" = "DTS" ] ; then
			if [ "$audioBitrate" -gt "1509" ] ; then
				audioBitrate=$(echo "$audioBitrate" | sed 's/.*\(....\)/\1/')
				audioBitrate=$(echo "($audioBitrate+0.5)/1" | bc)
				audioBitrateRaw=$audioBitrate
			fi
		fi

### Determine audio language
	
		audioLang=$(cat $vcTmpOut | grep vcAudio | grep -w id$searchAudio | awk -F ':' '{ print $8 }')
		if [ "$audioLang" = "" ] ; then
			audioLang="unknown"
		fi
		
### Determine subtitle track number 
		
		if [ "$targSubTrack" != "" ] ; then
			targSubTrack=$(echo "$targSubTrack - 1" | bc)
			targSubTrackMap="-map 0:$targSubTrack"
			targSubTrackTag="-metadata:s:2 language=$tagLang"
		else
			targSubTrack=""
			targSubTrackMap=""
			targSubTrackTag=""
		fi
		
### Determine subtitle language
	
	if [ "$targSubTrack" != "" ] ; then
		searchSub=$(echo "$targSubTrack + 1" | bc)
		subLang=$(cat $vcTmpOut | grep vcText | grep -w id$searchSub | awk -F ':' '{ print $4 }')
		if [ "$subLang" = "" ] ; then
			subLang="unknown"
		fi
	fi
		
### Copy PGS and VobSub subs and let ffmpeg convert other formats to ASS
		
		if [ "$subFormat" = "PGS" ] || [ "$subFormat" = "VobSub" ] ; then
			subOpt="-c:s copy"
		else
			subOpt=""
		fi
		
### Map video track
		
		vidTrack=$(echo "$vidTrack - 1" | bc)
		vidTrackMap="-map 0:$vidTrack"
		
### Downscale, if enabled

		if [ "$downscale" = "y" ] ; then
			if [ "$videoWidth" -gt "$maxVidWidth" ] || [ "$videoHeight" -gt "$maxVidHeight" ] ; then
				scaleOpt="-vf scale=$maxVidWidth:$maxVidHeight"
				if [ "$force16" = "y" ] ; then
					if [ "$videoAspect" != "1.778" ] ; then
						scaleOpt="$scaleOpt,setdar=dar=16/9"
					fi
				fi
			else
				scaleOpt=""
			fi
		else
			scaleOpt=""
		fi
		
### Audio downmixing / reencoding

		charK="k"
				
		if [ "$downmix" = "y" ] ; then		
			if [[ "$audioChannels" = "$downmixChannels"* ]]; then
				doDownmix="n"
				audioOpt="copy"
				tagAudio="$audioFormat"
				tagChannels="$audioChannels"
			else
				if [ "$downMixVbr" = "n" ] ; then
					audioOpt="$downmixCodec -b:a $downmixTargBit$charK -ac $downmixChannels"
				else
					audioOpt="$downmixCodec -q:a $downMixVbr -ac $downmixChannels"
				fi
				tagAudio="$downmixAudioTag"
				tagChannels="$downmixChannels"
			fi
		else
			if [ "$reencAudio" = "y" ] ; then
				if [ "$audioBitrate" != "variable/unknown" ] ; then
					if [ "$audioChannels" -gt "2" ] ; then
						if [ "$audioBitrateRaw" -le "$reencTargBitSurround" ] ; then
							doReencAudio="n"
							audioOpt="copy"
							tagAudio="$audioFormat"
							tagChannels="$audioChannels"
						else
							if [ "$reencVbr" = "n" ] ; then
								doReencAudio="y"
								audioOpt="$reencCodec -b:a $reencTargBitSurround$charK -ac $reencChannelsSurround"
							else
								doReencAudio="y"
								audioOpt="$reencCodec -q:a $reencVbr -ac $reencChannelsSurround"
							fi
							tagAudio="$reencAudioTag"
							tagChannels="$reencChannelsSurround"
						fi
					else
						if [ "$audioBitrateRaw" -le "$reencTargBitStereo" ] ; then
							doReencAudio="n"
							audioOpt="copy"
							tagAudio="$audioFormat"
							tagChannels="$audioChannels"
						else
							if [ "$reencVbr" = "n" ] ; then
								doReencAudio="y"
								audioOpt="$reencCodec -b:a $reencTargBitStereo$charK"
							else
								doReencAudio="y"
								audioOpt="$reencCodec -q:a $reencVbr"
							fi					
							tagAudio="$reencAudioTag"
							tagChannels="$audioChannels"					
						fi
					fi
				else
					doReencAudio="n"
					audioOpt="copy"
					tagAudio="$audioFormat"
					tagChannels="$audioChannels"
				fi
			else
				audioOpt="copy"
				tagAudio="$audioFormat"
				tagChannels="$audioChannels"
			fi
		fi
		
### Force reencode of TrueHD audio (only if reencoding audio)

if [ "$reencAudio" = "y" ] ; then
	if [ "$audioFormat" = "TrueHD" ] ; then
		if [ "$reencVbr" = "n" ] ; then
			audioOpt="$reencCodec -b:a $reencTargBitSurround$charK -ac $reencChannelsSurround"
		else
			audioOpt="$reencCodec -q:a $reencVbr -ac $reencChannelsSurround"
		fi
		tagAudio="$reencAudioTag"
		tagChannels="$reencChannelsSurround"
	fi
fi

### Determine destination filenames

		charP="p"
		stringCh="ch"
		
		if [ "$tagAudio" = "AC-3" ] ; then
			tagAudio="AC3"
		elif [ "$tagAudio" = "E-AC-3" ] ; then
			tagAudio="EAC3"
		else
			if [ "$tagAudio" != "" ] ; then
				tagAudio="$tagAudio"
			else
				tagAudio="tagAudio"
			fi
		fi		
		
		if [ "$targCodec" = "libx265" ] ; then
			tagCodec="HEVC"
		elif [ "$targCodec" = "libx264" ] ; then
			tagCodec="AVC"
		else
			tagCodec="tagCodec"
		fi
		
		if [ "$tagCodec" = "HEVC" ] ; then
			tagEncoder="x265"
		elif [ "$tagCodec" = "AVC" ] ; then
			tagEncoder="x264"
		else
			tagEncoder="tagEncoder"
		fi
		
		if [ "$downscale" = "y" ] ; then
			tagRes="$maxVidHeight$charP"
		else
			if [ "$videoWidth" = "1920" ] ; then
				tagRes="1080p"
			elif [ "$videoWidth" = "1280" ] ; then
				tagRes="720p"
			else
				tagRes="$videoHeight$charP"
			fi
		fi
			
		name=$(basename "$line")
		
		filename=$(basename "$name")
		extension="${filename##*.}"
		filename="${filename%.*}"
		filename="$(echo "$filename" | tr -cd '[[:alnum:]]._-')"
		
		newname="$filename.$tagRes.$tagCodec.$tagEncoder.$tagChannels$stringCh.$tagAudio$fileTag.mkv"
		
		dir=$(dirname "$line")
		
		if [ "$destDir" = "" ] ; then
			dest=$dir/$newname
		else
			dest=$destDir/$newname
		fi
		
		reportFilename=$(basename "$dest")
		reportFilename="$reportFilename-report.log"
		
		reportDest=$dir/$reportFilename
		
## Echo pre-encode data summary

		charX="x"

		sayB
		say "-+- Conversion Details -+-"
		sayB
		say ":: $name ($origSize MB | $generalBitrate kb/s)"
		sayB
		say "-+- Input -+-"
		sayB
		say "++ Video"
		say ":: track: $vidTrack | $videoWidth$charX$videoHeight ($videoAspect AR) | codec: $videoCodec @ $videoBitrate kb/s"
		sayB
		say "++ Audio"
		say ":: audioLang: $audioLang"
		if [ "$audioBitrateRaw" = "" ] ; then
			audioBitrateDisp="variable/unknown kb/s"
		else
			audioBitrateDisp="$audioBitrateRaw kb/s"
		fi
		say ":: track: $targAudioTrack | $audioFormat @ $audioBitrateDisp ($audioChannels ch)"
		sayB
		say "++ Subtitles"
		if [ "$targSubTrack" = "" ] ; then
			say "-- No $targLang subtitle track found"
		else
				say ":: track: $targSubTrack ($subLang / $subFormat)"
		fi
		sayB
		say "-+- Output -+-"
		sayB
		say "++ Video"
		say ":: targCodec: $targCodec @ $targCrf CRF ($codecPreset)"
		if [ "$downscale" = "y" ] ; then
			say ":: downscale: yes"
			say ":: maxDimensions: $maxVidWidth$charX$maxVidHeight"
			if [ "$scaleOpt" != "" ] ; then
				say ":: force16: $force16"
			else
				say "!! Downscaling unnecessary"
			fi
		else
			say ":: downscale: no"
		fi
		if [ "$scaleOpt" != "" ] ; then
			say ":: scaleOpt: $scaleOpt"
		fi
		sayB
		say "++ Audio"
		if [ "$targAudioTrackTag" = "" ] ; then
			say ":: audioLang: $audioLang"
		else
			say ":: audioLang: $audioLang [tag: $tagLang]"
		fi
		if [ "$downmix" = "y" ] && [ "$reencAudio" = "n" ] ; then
			say ":: downmix: yes"
			say ":: downmixChannels: $downmixChannels"
			if [ "$audioOpt" = "copy" ] ; then
				say ":: Downmixing unnecessary"
				if [ "$doDownmix" = "n" ] ; then
					say "!! Not downmixing because audio is already $downmixChannels channels."
				fi
			else
				if [ "$targAudioTrackTag" = "" ] ; then
					say ":: audioDownmix: $downmixCodec @ $downmixTargBit kb/s ($downmixChannels ch)"
				else
					say ":: audioDownmix: $downmixCodec @ $downmixTargBit kb/s ($downmixChannels ch) [tag: $downmixAudioTag]"
				fi
			fi
		fi
		if [ "$reencAudio" = "y" ] && [ "$downmix" = "n" ] ; then
			say ":: reencAudio: yes"
			if [ "$tagChannels" -le "2" ] ; then
				if [ "$targAudioTrackTag" = "" ] ; then
					say ":: audioReenc: $reencCodec @ $reencTargBitStereo kb/s ($tagChannels ch)"
				else
					say ":: audioReenc: $reencCodec @ $reencTargBitStereo kb/s ($tagChannels ch) [tag: $reencAudioTag]"
				fi
			else
				if [ "$targAudioTrackTag" = "" ] ; then
					say ":: audioReenc: $reencCodec @ $reencTargBitSurround kb/s ($tagChannels ch)"
				else
					say ":: audioReenc: $reencCodec @ $reencTargBitSurround kb/s ($tagChannels ch) [tag: $reencAudioTag]"
				fi
			fi			
			if [ "$audioOpt" = "copy" ] ; then
				say "!! Audio reencoding unnecessary"
				if [ "$doReencAudio" = "n" ] ; then
					say "!! Not reencoding because input stream has a bitrate <="
					say "!! target bitrate OR input stream bitrate is variable/unknown."
				fi
			fi
		fi
		say ":: audioOpt: $audioOpt"
		sayB
		say "++ Subtitles"
		if [ "$targSubTrack" = "" ] ; then
			say "-- No $targLang subtitle track found"
		else
			say ":: $subLang / $subFormat [tag: $tagLang]"
			if [ "$subOpt" = "" ] ; then
				say ":: subOpt: convert to ASS"
			else
				say ":: subOpt: copy"
			fi
		fi
		sayB
		say "-+- Filename -+-"
		sayB
		say ":: tagRes: $tagRes | tagCodec: $tagCodec | tagEncoder: $tagEncoder | tagChannels: $tagChannels$stringCh | tagAudio: $tagAudio | fileTag: $fileTag"
		say ":: dest: $dest"
		if [ "$genReports" = "y" ] ; then
			say ":: report: $reportFilename"
		fi
		sayB
		
### Construct, echo, and exec encode cmd	

		if [ "$genReports" = "y" ] ; then
			reportOpt="FFREPORT=file=\"$reportDest\":level=40"
		else
			reportOpt=""
		fi
		
		ffmpegFailed="no"
		
		cmd="$reportOpt </dev/null ffmpeg -y -v verbose -i \"$line\" $vidTrackMap $targAudioTrackMap $targSubTrackMap $targAudioTrackTag $targSubTrackTag $scaleOpt -c:v $targCodec -preset $codecPreset -crf $targCrf -c:a $audioOpt $subOpt -disposition:v:0 1 -disposition:a:0 1 -disposition:s:0 0 -map_metadata -1 \"$dest\""	
		
		say "!! exec: $cmd"
		sayB
			
		if [ "$dryRun" = "n" ] ; then
			
			eval $cmd
			
### ffmpeg error handling
			
			if [ $? -eq 0 ] ; then
				sleep 2s
				sayB
				say "!! ffmpeg exited cleanly!"
				if [ "$genReports" = "y" ] ; then
					cmd="gzip -f -v \"$reportDest\""
					sayB
					say "!! exec: $cmd"
					eval $cmd
				fi
			else	
				ffmpegFailed="yes"
				sleep 2s
				sayB
				say "!! ffmpeg experienced an error and encode likely did not finish..."
				if [ "$genReports" = "y" ] ; then
					cmd="mv -v \"$reportDest\" \"$reportDest.ERROR\""
					sayB
					say "!! exec: $cmd"
					eval $cmd
					cmd="gzip -f -v \"$reportDest.ERROR\""
					sayB
					say "!! exec: $cmd"
					eval $cmd
				fi
				if [ "$exitOnError" = "y" ] ; then
					say "!! exitOnError enabled, exiting..."
					exit
				fi
			fi
			
## Determine, compare, and echo input & output file sizes / percentage
			
			if [ "$ffmpegFailed" = "no" ] ; then
				newGeneralBitrate=$(mediainfo --Inform="General;%BitRate%" "$dest")
				newGeneralBitrate=$(echo "$newGeneralBitrate / 1000" | bc)
				destSize=$(stat --printf="%s" "$dest")
				destSize=$(echo "scale=2; $destSize / 1000000" | bc)
				sayB
				
				say ":: inputGeneralBitrate: $generalBitrate kb/s"
				say ":: outputGeneralBitrate: $newGeneralBitrate kb/s"
				
				sayB
				say ":: origSize: $origSize MB"
				say ":: destSize: $destSize MB"
				
				compareSize=$(echo "scale=4; $destSize / $origSize * 100" | bc)
				compareSize=${compareSize::-2}
				compareSize=$(echo "($compareSize+0.5)/1" | bc)
				say ":: compareSize: $compareSize%"
				sayB
				
### Determine which file to remove and do so, if enabled
			
				if [ "$deleteLarger" = "y" ] ; then
					if [ "$compareSize" -le "$keepPerc" ] ; then
						say ":: New vid's size is <= $keepPerc% of old vid's size!  Keeping new and removing old..."
						cmd="rm -v \"$line\""
						say "!! exec: $cmd"
						eval $cmd
					else
						say ":: New vid's size is NOT <= $keepPerc% of old vid's size!  Keeping old and removing new..."
						cmd="rm -v \"$dest\""
						say "!! exec: $cmd"
						eval $cmd
						sayB
						if [ "$destDir" != "" ] ; then
							say ":: Copying input to destDir..."
							cmd="cp -v \"$line\" \"$destDir/\""
							say "!! exec: $cmd"
							eval $cmd
						fi
					fi
				fi
			fi
		fi
	fi
done

### Remove tmp files

rm $vcTmpIn
rm $vcTmpOut 

### Stop timers

endTime=$(date +"%x %X")
duration=$(( SECONDS - start ))

if [ "$duration" -gt "60" ] ; then
	duration=$(echo "scale=2;$duration / 60" | bc)
	duration="$duration min"
elif [ "$duration" -gt "3600" ] ; then
	duration=$(echo "scale=2;$duration / 3600" | bc)
	duration="$duration hrs"
else
	duration="$duration sec"
fi

### Say farewell

sayB
say "!! Processing finished!"
say ":: chewEnd: $endTime"
say ":: chewDuration: $duration"
sayB
