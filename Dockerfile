FROM debian:8

ARG DEBIAN_FRONTEND=noninteractive
ARG DEBCONF_NONINTERACTIVE_SEEN=true

RUN apt-get update && apt-get install -y \
    apache2 \
    curl \
    gdb \
    git \
    jq \
    libapache2-mod-php5 \
    libmysqlclient18 \
    openssh-server \
    php5 \
    php5-apcu \
    php5-cli \
    php5-curl \
    php5-gd \
    php5-json \
    php5-ldap \
    php5-mysql \
    python-pygments \
    sudo \
    vim-tiny && \
    \
    rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb \
        /var/cache/apt/*.bin || true

# Grab 2016-07-23 version of Phabricator et al. and set up directories
RUN cd /opt && \
     git clone --single-branch --branch stable https://github.com/phacility/libphutil.git && \
     git clone --single-branch --branch stable https://github.com/phacility/arcanist.git && \
     git clone --single-branch --branch stable https://github.com/phacility/phabricator.git
RUN cd /opt/libphutil && git checkout 5fd2cf9d5d && \
    cd /opt/arcanist && git checkout f1c45a3323 && \
    cd /opt/phabricator && git checkout 9da15fd7ab && \
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
        /etc/php5/apache2/php.ini

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
     mkdir -p /run/sshd && \
     chmod -R g-w /usr/local

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
