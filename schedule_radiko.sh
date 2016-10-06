#!/bin/bash
# sort用に
LANG=en_US.UTF-8
reserv_table=$1
# 今の時刻取得
touch executed_time.dat
# 予約表の一行ごとに処理
cat ${reserv_table} | while read fileline
do
  set -- ${fileline}
  #$1 局
  #$2 検索ワード
  #$3 実行タイプ（Play | Record | PlayRecord）
  
  stationID=$1
  search_word=$2
  runtype=$3
  weektable=weektable\(${stationID}\).xml 
  
  # 一週間分の番組表を取得
  # 複数キーワードで同じ局が指定されていた場合、
  # 何度もダウンロードするのもアレなので
  if [ ! -e ${weektable} -o executed_time.dat -nt ${weektable} ]; then
    curl -s http://radiko.jp/v2/api/program/station/weekly?station_id=${stationID} \
      > ${weektable}
  fi
  
  # 検索する
  search_result=`echo "grep ${search_word}" \
    | xmllint --shell ${weektable} \
    | sed -n -e "s/^.*progs\[\(.*\)\].*prog\[\(.*\)\].*/\1 \2/p" \
    | uniq`
  
  # 検索結果に対して処理する
  echo "${search_result}" | while read resultline
  do
    set -- ${resultline}
    #$1 progs[x]
    #$2 prog[x]
    title=`echo "cat /radiko/stations/station/scd/progs[$1]/prog[$2]/title" \
      | xmllint --shell ${weektable} \
      | sed -n -e "s/^.*>\(.*\)<.*/\1/p" \
      | sed -e "y/ \t\//___/" `
    # ftはyyyymmddhhmmssで記述されているが
    # atコマンドの時刻はhh:mm mmddyyで指定
    ft=`echo "cat /radiko/stations/station/scd/progs[$1]/prog[$2]/@ft" \
      | xmllint --shell ${weektable} \
      | sed -n -e "s/^.*ft=\"..\(..\)\(....\)\(..\)\(..\).*/\3:\4 \2\1/p" `
    dur=`echo "cat /radiko/stations/station/scd/progs[$1]/prog[$2]/@dur" \
      | xmllint --shell ${weektable} \
      | sed -n -e "s/^.*dur=\"\([^\"]*\)\".*/\1/p" `
    
    # atコマンド整形
    at_command="/bin/bash /home/pi/bin/rec_radiko.sh \
      $stationID $(($dur + 60)) /home/pi/radio $title $runtype > /dev/null 2>&1"
    
    # すでに同じ内容がatに登録されていないか
    duplicate_flag=0
    if [ `atq | wc -l` -gt 0 ]; then
      all_jobs=`atq | cut -f1`
      for atqline in ${all_jobs}
      do
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
        | at "${ft}" - 1 minute
    fi
  done
done
# 一応けしとく
rm executed_time.dat
