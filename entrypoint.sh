#!/bin/bash

trap "echo SIGINT; exit" SIGINT
trap "echo SIGTERM; exit" SIGTERM

if [ -z "$CF_TOKEN" ]; then
    echo "CF_TOKEN environment variable not set!"
    exit 1;
fi

if [ -z "$EMAIL" ]; then
    echo "EMAIL environment variable not set!"
    exit 1;
fi

if [ -z "$DOMAIN" ]; then
    echo "DOMAIN environment variable not set!"
    exit 1;
fi

if [ -z "$SSHTARGET" ]; then
    echo "SSHTARGET environment variable not set!"
    exit 1;
fi

if [ ! -f "/opt/identity/ssh_id" ]; then
    echo "/opt/identity/ssh_id file does not exist.  Please mount your SSH private key."
    exit 1;
fi

if [ ! $(stat -L -c "%a" /opt/identity/ssh_id) = "600" ]; then
    echo "/opt/identity/ssh_id must have '600' permissions."
    exit 1;
fi

if [ ! -d "/opt/esxi" ]; then
    echo "** WARNING: No /opt/esxi directory.  This is ok but backup certificates will not be preserved."
    mkdir -p /opt/esxi
fi

echo "dns_cloudflare_api_token = \"$CF_TOKEN\"" > /opt/cf_token
chmod 400 /opt/cf_token
SERVER_URL="https://acme-v02.api.letsencrypt.org/directory"
if [ ! -z "$STAGING" ]; then
    echo "** Using Lets Encrypt Staging server **"
    SERVER_URL="https://acme-staging-v02.api.letsencrypt.org/directory"
fi

while [ -z "$ONCE" ]; do
    if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
        OLDMD5=($(md5sum /etc/letsencrypt/live/$DOMAIN/fullchain.pem))
        echo "Renewing certificate on $DOMAIN"
        certbot renew --non-interactive --no-self-upgrade --dns-cloudflare \
            --dns-cloudflare-credentials /opt/cf_token --agree-tos --email $EMAIL --server $SERVER_URL
        NEWMD5=($(md5sum /etc/letsencrypt/live/$DOMAIN/fullchain.pem))
        [ "$OLDMD5" != "$NEWMD5" ] && UPDATE_SYSTEM=1
    else
        echo "Creating certificate on $DOMAIN"
        certbot certonly --non-interactive --dns-cloudflare \
            --dns-cloudflare-credentials /opt/cf_token --agree-tos --email $EMAIL -d $DOMAIN --server $SERVER_URL
        UPDATE_SYSTEM=1
    fi

    if [ ! -z "$UPDATE_SYSTEM" ]; then
        echo "Backing up current certificates..."
        D=$(date +%Y%m%d-%H%M%S)
        OPTS="-i /opt/identity/ssh_id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
        scp $OPTS $SSHTARGET:/etc/vmware/ssl/rui.crt /etc/esxi/rui.crt.$D
        scp $OPTS $SSHTARGET:/etc/vmware/ssl/rui.key /etc/esxi/rui.key.$D

        echo "Updating system with new certificate."
        scp $OPTS /etc/letsencrypt/live/$DOMAIN/fullchain.pem $SSHTARGET:/etc/vmware/ssl/rui.crt
        scp $OPTS /etc/letsencrypt/live/$DOMAIN/privkey.pem $SSHTARGET:/etc/vmware/ssl/rui.key
        echo "Rebooting.  If web doesn't come back, reset with /sbin/generate-certificates && reboot"
        ssh $OPTS $SSHTARGET reboot
    fi

    if [ -z "$ONCE"]; then
        echo "Sleeping for one day..."
        sleep 1d
    fi
done
