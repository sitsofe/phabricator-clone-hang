FROM ubuntu:18.04

ARG DEBIAN_FRONTEND=noninteractive
ARG DEBCONF_NONINTERACTIVE_SEEN=true

RUN apt-get update && apt-get install -y \
    software-properties-common

RUN add-apt-repository ppa:ondrej/php

RUN apt-get update && apt-get install -y \
    apache2 \
    curl \
    gdb \
    git \
    jq \
    libapache2-mod-php5.6 \
    libmysqlclient20 \
    openssh-server \
    php-apcu \
    php5.6 \
    php5.6-apcu \
    php5.6-cli \
    php5.6-curl \
    php5.6-gd \
    php5.6-json \
    php5.6-ldap \
    php5.6-mbstring \
    php5.6-mysql \
    python-pygments \
    sudo \
    vim-tiny && \
    \
    rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb \
        /var/cache/apt/*.bin || true

# Grab 2017 Week 12 stable version of Phabricator and set up directories
RUN cd /opt && \
    git clone --single-branch --branch stable https://github.com/phacility/libphutil.git && \
    git clone --single-branch --branch stable https://github.com/phacility/arcanist.git && \
    git clone --single-branch --branch stable https://github.com/phacility/phabricator.git
RUN cd /opt/libphutil && git checkout 75da31a282223f3ea2e480c06c8e0cce4799ef96 && \
    cd /opt/arcanist && git checkout 6f1e2d80553a818d6b6d9a92b1f00d4f739113f3 && \
    cd /opt/phabricator && git checkout 60aaee0ed3f5a1e4384ac7d7f2efd2c64cecbe44 && \
    cd /opt

# Set up Phabricator
RUN mkdir -p /var/tmp/phd && \
    mkdir -p /var/repo && \
    mkdir -p /usr/local/lib/phabricator && \
    cp /opt/phabricator/resources/sshd/phabricator-ssh-hook.sh \
        /usr/local/lib/phabricator && \
    sed -i -e 's/vcs-user/git/g' -e 's|/path/to/phabricator|/opt/phabricator|g' \
        /usr/local/lib/phabricator/phabricator-ssh-hook.sh && \
    sed -i -e 's/;opcache.validate_timestamps=1/opcache.validate_timestamps=0/' \
           -e 's/post_max_size = 8M/post_max_size = 32M/' \
        /etc/php/5.6/apache2/php.ini

# Configure Apache
RUN a2enmod rewrite && \
    echo "\
<VirtualHost *>\n\
  DocumentRoot /opt/phabricator/webroot\n\
  RewriteEngine on\n\
  RewriteRule ^(.*)$          /index.php?__path__=\$1  [B,L,QSA]\n\
</VirtualHost>\n\
\n\
<Directory /opt/phabricator/webroot>\n\
  Require all granted\n\
</Directory>" > /etc/apache2/sites-available/phabricator.conf && \
    ln -s ../sites-available/phabricator.conf /etc/apache2/sites-enabled/ && \
    rm -f /etc/apache2/sites-enabled/000-default.conf
ENV APACHE_RUN_USER www-data
ENV APACHE_RUN_GROUP www-data
ENV APACHE_RUN_DIR /var/run/apache2
ENV APACHE_PID_FILE ${APACHE_RUN_DIR}/apache2.pid
ENV APACHE_LOCK_DIR /var/lock/apache2
ENV APACHE_LOG_DIR /var/log/apache2

# Set up SSH server
RUN  useradd -d /var/repo git && \
     usermod -p NP git && \
     echo "git ALL=(root) SETENV: NOPASSWD: /usr/bin/git-upload-pack, /usr/bin/git-receive-pack" >> /etc/sudoers && \
     cp -p /opt/phabricator/resources/sshd/sshd_config.phabricator.example /etc/ssh/sshd_config && \
     sed -i -e 's/vcs-user/git/g' -e 's!/usr/libexec!/usr/local/lib/phabricator!g' /etc/ssh/sshd_config && \
     mkdir -p /run/sshd

# Create SSH key
RUN ssh-keygen -q -N "" -f /root/.ssh/id_rsa

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s /usr/local/bin/docker-entrypoint.sh /entrypoint.sh # backwards compat

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/bin/bash"]

WORKDIR /opt/phabricator
ENV PATH="/opt/arcanist/bin:/opt/phabricator/bin:$PATH"
VOLUME /var/repo

EXPOSE 80
