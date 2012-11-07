#! /bin/bash

# cloudfiles.sh
#
# Provides simple command-line access to Cloud Files.
#
# Relies on curl and a few common Unix-y tools (file, basename, sed, tr)
#
# Written by Mike Barton (mike@weirdlooking.com), based on work by letterj.

auth_url="https://auth.api.rackspacecloud.com/v1.0"
me=`basename $0`

function usage {
  echo "Usage:    $0 [-e] [-u <auth url>] [<Username> <API Key>] <command> [<arguments> ...]" >&2
  echo "Commands: LS [<container>]" >&2
  echo "          PUT <container> <local file>" >&2
  echo "          GET </container/object> [<local file>]" >&2
  echo "          MKDIR </container>" >&2
  echo "          RM </container/object>" >&2
  echo "          RMDIR </container>" >&2
  echo "Options:  -e  use CLOUDFILES_USERNAME and CLOUDFILES_API_KEY" >&2
  echo "              environment variables instead of the command line" >&2
  echo "              (so that they won't show up in a process listing)" >&2
  echo "          -u  specify authentication url" >&2
  echo "              (default: $auth_url)" >&2
  echo "          -s  silent operation (apart from errors)" >&2
  exit 1
}

function scurl {
  curl -s -g -w '%{http_code}' -H Expect: -H "X-Auth-Token: $TOKEN" -X "$@"
}

function authenticate {
  LOGIN=`curl --dump-header - -s -H "X-Auth-User: $CLOUDFILES_USERNAME" \
         -H "X-Auth-Key: $CLOUDFILES_API_KEY" $auth_url`
  TOKEN=`echo "$LOGIN" | grep ^X-Auth-Token | sed 's/.*: //' | tr -d "\r\n"`
  URL=`echo "$LOGIN" | grep ^X-Storage-Url | sed 's/.*: //' | tr -d "\r\n"`
  if [ -z $TOKEN ] || [ -z $URL ]; then
    echo "$0: authentication failed" >&2
    exit 4
  fi
}

while getopts eu: opt; do
  case $opt in
    e)
      opt_e=1
    ;;
    s)
      opt_s=1
    ;;
    u)
      auth_url=$OPTARG
    ;;
    *)
      usage
    ;;
  esac
done

shift $(($OPTIND - 1))

if [ ! "$opt_e" ]; then
  CLOUDFILES_USERNAME=$1; shift
  CLOUDFILES_API_KEY=$1; shift
fi

if [ ! "$CLOUDFILES_USERNAME" -o ! "$CLOUDFILES_API_KEY" ]; then
  echo "$0: username and/or API key not specified" >&2
  usage
fi


cmd=$1; shift

case $cmd in
  LS)
    authenticate
    if [ -z "$1" ]; then
      curl -s -o - -H "Expect:" -H "X-Auth-Token: $TOKEN" "$URL"
    else
      curl -s -o - -H "Expect:" -H "X-Auth-Token: $TOKEN" "$URL/$1"
    fi
    exit
    ;;
  GET)
    [ ! "$1" ] && usage
    authenticate
    if [ "$2" ]; then
      output_file=$2
    else
      output_file=`basename "$1"`
    fi
    tmp="$output_file.$me.$$.part"
    result=`scurl GET "$URL$1" -o "$tmp"`
    if [ "$result" -eq "200" ]; then
      mv $tmp $output_file
    else
      rm $tmp
    fi
    ;;
  PUT)
    if [ ! "$2" ]; then
      usage
    elif [ ! -r "$2" ]; then
      echo "$0: can't open $2 for reading" >&2
      exit 1
    fi
    authenticate
    TYPE=`file -bi "$2"`
    OBJNAME=`basename "$2"`
    result=`scurl PUT -H "Content-Type: $TYPE" -T "$2" "$URL/$1/$OBJNAME"`
    ;;
  MKDIR)
    [ ! "$1" ] && usage
    authenticate
    result=`scurl PUT -T /dev/null "$URL/$1"`
    ;;
  RM*)
    [ ! "$1" ] && usage
    authenticate
    target="`echo $1 | sed -e 's/^\///'`"
    result=`scurl DELETE "$URL/$target"`
    ;;
  *)
    usage
esac

if [ "$result" != 200 ]; then
  echo "$0: failed with status code $result" >&2
  exit 1
fi

exit 0

