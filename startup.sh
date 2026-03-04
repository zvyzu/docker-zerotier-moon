#!/bin/sh

# export PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin

# if [ ! -e /dev/net/tun ]; then
#     echo 'FATAL: cannot start ZeroTier One in container: /dev/net/tun not present.'
#     exit 1
# fi

# usage ./startup.sh -4 1.2.3.4 -6 2001:abcd:abcd::1 -p 9993
# or via environment variables: ZT_IPV4, ZT_IPV6, ZT_PORT
moon_port=${ZT_PORT:-9993} # default ZeroTier moon port, env fallback

# Read from env first (if set)
if [ -n "$ZT_IPV4" ]; then
        ipv4_address="$ZT_IPV4"
fi
if [ -n "$ZT_IPV6" ]; then
        ipv6_address="$ZT_IPV6"
fi

while getopts "4:6:p:" arg # handle args (CLI args override env)
do
        case $arg in
             4)
                ipv4_address="$OPTARG"
                ;;
             6)
                ipv6_address="$OPTARG"
                ;;
             p)
                moon_port="$OPTARG"
                ;;
             ?)
            echo "unknown argument"
        exit 1
        ;;
        esac
done

# Print resolved values
[ -n "$ipv4_address" ] && echo "IPv4 address: $ipv4_address"
[ -n "$ipv6_address" ] && echo "IPv6 address: $ipv6_address"
echo "Moon port: $moon_port"

echo "Setting up ZeroTier moon..."

stableEndpointsForSed=""
if [ -z ${ipv4_address+x} ]
then # ipv4 address is not set
        if [ -z ${ipv6_address+x} ]
        then # ipv6 address is not set
                echo "Please set IPv4 address or IPv6 address."
                exit 0
        else # ipv6 address is set
                stableEndpointsForSed="\"$ipv6_address\/$moon_port\""
        fi
else # ipv4 address is set
        if [ -z ${ipv6_address+x} ]
        then # ipv6 address is not set
                stableEndpointsForSed="\"$ipv4_address\/$moon_port\""
        else # ipv6 address is set
                stableEndpointsForSed="\"$ipv4_address\/$moon_port\",\"$ipv6_address\/$moon_port\""
        fi
fi

echo "Endpoints config: $stableEndpointsForSed"

if [ -d "/var/lib/zerotier-one/moons.d" ] # check if the moons conf has generated
then
        echo "Found existing moon configuration"
        moon_id=$(cat /var/lib/zerotier-one/identity.public | cut -d ':' -f1)
        printf "Your ZeroTier moon id is \033[0;31m$moon_id\033[0m, you could orbit moon using \033[0;31m\"zerotier-cli orbit $moon_id $moon_id\"\033[0m"
        exec /usr/sbin/zerotier-one
else
        echo "Starting ZeroTier service to generate identity..."
        nohup /usr/sbin/zerotier-one >/dev/null 2>&1 &
        ZT_PID=$!

        echo "Waiting for identity generation..."
        MAX_WAIT=30
        COUNT=0
        while [ ! -f /var/lib/zerotier-one/identity.secret ]; do
            sleep 1
            COUNT=$((COUNT+1))
            if [ $COUNT -ge $MAX_WAIT ]; then
                echo "ERROR: Timed out waiting for identity.secret file"
                ps aux | grep zerotier
                if kill -0 $ZT_PID 2>/dev/null; then
                    echo "ZeroTier still running but not generating identity"
                else
                    echo "ZeroTier process died. Check for errors"
                fi
                exit 1
            fi
            echo "Waiting... ($COUNT/$MAX_WAIT)"
        done
        echo "Identity generated successfully"

        echo "Creating moon configuration..."
        /usr/sbin/zerotier-idtool initmoon /var/lib/zerotier-one/identity.public >>/var/lib/zerotier-one/moon.json
        sed -i 's/"stableEndpoints": \[\]/"stableEndpoints": ['$stableEndpointsForSed']/g' /var/lib/zerotier-one/moon.json

        echo "Generating moon..."
        /usr/sbin/zerotier-idtool genmoon /var/lib/zerotier-one/moon.json > /dev/null
        mkdir -p /var/lib/zerotier-one/moons.d
        mv *.moon /var/lib/zerotier-one/moons.d/

        echo "Stopping temporary ZeroTier instance..."
        pkill zerotier-one

        echo "Starting ZeroTier with moon configuration..."
        moon_id=$(cat /var/lib/zerotier-one/moon.json | grep \"id\" | cut -d '"' -f4)
        echo -e "Your ZeroTier moon id is \033[0;31m$moon_id\033[0m, you could orbit moon using \033[0;31m\"zerotier-cli orbit $moon_id $moon_id\"\033[0m"
        printf "Your ZeroTier moon id is \033[0;31m$moon_id\033[0m, you could orbit moon using \033[0;31m\"zerotier-cli orbit $moon_id $moon_id\"\033[0m"

        exec /usr/sbin/zerotier-one
fi
