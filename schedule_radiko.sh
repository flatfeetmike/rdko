#!/bin/bash
# Schedule daily Radiko recording
# ref - http://gkmsxho.net/blog-entry-21.html

# sort用に
LANG=en_US.UTF-8

# store today's date in yyyy-mm-dd format
today=`date -I`

stationID="DATEFM"
weektable=${stationID}_${today}.xml 

# download today's program listing
if [ ! -e ${weektable} ]; then
	curl -s http://radiko.jp/v2/api/program/station/today?station_id=${stationID} \
	> ${weektable}
fi

# count the number of <prog> tags within today.xml
progcount=`grep "<prog ft=" ${weektable} |wc -l`

# go through each prog[i] in the xml tree
i=0
while (( i < ${progcount})) ; do
	(( i++ ))
	# extract the title from each program
	title=`echo "cat /radiko/stations/station/scd/progs/prog[${i}]/title" \
	| xmllint --shell ${weektable} \
	| sed -n -e "s/^.*>\(.*\)<.*/\1/p" \
	| sed -e "y/ \t\//___/" `
	# extract ft - from time
	# ftはyyyymmddhhmmssで記述されているがatコマンドの時刻はhh:mm mmddyyで指定
	ft=`echo "cat /radiko/stations/station/scd/progs/prog[${i}]/@ft" \
	| xmllint --shell ${weektable} \
	| sed -n -e "s/^.*ft=\"..\(..\)\(....\)\(..\)\(..\).*/\3:\4 \2\1/p" `
	# extract dur - duration in seconds
	dur=`echo "cat /radiko/stations/station/scd/progs/prog[${i}]/@dur" \
	| xmllint --shell ${weektable} \
	| sed -n -e "s/^.*dur=\"\([^\"]*\)\".*/\1/p" `
	# create file name
	rec_file=`echo "cat /radiko/stations/station/scd/progs/prog[${i}]/@ft" \
	| xmllint --shell ${weektable} \
	| sed -n -e "s/^.*ft=\"\(20..\)\(..\)\(..\)\(..\)\(..\).*/\1-\2-\3-\4\5/p" `
	rec_file="${rec_file}_$title"
	# directory name for recorded files
	dir_name=`echo "cat /radiko/stations/station/scd/progs/prog[${i}]/@ft" \
	| xmllint --shell ${weektable} \
	| sed -n -e "s/^.*ft=\"\(20..\)\(..\)\(..\)\(..\)\(..\).*/\1-\2-\3/p" `
	dir_name="/mnt/nas/Radiko/${dir_name}"

	# atコマンド整形
	at_command="/bin/bash /home/pi/bin/rec_radiko.sh -d $dir_name -f $rec_file -t $dur $stationID > /dev/null 2>&1"

	# すでに同じ内容がatに登録されていないか
	duplicate_flag=0
	if [ `atq | wc -l` -gt 0 ]; then
		all_jobs=`atq | cut -f1`
		for atqline in ${all_jobs} ; do
			if [ "`at -c ${atqline} \
				| sed -n -e "s%${at_command}%DUPLICATED%p" `" \
				== "DUPLICATED" ]
			then
				duplicate_flag=1
				break
			fi
		done
	fi
	# フラグ立たなかったらatに追加
	if [ "${duplicate_flag}" == "0" ]; then
		echo "${at_command}" \
		| at "${ft}" #- 1 minute
		echo "$ft $at_command" >> schedule_radiko.log
	fi
done
