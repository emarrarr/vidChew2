vidChew2
Copyright (C) 2018 \m/rr emarrarr@tuta.io

Usage: vidChew2 [targetFolder]

Dependencies: ffmpeg, mediainfo (cli), bc, find, sort, cat, grep, tr, sed, awk, head, basename, bash

Recursive batch video reencode script with optional video downscaling and audio downmixing via ffmpeg,
written in BASH.

+ If no <targetFolder> argument is defined, vidChew2 will work inside current folder.

+ vidChew2 uses find to recursively scan a directory for inputs and, by default, will output to the input's source folder.  Output folder can be modified via the destDir config variable.
  
+ If an input filename contains a string in the nameSkipArray, the input will be skipped. If an input  file does not contain a video stream encoded with a codec contained in codecArray (mediainfo format), the input will be skipped.  Output is always muxed into the Matroska container (mkv).

+ If downscaling is disabled, video is reeconded at its original size. If downscaling is enabled and input height or width is greater than maxVidWidth or maxVidHeight, then input is scaled to maxVidWidth and maxVidHeight.  Otherwise, input is not scaled (input is never upscaled).

+ If force16 is enabled, inputs that are being downscaled will be forced to 16:9 aspect ratio. If input is not being downscaled, aspect ratio never changes.

+ Audio track selection is as follows:

  1) First audio track is set as fallback

    If there are multiple audio tracks, a deep search is performed

  2) Stereo
  3) Surround
  4) Preferred language
  5) Preferred language and stereo
  6) Preferred language, preferred format, and stereo
  7) Preferred language and surround
  8) Preferred language, preferred format, and surround

    The track chosen from the input is the one matching the highest criteria available in the above list.

+ If downmixing is disabled, audio is copied from input.  If downmixing is enabled, audio is reencoded with downmixChannels using downmixCodec @ downmixTargBit unless the input is already downmixChannels channels.

+ Full channel input audio can be reencoded if reencAudio is enabled and downmix is disabled.

+ TrueHD (Dolby Atmos) audio is always reencoded using reencCodec @ reencTargBitSurround when using reencAudio (even if bitrate is variable/unknown).

+ If reencAudio & downmix are both disabled, audio is always copied from source.

+ vidChew2 will not run if reencAudio & downmix are both enabled.

+ The first targLang subtitle track (if exist) is selected for the output mux.  If a targLang subtitle track isn't found, no subtitle track is included in the output mux.

+ The input subtitle track is converted to ASS if source is UTF-8/SRT/Timed Text or copied if PGS/VobSub.  Subtitle track is always set non-default.

+ No metadata (except audio/subtitle language) are copied.  Chapters are preserved.

+ Non-alphanumeric characters are removed from output filename.

vidChew2 was born out of a desire to migrate my AVC movie & TV collection to HEVC using ffmpeg instead of Handbrake.  As is, vidChew2 only supports a single audio/subtitle track. It was obviously written specifically with 1080p/720p AVC (x264) or HEVC (x265) in mind and likely needs some changes to adequately support other codecs.  The config options are based  on ffmpeg & mediainfo codec/format syntax, so it's important to respect them or else some of the logic will fail.

I strongly recommend testing on short clips before committing to hours (or years) of encoding before realizing you weren't happy with your settings. ;P

https://trac.ffmpeg.org/wiki/Seeking#Cuttingsmallsections

ffmpeg -ss 00:15:00.0 -i "[in]" -map 0 -c copy -t 00:00:10.0 "[out]"

Admittedly, the code is messy and somewhat specific to my personal needs, but it worked for the 1000+ files I threw at it.  This script could no doubt be signficantly improved. If such things are up your alley, you have my love and feel free.  I'd be quite thrilled if you reached out and shared your work. ;]

Taste the rainbow...

<3

\m/
