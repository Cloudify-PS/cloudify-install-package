#!/bin/bash -e

show_syntax() {
    echo "Syntax: ${SCRIPT_NAME} -i|--private-ip <private_ip> -e|--public-ip <public_ip> -k|--key <key_file> [-u|--user <ssh_user>] [--ssl]" >&2
}

SCRIPT_NAME=$0

set +e
PARSED_CMDLINE=$(getopt -o i:e:u:k:s --long private-ip:,public-ip:,user:,key:,ssl --name "${SCRIPT_NAME}" -- "$@")
set -e

if [[ $? -ne 0 ]]; then
    show_syntax
    exit 1
fi

eval set -- "${PARSED_CMDLINE}"

SSL_ENABLED=false
SSH_USER=$(id -un)

while true ; do
    case "$1" in
        -i|--private-ip)
            PRIVATE_IP="$2"
            shift 2
            ;;
        -e|--public-ip)
            PUBLIC_IP="$2"
            shift 2
            ;;
        -u|--user)
            SSH_USER="$2"
            shift 2
            ;;
        -k|--key)
            SSH_KEY_FILENAME="$2"
            shift 2
            ;;
        -s|--ssl)
            SSL_ENABLED=true
            shift
            ;;
        --)
            shift
            break
            ;;
    esac
done

if [ -z "${PRIVATE_IP}" -o -z "${PUBLIC_IP}" -o -z "${SSH_KEY_FILENAME}" ] ; then
    show_syntax
    exit 1
fi

echo "Installing RPM(s)"

for rpm_file in ../cli/*.rpm; do
    rpm_name=$(sudo rpm -qp ${rpm_file})

    set +e
    sudo rpm -q ${rpm_name}
    rpm_rc=$?
    set -e

    if [ ${rpm_rc} -eq 0 ]; then
        echo "Package ${rpm_file} already installed; skipping"
    else
        echo "Installing ${rpm_file}"
        sudo yum -y install ${rpm_file}
    fi
done

TEMP_INPUTS=$(mktemp --suffix=.yaml)

echo "Writing temporary inputs into ${TEMP_INPUTS}"

cat << EOF >> ${TEMP_INPUTS}
public_ip: ${PUBLIC_IP}
private_ip: ${PRIVATE_IP}
ssh_user: ${SSH_USER}
ssh_key_filename: ${SSH_KEY_FILENAME}
dsl_resources: {}
manager_resources_package: file://$(pwd)/../manager-resources-package.tar.gz
ssl_enabled: ${SSL_ENABLED}
EOF

echo "Inputs file:"
echo "------------"
cat ${TEMP_INPUTS}
echo "------------"

# Perform the bootstrap.
echo "Starting the bootstrap process"
cfy bootstrap /opt/cfy/cloudify-manager-blueprints/simple-manager-blueprint.yaml -i ${TEMP_INPUTS} $@

rm -f ${TEMP_INPUTS}

# We provide an empty dict to dsl_resources in order to avoid the bootstrap
# process having to go outside. To compensate, just copy the files.
echo "Copying DSL resources"
sudo cp -R ../dsl/. /opt/manager/resources/
sudo chown -R cfyuser:cfyuser /opt/manager/resources/spec
sudo chmod -R go-w /opt/manager/resources/spec

# Upload Wagons.
for wagon in ../wagons/*.wgn; do
    echo "Uploading plugin: ${wagon}"
    cfy plugins upload ${wagon}
done

echo "Done."
