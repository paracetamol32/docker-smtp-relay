#!/bin/sh

# G?n?rer les cl?s DKIM si elles n'existent pas
if [ ! -f "/etc/opendkim/keys/${DKIM_SELECTOR}.private" ]; then
    opendkim-genkey -b 2048 -d ${DKIM_DOMAIN} -D /etc/opendkim/keys -s ${DKIM_SELECTOR}
    chown opendkim:opendkim /etc/opendkim/keys/${DKIM_SELECTOR}.private
fi

# Configurer OpenDKIM
cat << EOF > /etc/opendkim.conf
Domain                  ${DKIM_DOMAIN}
KeyFile                 /etc/opendkim/keys/${DKIM_SELECTOR}.private
Selector                ${DKIM_SELECTOR}
Socket                  inet:8891@localhost
EOF

# Afficher la cl? publique DKIM pour l'enregistrement DNS
echo "DKIM Public Key (add this to your DNS records):"
cat /etc/opendkim/keys/${DKIM_SELECTOR}.txt

# D?marrer OpenDKIM
/usr/sbin/opendkim

# Continuer avec l'entrypoint original
exec "$@"