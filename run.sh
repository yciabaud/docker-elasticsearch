#!/bin/bash

BASE=/elasticsearch

# allow for memlock if enabled
if [ "$MEMORY_LOCK" == "true" ]; then
    ulimit -l unlimited
fi

# Set a random node name if not set.
if [ -z "${NODE_NAME}" ]; then
	NODE_NAME=$(uuidgen)
fi
export NODE_NAME=${NODE_NAME}

# Create a temporary folder for Elastic Search ourselves.
# Ref: https://github.com/elastic/elasticsearch/pull/27659
export ES_TMPDIR=`mktemp -d -t elasticsearch.XXXXXXXX`

# Prevent "Text file busy" errors
sync

if [ ! -z "${ES_PLUGINS_INSTALL}" ]; then
   OLDIFS=$IFS
   IFS=','
   for plugin in ${ES_PLUGINS_INSTALL}; do
      if ! $BASE/bin/elasticsearch-plugin list | grep -qs ${plugin}; then
         until $BASE/bin/elasticsearch-plugin install --batch ${plugin}; do
           echo "failed to install ${plugin}, retrying in 3s"
           sleep 3
         done
      fi
   done
   IFS=$OLDIFS
fi

if [ ! -z "${SHARD_ALLOCATION_AWARENESS_ATTR}" ]; then
    # this will map to a file like  /etc/hostname => /dockerhostname so reading that file will get the
    #  container hostname
    if [ "$NODE_DATA" == "true" ]; then
        ES_SHARD_ATTR=`cat ${SHARD_ALLOCATION_AWARENESS_ATTR}`
        NODE_NAME="${ES_SHARD_ATTR}-${NODE_NAME}"
        echo "node.attr.${SHARD_ALLOCATION_AWARENESS}: ${ES_SHARD_ATTR}" >> $BASE/config/elasticsearch.yml
    fi
    if [ "$NODE_MASTER" == "true" ]; then
        echo "cluster.routing.allocation.awareness.attributes: ${SHARD_ALLOCATION_AWARENESS}" >> $BASE/config/elasticsearch.yml
    fi
fi

for item in ${!ES_CONFIG_*}; do
    value=${!item}
    item=${item##ES_CONFIG_}   # Strip away prefix
    item=${item,,}             # Lowercase
    item=${item//__/.}         # Replace double underscore with dot
    echo "${item}: ${value}" >> $BASE/config/elasticsearch.yml
done

# run
if [[ $(whoami) == "root" ]]; then
    chown -R elasticsearch:elasticsearch $BASE
    chown -R elasticsearch:elasticsearch /data

    for item in ${!ES_KEYSTORE_*}; do
        value=${!item}
        item=${item##ES_KEYSTORE_} # Strip away prefix
        item=${item,,}             # Lowercase
        item=${item//__/.}         # Replace double underscore with dot

	if [ ! -f  $BASE/config/elasticsearch.keystore ]; then
            su-exec elasticsearch $BASE/bin/elasticsearch-keystore create
	fi
    	su-exec elasticsearch $BASE/bin/elasticsearch-keystore add -x $item <<< ${value}
    done

    exec su-exec elasticsearch $BASE/bin/elasticsearch $ES_EXTRA_ARGS
else
    # the container's first process is not running as 'root', 
    # it does not have the rights to chown. however, we may
    # assume that it is being ran as 'elasticsearch', and that
    # the volumes already have the right permissions. this is
    # the case for kubernetes for example, when 'runAsUser: 1000'
    # and 'fsGroup:100' are defined in the pod's security context.
    for item in ${!ES_KEYSTORE_*}; do
        value=${!item}
        item=${item##ES_KEYSTORE_} # Strip away prefix
        item=${item,,}             # Lowercase
        item=${item//__/.}         # Replace double underscore with dot

	if [ ! -f  $BASE/config/elasticsearch.keystore ]; then
            su-exec elasticsearch $BASE/bin/elasticsearch-keystore create
	fi
    	$BASE/bin/elasticsearch-keystore add -x $item <<< ${value}
    done
    $BASE/bin/elasticsearch $ES_EXTRA_ARGS
fi
