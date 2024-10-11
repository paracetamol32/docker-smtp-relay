FROM alpine:3.11
LABEL maintainer='Pierre GINDRAUD <pgindraud@gmail.com>'
ARG POSTFIX_VERSION
ARG RSYSLOG_VERSION

ENV RELAY_MYDOMAIN=domain.com
ENV RELAY_MYNETWORKS=127.0.0.0/8
ENV RELAY_HOST=[127.0.0.1]:25
ENV RELAY_USE_TLS=yes
ENV RELAY_TLS_VERIFY=may
ENV RELAY_DOMAINS=\$mydomain
ENV RELAY_STRICT_SENDER_MYDOMAIN=true
ENV RELAY_MODE=STRICT
ENV RELAY_TLS_CA /etc/ssl/certs/ca-certificates.crt
#ENV RELAY_MYHOSTNAME=relay.domain.com
#ENV RELAY_POSTMASTER=postmaster@domain.com
#ENV RELAY_LOGIN=loginname
#ENV RELAY_PASSWORD=xxxxxxxx
#ENV RELAY_EXTRAS_SETTINGS
ENV POSTCONF_inet_interfaces all
ENV POSTCONF_inet_protocols ipv4

# Ajout de variables d'environnement pour DKIM
ENV DKIM_SELECTOR=default
ENV DKIM_DOMAIN=example.com

# Install dependencies
RUN apk --no-cache add \
    cyrus-sasl \
    cyrus-sasl-crammd5 \
    cyrus-sasl-digestmd5 \
    cyrus-sasl-login \
    cyrus-sasl-plain \
    postfix \
    rsyslog \
    supervisor \
    tzdata \
    opendkim \
    opendkim-utils

# Configuration of main.cf
RUN postconf -e 'notify_classes = bounce, 2bounce, data, delay, policy, protocol, resource, software' \
    && postconf -e 'bounce_notice_recipient = $2bounce_notice_recipient' \
    && postconf -e 'delay_notice_recipient = $2bounce_notice_recipient' \
    && postconf -e 'error_notice_recipient = $2bounce_notice_recipient' \
    && postconf -e 'myorigin = $mydomain' \
    && postconf -e 'smtpd_sasl_auth_enable = yes' \
    && postconf -e 'smtpd_sasl_type = cyrus' \
    && postconf -e 'smtpd_sasl_local_domain = $mydomain' \
    && postconf -e 'smtpd_sasl_security_options = noanonymous' \
    && postconf -e 'smtpd_banner = $myhostname ESMTP $mail_name RELAY' \
    && postconf -e 'smtputf8_enable = no' \
    && postconf -e 'smtp_destination_rate_delay = 20s' \
    && postconf -e 'smtp_destination_concurrency_limit = 1' \
    && postconf -e 'smtp_extra_recipient_limit = 10' \
    && postconf -e 'header_checks = regexp:/etc/postfix/header_checks' \
    && postconf -e 'debug_peer_level = 2' \
    && postconf -e 'debug_peer_list = *' \
    && postconf -e 'smtpd_tls_loglevel = 1' \
    && postconf -e 'smtp_tls_loglevel = 1' \
    && postconf -e 'milter_protocol = 2' \
    && postconf -e 'milter_default_action = accept' \
    && postconf -e 'smtpd_milters = inet:localhost:8891' \
    && postconf -e 'non_smtpd_milters = inet:localhost:8891'

# Configuration for OpenDKIM
RUN mkdir -p /etc/opendkim/keys \
    && chown -R opendkim:opendkim /etc/opendkim \
    && echo "SOCKET=\"inet:8891@localhost\"" >> /etc/opendkim/opendkim.conf \
    && echo "SUBDOMAINS=yes" >> /etc/opendkim/opendkim.conf \
    && echo "Domain ${DKIM_DOMAIN}" >> /etc/opendkim/opendkim.conf \
    && echo "KeyFile /etc/opendkim/keys/dkim.private" >> /etc/opendkim/opendkim.conf \
    && echo "Selector ${DKIM_SELECTOR}" >> /etc/opendkim/opendkim.conf

# Modification de la configuration pour le logging du sujet et autres en-têtes
RUN echo "/^.*/ WARN" > /etc/postfix/header_checks \
    && postmap /etc/postfix/header_checks

# Modification de la configuration de rsyslog pour inclure plus de détails dans les logs
RUN sed -i 's/^#\$ModLoad imklog/#$ModLoad imklog\n$template Details,"%syslogtag% %msg%\\n"/' /etc/rsyslog.conf \
    && sed -i 's/^mail.*/mail.* -\/var\/log\/mail.log;Details/' /etc/rsyslog.conf



# Add some configurations files
COPY /root/etc/* /etc/
COPY /root/opt/* /opt/
COPY /docker-entrypoint.sh /
COPY /docker-entrypoint.d/* /docker-entrypoint.d/

# Script pour générer les clés DKIM et configurer OpenDKIM
COPY setup-dkim.sh /usr/local/bin/
RUN chmod -R +x /docker-entrypoint.d/ /usr/local/bin/setup-dkim.sh \
    && touch /etc/postfix/aliases \
    && touch /etc/postfix/sender_canonical \
    && mkdir -p /data

EXPOSE 25/tcp
VOLUME ["/data","/var/spool/postfix"]
WORKDIR /data

HEALTHCHECK --interval=5s --timeout=2s --retries=3 \
    CMD nc -znvw 1 127.0.0.1 25 || exit 1

# Modifier l'ENTRYPOINT pour inclure la configuration DKIM
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "--configuration", "/etc/supervisord.conf"]