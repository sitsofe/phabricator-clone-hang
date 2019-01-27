#!/bin/bash

# Ensure the hostname is all in lowercase
SERVER_FQDN="$(echo "${SERVER_FQDN}" | tr '[:upper:]' '[:lower:]')"
echo "ServerName ${SERVER_FQDN}" > /etc/apache2/conf-enabled/servername.conf

/opt/phabricator/bin/config set diffusion.ssh-port 2222
/opt/phabricator/bin/config set diffusion.ssh-user git
/opt/phabricator/bin/config set mysql.host mysql-phabricator
/opt/phabricator/bin/config set mysql.pass githang
/opt/phabricator/bin/config set phd.user root
/opt/phabricator/bin/config set phabricator.base-uri "http://${SERVER_FQDN}/"

# Reduce Phabricator setup issues
/opt/phabricator/bin/config set phabricator.timezone UTC
/opt/phabricator/bin/config set pygments.enabled true

/opt/phabricator/bin/storage upgrade --force || exit

/opt/phabricator/bin/phd start
/opt/phabricator/bin/phd launch 8 PhabricatorTaskmasterDaemon
apachectl start

# Force the FQDN into hosts to workaround crazy things like the DNS servers
# being used being Google's anycast ones...
echo "127.0.0.1 ${SERVER_FQDN}" >> /etc/hosts

echo "Press enter to continue after Phabricator been configured via its web "
echo -n "interface on http://${SERVER_FQDN}/ :"
read -r

# Show the user the public part of the root user's SSH key
echo "Copy the following into a public SSH key for your user:"
echo "--- ✂  cut here ✂ ---"
cat /root/.ssh/id_rsa.pub
echo "--- ✂  cut here ✂ ---"

echo "Press enter to continue after key has been copied to "
echo -n "http://${SERVER_FQDN}/settings/user/<user>/page/ssh/ :"
read -r

# Configure arcanist
/opt/arcanist/bin/arc set-config default "http://${SERVER_FQDN}"
# Switch directory (otherwise the default conduit-uri won't be picked up)
cd /dev/shm
/opt/arcanist/bin/arc install-certificate

# Create repository in Phabricator
echo '{"transactions": [{"type":"vcs", "value": "git"},
          {"type":"name", "value":"libphutil"},
          {"type":"publish", "value":false },
          {"type":"autoclose", "value":false },
          {"type":"callsign", "value":"LIBPHUTIL"}]
      }' | /opt/arcanist/bin/arc call-conduit 'diffusion.repository.edit'
# Grab PHID for repo
REPO_PHID="$(echo '{ "names": [ "rLIBPHUTIL" ] }' | \
    arc call-conduit phid.lookup | jq -r '.response | .rLIBPHUTIL.phid')"
# Set all the existing repo URIs to read-only
URI_PHIDS="$(echo '{ "constraints": { "phids": [ "'"${REPO_PHID}"'" ] },
    "attachments": { "uris": true } }' | \
    arc call-conduit diffusion.repository.search | \
    jq -r '.response.data[0].attachments.uris.uris[].phid')"
for phid in ${URI_PHIDS}; do
    echo '{ "transactions": [ { "type": "io", "value": "read" } ],
        "objectIdentifier": "'"${phid}"'" }' | \
    arc call-conduit diffusion.uri.edit
done
# Add upstream URI (to import from)
echo '{ "transactions": [
    { "type": "repository", "value": "'"${REPO_PHID}"'" },
    { "type": "uri", "value": "https://secure.phabricator.com/source/libphutil.git" },
    { "type": "io", "value": "observe" }
  ]
}' | arc call-conduit diffusion.uri.edit
# Activate the repo (and start the import process)
echo '{
  "transactions": [ { "type": "status", "value": "active" } ],
  "objectIdentifier": "'"${REPO_PHID}"'"
}' | arc call-conduit diffusion.repository.edit

# Wait for the import to finish
echo "Waiting for libphutil import (this may take a while)..."
echo -n "(monitor progress via http://${SERVER_FQDN}/diffusion/LIBPHUTIL/ ):  "
sp="/-\\|"
while true; do
    # Check import state
    IMPORTING=$(echo '{ "constraints": { "callsigns": [ "LIBPHUTIL" ] }
    }' | arc call-conduit diffusion.repository.search | jq  -r '.response.data[0].fields.isImporting')
    if [[ "$IMPORTING" == "true" ]]; then
        printf "\b${sp:i++%${#sp}:1}"
        sleep 3;
    else
        break
    fi
done
printf '    \b\b\b\b\n'
echo 'Import complete!'

/usr/sbin/sshd
ssh-keygen -R localhost
ssh-keygen -R 127.0.0.1
ssh-keyscan -H -p 2222 localhost >> ~/.ssh/known_hosts

# Repeatedly clone the repo
mkdir /dev/shm/gitclonehang
cd /dev/shm/gitclonehang
START_DATE="$(date)"
count=0
rc=0
while [[ rc -eq 0 ]]; do
    count=$((count + 1))
    echo "$(date) Clone count: ${count}"
    rm -rf libphutil/
    git clone ssh://git@localhost:2222/diffusion/LIBPHUTIL/libphutil.git
    rc=$?
done
echo "Started : ${START_DATE}"
echo "Finished: $(date)"

exec "$@"
