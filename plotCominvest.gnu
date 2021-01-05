# usage: gnuplot -e "DATA_FILE='xxx.csv'" -e "PNG_FILE='xxx.png'" plotCominvest.gnu
# 
# If no DATA_FILE is set by command line option '-e', the default data file will be "cominvestValue.csv"
#
# If no PNG_FILE is set by command line option '-e', the default output file will be "cominvestValue.png"
#
# Created 26.07.2020 M.Schmidl

##############################################################################
# define where the data comes from and where the plot goes to
if (!exists("DATA_FILE")) DATA_FILE='cominvestValue.csv'
if (!exists("PNG_FILE")) PNG_FILE='cominvestValue.png'

##############################################################################
set fit quiet
set fit logfile '/dev/null'
set macros
set terminal pngcairo size 800,480
set datafile separator ","
#set yrange [0:]
#set logscale y
set decimal locale
set format y "%'.0f€"
set key right bottom

##############################################################################
today = system("tail -1 ".DATA_FILE." | awk '{print $2+$4}' FS=,") + 0.0
yesterday = system("tail -2 ".DATA_FILE." | head -1 | awk '{print $2+$4}' FS=,") + 0.0
invest = system("tail -1 ".DATA_FILE." | head -1 | awk '{print $3}' FS=,") + 0.0
totalchange = ((today * 100) / invest) - 100
change = ((today * 100) / yesterday) - 100
set title sprintf("today %'.f€ (%'.f%%) because %'.f€ -> %'.f€ (total %'.f€ %'.f%%)", today - yesterday, change, yesterday, today, today - invest, totalchange)

##############################################################################
prices="< awk '{print $1\",\"$2+$4\",\"$3}' FS=, ".DATA_FILE.""
set output PNG_FILE

set timefmt "%d.%m.%Y"

stats prices using 2 name "Y_" nooutput
stats prices using 2 name "power" nooutput

stats prices using (timecolumn(1)) every ::Y_index_min::Y_index_min nooutput
X_min = STATS_min
stats prices using (timecolumn(1)) every ::Y_index_max::Y_index_max nooutput
X_max = STATS_max

belowMax = ((today * 100) / Y_max) - 100
aboveMin = ((today * 100) / Y_min) - 100

set xdata time
set format x "%d.%b"
set grid ytics lc rgb "black" lw 1 lt 0 front
set grid xtics lc rgb "black" lw 1 lt 0 front

##############################################################################
# average function over N sample points
n = 14
# initialize the variables
do for [i=1:n] {
    eval(sprintf("back%d=0", i))
}
# build shift function (back_n = back_n-1, ..., back1=x)
shift = "("
do for [i=n:2:-1] {
    shift = sprintf("%sback%d = back%d, ", shift, i, i-1)
} 
shift = shift."back1 = x)"
# uncomment the next line for a check
# print shift
# build sum function (back1 + ... + backn)
sum = "(back1"
do for [i=2:n] {
    sum = sprintf("%s+back%d", sum, i)
}
sum = sum.")"
# uncomment the next line for a check
# print sum
# define the functions like in the gnuplot demo
# use macro expansion for turning the strings into real functions
samples(x) = $0 > (n-1) ? n : ($0+1)
avg_n(x) = (shift_n(x), @sum/samples($0))
shift_n(x) = @shift

##############################################################################
set label 1 sprintf("%'.f€", Y_min) center at first X_min,Y_min point pt 7 ps 1 offset 0,-1
set label 2 sprintf("%'.f€", Y_max) center at first X_max,Y_max point pt 7 ps 1 offset 0,0.5
plot today title sprintf("%.1f%% belowMax, %.1f%% aboveMin,", belowMax, aboveMin) with lines dashtype 2 lw 0 lc rgb "white", \
     today title sprintf("today %'.f€", today) with lines dashtype 2 lw 1 lc rgb "black", \
     prices using 1:3 title sprintf("Investment %'.f€", invest) with lines lw 2 lc rgb "red", \
     prices using 1:2 notitle lw 1 lc "blue" with lines, \
     prices using 1:(avg_n($2)) title sprintf("%d days average",n) lw 3 lc "dark-red" with lines
