#!/bin/bash

# define the ISIN numbers of shares
source ./shares.sh

# set definitions for necessary input databases,
# generated databases with daily information and
# temporary databases
source ./settings.sh

###############################################################################
usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-u] [-m]
Retrieve and plot all closing prices and other informational graphs.
Available options:
-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-u, --noUpdates Skip price and value updates - only generate graphs
-m, --noMessage Do not send message
-c, --checkOnly Check all shares but do not log prices
EOF
  exit
}

parse_params() {
  # default values of variables set from params
  updatePrices=1
  sendNotification=1
  checkOnly=0

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    -u | --noUpdates) updatePrices=0 ;;     # skip price updates
    -m | --noMessage) sendNotification=0 ;; # do not send message
    -c | --checkOnly) checkOnly=1 ;;        # check only prices
    -?*) die "Unknown option: $1\nConsider using -h to see valid options." ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required params and arguments
#  [[ -z "${param-}" ]] && die "Missing required parameter: param"
#  [[ ${#args[@]} -eq 0 ]] && die "Missing script arguments"

  return 0
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

###############################################################################
getRATES () {
   RATES=`curl -s "https://openexchangerates.org/api/latest.json?app_id=45426bc5db78430f90e7ebe0f5cca8a1"`
   USD2EUR=`echo $RATES | jq .rates.EUR`
   USD2CHF=`echo $RATES | jq .rates.CHF`
   USD2NOK=`echo $RATES | jq .rates.NOK`
   CHF2EUR=`echo "($USD2EUR / $USD2CHF)" | bc -l`
   NOK2EUR=`echo "($USD2EUR / $USD2NOK)" | bc -l`
   printf "USD2EUR=%s\n" $USD2EUR
   printf "USD2CHF=%s\n" $USD2CHF
   printf "USD2NOK=%s\n" $USD2NOK
   printf "CHF2EUR=%s\n" $CHF2EUR
   printf "NOK2EUR=%s\n" $NOK2EUR
}

###############################################################################
comdirectGetCurrentPrice () {
printf "try to get price of %s" $1
   r=1.0
   # NOTE: use FIREFOX Inspektor Mode to find hxselect argument for given website
   p=`curl -m 20 -s "https://www.comdirect.de/inf/aktien/$1" | hxnormalize -x | hxselect -i "div.realtime-indicator" | lynx -stdin -dump | awk 'NF > 0' | grep -v "\-\-" | head -1 | tr -d '.' | tr -d ' ' | tr ',' '.'`
   if [ "$p" == "" ]; then
      p=`curl -m 20 -s "https://www.comdirect.de/inf/aktien/amazon-aktie-$1" | hxnormalize -x | hxselect -i "div.realtime-indicator" | lynx -stdin -dump | awk 'NF > 0' | grep -v "\-\-" | head -1 | tr -d '.' | tr -d ' ' | tr ',' '.'`
   fi
   if [ "$p" == "" ]; then
      p=`curl -m 20 -s "https://www.comdirect.de/inf/aktien/apple-aktie-$1" | hxnormalize -x | hxselect -i "div.realtime-indicator" | lynx -stdin -dump | awk 'NF > 0' | grep -v "\-\-" | head -1 | tr -d '.' | tr -d ' ' | tr ',' '.'`
   fi
printf "   ----> <%s>\n" $p
   # check whether we need a currency exchange rate
   if [[ $p == *"USD"* ]]; then
      r=$USD2EUR
   fi
   if [[ $p == *"CHF"* ]]; then
      r=$CHF2EUR
   fi
   if [[ $p == *"NOK"* ]]; then
      r=$NOK2EUR
   fi
   # now we can remove the currency
   p=`echo $p | tr -d [A-Z]`
   # now scale the money value based on the exchange rate so we have EUR
   p=`echo "result = ($p * $r); scale=2; result / 1" | bc -l`
}

###############################################################################
tradegateGetCurrentPrice () {
   p=`curl -s "https://www.tradegate.de/orderbuch.php?isin=$1" | grep '<td class="longprice"><strong id="last">' | cut -d'>' -f3 | cut -d'<' -f1 | tr -d ' ' | tr ',' '.'`
   if [ "$p" == "./." ]; then
      p=`curl -s "https://www.tradegate.de/orderbuch.php?isin=$1" | grep '<td class="longprice"><strong id="ask">' | cut -d'>' -f3 | cut -d'<' -f1 | tr -d ' ' | tr ',' '.'`
   fi
   if [ "$p" == "./." ]; then
      p=`curl -s "https://www.tradegate.de/orderbuch.php?isin=$1" | grep '<td class="longprice"><strong id="bid">' | cut -d'>' -f3 | cut -d'<' -f1 | tr -d ' ' | tr ',' '.'`
   fi
}

