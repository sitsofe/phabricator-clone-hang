FROM centos:7

RUN yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
RUN yum install -y \
    git \
    httpd \
    jq \
    openssh-server \
    postfix \
    php \
    php-gd \
    php-ldap \
    php-mbstring \
    php-mysql \
    python2-pygments2 \
    sudo \
    which \
    \
    gcc \
    httpd-devel \
    make \
    php-devel \
    php-pear \
    \
    gdb \
    ltrace \
    strace

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
    sed -i -e 's/post_max_size = 8M/post_max_size = 32M/' \
        /etc/php.ini

#    sed -i -e 's/;opcache.validate_timestamps=1/opcache.validate_timestamps=0/' \

# Configure Apache
RUN echo -e "\
<VirtualHost *>\n\
  DocumentRoot /opt/phabricator/webroot\n\
  RewriteEngine on\n\
  RewriteRule ^(.*)$          /index.php?__path__=\$1  [B,L,QSA]\n\
</VirtualHost>\n\
\n\
<Directory /opt/phabricator/webroot>\n\
  Require all granted\n\
</Directory>" > /etc/httpd/conf.d/phabricator.conf && \
    rm -f /etc/httpd/conf.d/welcome.conf

ENV APACHE_RUN_USER www-data
ENV APACHE_RUN_GROUP www-data
ENV APACHE_RUN_DIR /var/run/httpd
ENV APACHE_PID_FILE ${APACHE_RUN_DIR}/apache2.pid
ENV APACHE_LOCK_DIR /var/lock/httpd
ENV APACHE_LOG_DIR /var/log/httpd

# Configure the SSH server
RUN  useradd -d /var/repo git && \
     usermod -p NP git && \
     echo "git ALL=(root) SETENV: NOPASSWD: /usr/bin/git-upload-pack, /usr/bin/git-receive-pack" >> /etc/sudoers && \
     cp -p /opt/phabricator/resources/sshd/sshd_config.phabricator.example /etc/ssh/sshd_config && \
     sed -i -e 's/vcs-user/git/g' -e 's!/usr/libexec!/usr/local/lib/phabricator!g' /etc/ssh/sshd_config && \
     mkdir -p /run/sshd && \
     /usr/sbin/sshd-keygen

# Build and configure APC
RUN pecl config-set php_ini /etc/php.ini && \
    pear config-set php_ini /etc/php.ini && \
    yes '' | pecl install apc && \
    echo -e "\
apc.write_lock=1\n\
apc.slam_defense=0\n\
apc.stat=0" >> /etc/php.ini

# Create fixed root SSH key (don't do this in production!)
RUN ssh-keygen -q -N "" -f /root/.ssh/id_rsa

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s /usr/local/bin/docker-entrypoint.sh /entrypoint.sh # backwards compat

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/bin/bash"]

WORKDIR /opt/phabricator
ENV PATH="/opt/arcanist/bin:/opt/phabricator/bin:$PATH"
VOLUME /var/repo

EXPOSE 80
