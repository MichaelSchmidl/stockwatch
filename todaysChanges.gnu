# usage: gnuplot -e "DATA_FILE='xxx.csv'" -e "PNG_FILE='xxx.png'" todaysChanges.gnu
# 
# If no DATA_FILE is set by command line option '-e', the default data file will be "todaysChanges.csv"
#
# If no PNG_FILE is set by command line option '-e', the default output file will be "todaysChanges.png"
#
# Created 26.11.2020 M.Schmidl

##############################################################################
# define where the data comes from and where the plot goes to
if (!exists("DATA_FILE")) DATA_FILE='todaysChanges.csv'
if (!exists("PNG_FILE")) PNG_FILE='todaysChanges.png'

##############################################################################
# make some settings
set macros
set fit quiet
set fit logfile '/dev/null'
set style fill transparent solid 0.5 noborder
set datafile separator ","
set format y "%.f%%"

set terminal pngcairo size 800,480
changes="< cat ".DATA_FILE.""
set output PNG_FILE

stats changes using 2 name "Y_" nooutput
stats changes using 3 name "M_" nooutput

set border 0
unset xtics
set ytics nomirror
set grid y
set boxwidth 0.75
plot Y_mean notitle lw 3 lc rgb "dark-red", \
	 0 notitle lc rgb "black", \
     changes using :2 with boxes lc rgb "black" notitle,\
     '' using 0:2:1 with labels left offset 0,0 rotate notitle

set format y "%.f€"
set output "moneyChanges.png"
plot M_sum notitle lw 3 lc rgb "dark-red", \
	 0 notitle lc rgb "black", \
     changes using :3 with boxes lc rgb "black" notitle,\
     '' using 0:3:1 with labels left offset 0,0 rotate notitle