###############################################################################
# now get all closing prices
getClosingPrices () {
    # get the current exchange rate for the USD
    getRATES
    # get closing prices for all shares
    printf "getClosingPrices for $@ \n"
    for a in $@
    do
        printf "***** %s *****\n" $a
        p=""
        while [ "$p" == "" ]; do
          comdirectGetCurrentPrice $a
          if [ "$p" == "" ]; then
             sleep 20
          fi
        done
        if [ ! -e $a.csv ]; then
            # if CSV database does not exist, initialize it
            printf "`date +%d.%m.%Y`,$p,,0\n" $p $r >>$a.csv           
        else
           name=`head -1 $a.csv | awk '{print $3}' FS=,`
           printf "%s\t%s\t[%s] %s\n" $name $a $p $r
           if [ $checkOnly == 0 ]; then
              printf "`date +%d.%m.%Y`,$p,$r\n" $p $r >>$a.csv
           fi
        fi
    done
}

###############################################################################
# special run for the COMINVEST shares - we want to track their total value over time
calculateCominvestValue () {
    cominvest_totalvalue=0
    printf "calculateCominvestValue for $@ \n"
    for a in $@
    do
       pieces=`head -1 $a.csv | awk '{print $4}' FS=,`
       today=`tail -1 $a.csv | awk '{print $2}' FS=,`
       todayvalue=`echo "result = ($today * $pieces); scale=0; result / 1" | bc -l`
       cominvest_totalvalue=`echo "result = ($todayvalue + $cominvest_totalvalue); scale=0; result / 1" | bc -l`
       printf "CominvestTotal=$cominvest_totalvalue\n"
    done
    if [ $updatePrices == 1 ]; then
        if [ $checkOnly == 0 ]; then
           printf "`date +%d.%m.%Y`,$cominvest_totalvalue,`cat $INVESTMENT_DB | tr -d '\n'`\n" >>$INVESTMENTVALUE_DB
        fi
    fi
}

###############################################################################
parse_params "$@"

# remove the database for todays changes. We will recreate it every day
rm -rf $TODAYSCHANGES_DB

# make sure an investment file exists. If not, initialize it with ZEROs
if [ ! -e $INVESTMENT_DB ]; then
   printf "0,0\n" >>$INVESTMENT_DB
fi

# now get currency rates and all closing prices
if [ $updatePrices == 1 ]; then
   getClosingPrices "$COMDIRECT_SHARES $COMINVEST_SHARES $WATCHLIST_SHARES"
fi

# start totalvalue with ZERO for today
totalvalue=0

# calculate value and changes. Then plot them
for a in $COMDIRECT_SHARES $COMINVEST_SHARES $WATCHLIST_SHARES
do
   rm -rf $a.png
   gnuplot -e "DATA_FILE='$a.csv'" -e "PNG_FILE='$a.png'" plotDailyPrice.gnu

   name=`head -1 $a.csv | awk '{print $3}' FS=,`
   bought=`head -1 $a.csv | awk '{print $2}' FS=,`
   pieces=`head -1 $a.csv | awk '{print $4}' FS=,`
   today=`tail -1 $a.csv | awk '{print $2}' FS=,`
   todayvalue=`echo "result = ($today * $pieces); scale=0; result / 1" | bc -l`
   totalvalue=`echo "result = ($todayvalue + $totalvalue); scale=0; result / 1" | bc -l`
   yesterday=`tail -2 $a.csv | head -1 | awk '{print $2}' FS=,`
   totalchange=`echo "scale=1; (($today * 100) / $bought) - 100" | bc -l`
   change=`echo "result = (($today * 100) / $yesterday) - 100; scale=1; result / 1" | bc -l`
   moneychange=`echo "result = (($today * $pieces) - ($yesterday * $pieces)); scale=0; result / 1" | bc -l`
   if [ -e $a.png ]; then
      printf "%s,%s,%s\n" $name $change $moneychange >>$TODAYSCHANGES_DB
      if [ $sendNotification == 1 ]; then
          ./notifymewithpicture.sh "${name}: ${change}%, ${moneychange}€, ${todayvalue}€" $a.png
      fi
   fi
   printf "Total=$totalvalue incl. $name\n"
done

# plot summary of todays changes
gnuplot -e "DATA_FILE='$TODAYSCHANGES_DB'" todaysChanges.gnu
if [ $sendNotification == 1 ]; then
    ./notifymewithpicture.sh "Daily summary" $TODAYSCHANGES_PIC
    ./notifymewithpicture.sh "Money summary" $TODAYMONYCHANGE_PIC
fi

# plot a graph for the total value over time
if [ $updatePrices == 1 ]; then
    if [ $checkOnly == 0 ]; then
       printf "`date +%d.%m.%Y`,$totalvalue\n" >>$TOTALVALUE_DB
    fi
fi
gnuplot plotTotalValue.gnu
if [ $sendNotification == 1 ]; then
    ./notifymewithpicture.sh "Total Value ${totalvalue}€" $TOTALVALUE_PIC
fi

##################################################
# plot a graph for the COMINVEST total value over time
calculateCominvestValue "$COMINVEST_SHARES"
gnuplot plotCominvest.gnu
cominvestinvestment=`tail -1 $INVESTMENT_DB | head -1 | awk '{print $2}' FS=,`
cominvest_totalvalue=`echo "result = ($cominvestinvestment + $cominvest_totalvalue); scale=0; result / 1" | bc -l`
if [ $sendNotification == 1 ]; then
    ./notifymewithpicture.sh "COMINVEST Value ${cominvest_totalvalue}€" $INVESTMENTVALUE_PIC
fi
