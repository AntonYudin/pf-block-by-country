
BLOCK_COUNTRIES="\(CN\|RU\|IR\)"
APNIC_LATEST="https://ftp.apnic.net/stats/apnic/delegated-apnic-latest"
RIPE_INETNUM="https://ftp.ripe.net/ripe/dbase/split/ripe.db.inetnum.gz"

pfctl -t blocked-networks -T flush

IFS="|"


if [ "X$APNIC_LATEST" != "X" ]; then

	if ! [ -f "delegated-apnic-latest" ]; then
		echo "fetching APNIC ..."
		fetch "$APNIC_LATEST"
	fi

	echo "processing APNIC ..."

	cat delegated-apnic-latest |							\
		grep "^apnic|$BLOCK_COUNTRIES|ipv4|[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}|[0-9]\{1,10\}|.*$" | \
		grep -v '^apnic|.*|ipv4|127\.*' |					\
		grep -v '^apnic|.*|ipv4|10\..*' |					\
		grep -v '^apnic|.*|ipv4|192\.168\..*' |					\
		while read SOURCE COUNTRY VERSION NETWORK SIZE DATE STATUS; do
		MASK=$(echo "scale=0; 32 - l2($SIZE)" | bc -l)
		echo "$NETWORK/$MASK"
	done | xargs -n 1000 pfctl -t blocked-networks -T add
fi

if [ "X$RIPE_INETNUM" != "X" ]; then

	if ! [ -f "ripe.db.inetnum.gz" ]; then
		echo "fetching RIPE ..."
		fetch "$RIPE_INETNUM"
	fi

	echo "processing RIPE ..."
	
	AWK_CODE='BEGIN { print "scale=0;" }
		/^inetnum:/ {
			NETWORK0=$2; NETWORK1=$3; NETWORK2=$4; NETWORK3=$5
			NETWORK4=$6; NETWORK5=$7; NETWORK6=$8; NETWORK7=$9
		}
		/^country:.*$/ {
			gsub(/ /, "", NETWORK3)
			printf "print \"" NETWORK0 "." NETWORK1 "." NETWORK2 "." NETWORK3 "/\";";
			#printf "print \"" NETWORK4 "_" NETWORK5 "_" NETWORK6 "_" NETWORK7 "/\";";
			printf "32 - l2((" NETWORK4 "*256*256*256+" NETWORK5 "*256*256+" NETWORK6 "*256+" NETWORK7 ")-";
			printf "(" NETWORK0 "*256*256*256+" NETWORK1 "*256*256+" NETWORK2 "*256+" NETWORK3 ") + 1);";
			printf "\n"
		}
	'

	gzcat ripe.db.inetnum.gz |					\
		grep	-e '^inetnum:[ ]*[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\} - [0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$' \
			-e "^country:.*$BLOCK_COUNTRIES$" |		\
		grep -v '^inetnum:[ ]*127\.*' |				\
		grep -v '^inetnum:[ ]*10\..*' |				\
		grep -v '^inetnum:[ ]*192\.168\..*' |			\
		awk -F '[.:-]' $AWK_CODE | 				\
		bc -l |							\
		xargs -n 1000 pfctl -t blocked-networks -T add

fi

