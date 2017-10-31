#!/bin/bash -e

show_syntax() {
    cat << EOF >&2
Syntax: ${SCRIPT_NAME} --private-ip <private_ip> --public-ip <public_ip> [--user <ssh_user>]
        --key <key_file> [--extra <extra_inputs_yaml>] [--ssl] [--admin-password <password>]
        [--skip-plugins] [--skip-cli]

--private-ip        this machine's IP to be used for internal communications. Usually,
                    this is the machine's private IP.
--public-ip         this machine's IP to be used for communicating via the REST API or
                    CLI
--user              (optional) the user to use for SSH'ing into this machine. If not
                    provided, the current user is used.
--key               private key to use to SSH into this machine.
--extra             an additional YAML file to use for inputs.
--ssl               (optional) if specified, enable SSL on the REST API layer.
--admin-password    (optional) password to assign to the 'admin' user. If not provided,
                    then a password is automatically generated.
--skip-plugins      (optional) if specified, skip the uploading of plugins to the manager
                    after bootstrap.
--skip-cli          (optional) if specified, skip the installation of the CLI RPM before
                    bootstrap. Note that the CLI RPM must be installed in order for the
                    bootstrap to work.
EOF
}

SCRIPT_NAME=$(basename $0)

set +e
PARSED_CMDLINE=$(getopt -o '' --long private-ip:,public-ip:,user:,key:,extra:,ssl,admin-password:,skip-plugins,skip-cli --name "${SCRIPT_NAME}" -- "$@")
set -e

if [[ $? -ne 0 ]]; then
    show_syntax
    exit 1
fi

eval set -- "${PARSED_CMDLINE}"

EXTRA_INPUTS_YAML=
ADMIN_PASSWORD=
SKIP_PLUGINS=
SKIP_CLI=
SSL_ENABLED=false
SSH_USER=$(id -un)

while true ; do
    case "$1" in
        --private-ip)
            PRIVATE_IP="$2"
            shift 2
            ;;
        --public-ip)
            PUBLIC_IP="$2"
            shift 2
            ;;
        --user)
            SSH_USER="$2"
            shift 2
            ;;
        --key)
            SSH_KEY_FILENAME="$2"
            shift 2
            ;;
        --ssl)
            SSL_ENABLED=true
            shift
            ;;
        --extra)
            EXTRA_INPUTS_YAML="$2"
            shift 2
            ;;
        --admin-password)
            ADMIN_PASSWORD="$2"
            shift 2
            ;;
        --skip-plugins)
            SKIP_PLUGINS=true
            shift
            ;;
        --skip-cli)
            SKIP_CLI=true
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

if [ -z "${SKIP_CLI}" ] ; then
    echo "Installing CLI RPM"

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
else
    echo "Skipping CLI installation"
fi

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
admin_password: ${ADMIN_PASSWORD}
EOF

if [ -n "${EXTRA_INPUTS_YAML}" ]; then
    cat ${EXTRA_INPUTS_YAML} >> ${TEMP_INPUTS}
fi

echo "Inputs file:"
echo "------------"
cat ${TEMP_INPUTS}
echo "------------"

# Perform the bootstrap.
echo "Starting the bootstrap process"
cfy bootstrap /opt/cfy/cloudify-manager-blueprints/simple-manager-blueprint.yaml -i ${TEMP_INPUTS} -vv

rm -f ${TEMP_INPUTS}

# We provide an empty dict to dsl_resources in order to avoid the bootstrap
# process having to go outside. To compensate, just copy the files.
echo "Copying DSL resources"
sudo cp -R ../dsl/. /opt/manager/resources/
sudo chown -R cfyuser:cfyuser /opt/manager/resources/spec
sudo chmod -R go-w /opt/manager/resources/spec

# Upload Wagons.
if [ -z "${SKIP_PLUGINS}" ] ; then
    for wagon in ../wagons/*.wgn; do
        # Skip validation as per https://cloudifysource.atlassian.net/browse/CFY-7443
        cfy plugins upload --skip-local-plugins-validation ${wagon}
    done
else
    echo "Skipping plugins upload"
fi

echo "Done."
