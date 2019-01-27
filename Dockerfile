# Dockerfile to build a Phabricator container that demonstrates git hanging
# when cloning from Phabricator over SSH (see
# https://discourse.phabricator-community.org/t/sporadic-git-cloning-hang-over-ssh/2233
# for details)
#
# https://github.com/sitsofe/phabricator-clone-hang

FROM ubuntu:18.04

ARG DEBIAN_FRONTEND=noninteractive
ARG DEBCONF_NONINTERACTIVE_SEEN=true

RUN apt-get update && apt-get install -y \
    apache2 \
    git \
    libapache2-mod-php \
    mysql-client \
    openssh-server \
    php \
    php-apcu \
    php-curl \
    php-gd \
    php-json \
    php-ldap \
    php-mbstring \
    php-mysql \
    python-pygments \
    sudo \
    \
    gdb \
    jq \
    ltrace \
    strace \
    vim-tiny \
    \
    && \
    rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb \
        /var/cache/apt/*.bin || true

# Grab the latest stable version of Phabricator and its dependencies
RUN cd /opt && \
    git clone --depth 1 --single-branch --branch stable https://github.com/phacility/libphutil.git && \
    git clone --depth 1 --single-branch --branch stable https://github.com/phacility/arcanist.git && \
    git clone --depth 1 --single-branch --branch stable https://github.com/phacility/phabricator.git

# Do configuration for Phabricator
RUN mkdir -p /var/tmp/phd && \
    mkdir -p /var/repo && \
    mkdir -p /usr/local/lib/phabricator && \
    cp /opt/phabricator/resources/sshd/phabricator-ssh-hook.sh \
        /usr/local/lib/phabricator && \
    sed -i -e 's/vcs-user/git/g' -e 's|/path/to/phabricator|/opt/phabricator|g' \
        /usr/local/lib/phabricator/phabricator-ssh-hook.sh && \
    sed -i -e 's/;opcache.validate_timestamps=1/opcache.validate_timestamps=0/' \
           -e 's/post_max_size = 8M/post_max_size = 32M/' \
           -e 's/;mysqli.allow_local_infile = On/mysqli.allow_local_infile = 0/' \
        /etc/php/7.2/apache2/php.ini

# Do configuration for Apache
RUN a2enmod rewrite && \
    printf "\
<VirtualHost *>\n\
  DocumentRoot /opt/phabricator/webroot\n\
  RewriteEngine on\n\
  RewriteRule ^(.*)$          /index.php?__path__=\$1  [B,L,QSA]\n\
</VirtualHost>\n\
\n\
<Directory /opt/phabricator/webroot>\n\
  Require all granted\n\
</Directory>\n" > /etc/apache2/sites-available/phabricator.conf && \
    ln -s ../sites-available/phabricator.conf /etc/apache2/sites-enabled/ && \
    rm -f /etc/apache2/sites-enabled/000-default.conf
ENV APACHE_RUN_USER www-data
ENV APACHE_RUN_GROUP www-data
ENV APACHE_RUN_DIR /var/run/apache2
ENV APACHE_PID_FILE ${APACHE_RUN_DIR}/apache2.pid
ENV APACHE_LOCK_DIR /var/lock/apache2
ENV APACHE_LOG_DIR /var/log/apache2

# Do configuration for the SSH server
RUN useradd -d /var/repo git && \
    usermod -p NP git && \
    echo "git ALL=(root) SETENV: NOPASSWD: /usr/bin/git-upload-pack, /usr/bin/git-receive-pack" >> /etc/sudoers && \
    cp -p /opt/phabricator/resources/sshd/sshd_config.phabricator.example /etc/ssh/sshd_config && \
    sed -i -e 's/vcs-user/git/g' \
           -e 's!/usr/libexec!/usr/local/lib/phabricator!g' \
        /etc/ssh/sshd_config && \
    mkdir -p /run/sshd

# Create SSH key for root user (don't do this in production!)
RUN ssh-keygen -q -N "" -f /root/.ssh/id_rsa

VOLUME /var/repo

WORKDIR /opt/phabricator
ENV PATH="/opt/arcanist/bin:/opt/phabricator/bin:${PATH}"

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s /usr/local/bin/docker-entrypoint.sh /entrypoint.sh # backwards compat
ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 80
CMD ["/bin/bash"]
