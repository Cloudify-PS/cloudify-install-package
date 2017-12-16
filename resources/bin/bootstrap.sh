#!/bin/bash -e

show_syntax() {
    cat << EOF >&2
Syntax: ${SCRIPT_NAME} --private-ip <private_ip> --public-ip <public_ip> --key <key_file>
        [--user <ssh_user>] [--extra <extra_inputs_yaml>] [--no-ssl] [--admin-password <password>]
        [--skip-memory-validation] [--skip-plugins] [--skip-cli] [--skip-prereq] [--skip-yum-config]

Required parameters:

--private-ip                this machine's IP to be used for internal communications. Usually,
                            this is the machine's private IP.
--public-ip                 this machine's IP to be used for communicating via the REST API or
                            CLI
--key                       private key to use to SSH into this machine.

Optional parameters:

--user                      the user to use for SSH'ing into this machine. If not
                            provided, the current user is used.
--extra                     an additional YAML file to use for inputs.
--no-ssl                    if specified, disable SSL on the REST API layer.
--admin-password            password to assign to the 'admin' user. If not provided,
                            then a password is automatically generated.
--skip-memory-validation    skip validation of available memory prior to bootstrap
--skip-plugins              if specified, skip the uploading of plugins to the manager
                            after bootstrap.
--skip-cli                  if specified, skip the installation of the CLI RPM before
                            bootstrap. Note that the CLI RPM must be installed in order for the
                            bootstrap to work.
--skip-prereq               if specified, skip the detection and (potential) installation of
                            prerequisite packages which are not delivered as part of the
                            Cloudify Manager bundle, as well as uninstalling potentially-interfering
                            packages
--skip-yum-config           if specified, skip disabling the yum-cron service (if it is installed)
EOF
}

yum_remove_if_installed() {
    package_name=$1
    echo "Checking if package ${package_name} is installed..."
    if sudo yum -y --disablerepo=* list installed "${package_name}" >/dev/null 2>&1; then
        echo "Package ${package_name} is installed; removing it"
        sudo yum -y --disablerepo=* remove ${package_name}
        echo "Package ${package_name} removed"
    else
        echo "Package ${package_name} not installed; skipping"
    fi
}

SCRIPT_NAME=$(basename $0)
SCRIPT_DIR=$(dirname $(readlink -f $0))

set +e
PARSED_CMDLINE=$(getopt -o '' --long private-ip:,public-ip:,user:,key:,extra:,no-ssl,admin-password:,skip-memory-validation,skip-plugins,skip-cli,skip-prereq,skip-yum-config --name "${SCRIPT_NAME}" -- "$@")
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
SKIP_PREREQ=
SKIP_YUM_CONFIG=
SSL_ENABLED=true
SSH_USER=$(id -un)
MIN_MEMORY_VALIDATION=

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
        --no-ssl)
            SSL_ENABLED=false
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
        --skip-memory-validation)
            MIN_MEMORY_VALIDATION=0
            shift
            ;;
        --skip-prereq)
            SKIP_PREREQ=true
            shift
            ;;
        --skip-yum-config)
            SKIP_YUM_CONFIG=true
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

# Handle prerequisites

if [ -z "${SKIP_PREREQ}" ] ; then
    # If pip is installed in any way, and virtualenv is installed through it,
    # then remove virtualenv. This is done in order to cope with CFY-7678.

    set +e
    pip_ind=$(command -v pip)
    set -e

    if [ -n "${pip_ind}" ] ; then
        echo "pip is system-available; checking if virtualenv is installed..."
        set +e
        virtualenv_ind=$(pip show virtualenv)
        set -e

        if [ -n "${virtualenv_ind}" ] ; then
            echo "virtualenv is available; removing it"
            sudo pip uninstall -y -v virtualenv
        else
            echo "virtualenv is not installed through system-available pip; skipping"
        fi
    else
        echo "pip is not system-available"
    fi

    echo "Removing python-pip and python-virtualenv if they are installed"

    yum_remove_if_installed python-pip
    yum_remove_if_installed python2-pip
    yum_remove_if_installed python-virtualenv

    echo "Installing prerequisite RPM's if not already installed"
    set +e
    sudo yum -y --disablerepo=* install ${SCRIPT_DIR}/../prereq/*.rpm
    yum_rc=$?
    set -e

    if [ $yum_rc -ne 0 ] ; then
        echo "Prerequisite installation ended with return code ${yum_rc}. Most likely, this means that nothing required installation."
    fi
else
    echo "Skipping prerequisites installation"
fi

if [ -z "${SKIP_CLI}" ] ; then
    echo "Installing CLI RPM"

    for rpm_file in ${SCRIPT_DIR}/../cli/*.rpm; do
        rpm_name=$(sudo rpm -qp ${rpm_file})

        set +e
        sudo rpm -q ${rpm_name}
        rpm_rc=$?
        set -e

        if [ ${rpm_rc} -eq 0 ]; then
            echo "Package ${rpm_file} already installed; skipping"
        else
            echo "Installing ${rpm_file}"
            sudo yum -y --disablerepo=* install ${rpm_file}
        fi
    done
else
    echo "Skipping CLI installation"
fi

# Handle yum configuration

if [ -z "${SKIP_YUM_CONFIG}" ] ; then
    echo "Checking if yum-cron is enabled or started"
    set +e
    sudo systemctl is-enabled yum-cron
    enabled_rc=$?
    sudo systemctl is-active yum-cron
    active_rc=$?
    set -e

    if [ $active_rc -eq 0 ] ; then
        echo "yum-cron is active; stopping it"
        sudo systemctl stop yum-cron || echo "WARNING: Failed stopping yum-cron, rc=$?"
    fi

    if [ $enabled_rc -eq 0 ] ; then
        echo "yum-cron is enabled; disabling it"
        sudo systemctl disable yum-cron || echo "WARNING: Failed disabling yum-cron, rc=$?"
    fi
else
    echo "Skipping yum-cron detection"
fi


TEMP_INPUTS=$(mktemp --suffix=.yaml)

echo "Writing temporary inputs into ${TEMP_INPUTS}"

cat << EOF >> ${TEMP_INPUTS}
public_ip: ${PUBLIC_IP}
private_ip: ${PRIVATE_IP}
ssh_user: ${SSH_USER}
ssh_key_filename: ${SSH_KEY_FILENAME}
manager_resources_package: file://${SCRIPT_DIR}/../manager-resources-package.tar.gz
ssl_enabled: ${SSL_ENABLED}
admin_password: ${ADMIN_PASSWORD}
EOF

if [ -n "${MIN_MEMORY_VALIDATION}" ]; then
    echo "minimum_required_total_physical_memory_in_mb: ${MIN_MEMORY_VALIDATION}" >> ${TEMP_INPUTS}
fi

if [ -n "${EXTRA_INPUTS_YAML}" ]; then
    cat ${EXTRA_INPUTS_YAML} >> ${TEMP_INPUTS}
fi

TEMP_DSL_RESOURCES=$(mktemp --suffix=.yaml)
sed -e 's#@root@#'"${SCRIPT_DIR}/../dsl"'#' ${SCRIPT_DIR}/../resources/dsl-resources.yaml > ${TEMP_DSL_RESOURCES}

echo "Inputs file:"
echo "------------"
cat ${TEMP_INPUTS}
echo "------------"
echo "DSL resources file:"
echo "-------------------"
cat ${TEMP_DSL_RESOURCES}
echo "-------------------"

# Perform the bootstrap.
echo "Starting the bootstrap process"
cfy bootstrap /opt/cfy/cloudify-manager-blueprints/simple-manager-blueprint.yaml -i ${TEMP_INPUTS} -i ${TEMP_DSL_RESOURCES} -vv

rm -f ${TEMP_INPUTS}
rm -f ${TEMP_DSL_RESOURCES}

# We provide an empty dict to dsl_resources in order to avoid the bootstrap
# process having to go outside. To compensate, just copy the files.
echo "Copying DSL resources..."
sudo cp -Rv ${SCRIPT_DIR}/../dsl/. /opt/manager/resources/
sudo chown -R cfyuser:cfyuser /opt/manager/resources/spec
sudo chmod -R go-w /opt/manager/resources/spec

# Upload Wagons.
if [ -z "${SKIP_PLUGINS}" ] ; then
    for wagon in ${SCRIPT_DIR}/../wagons/*.wgn; do
        cfy plugins upload ${wagon}
    done
else
    echo "Skipping plugins upload"
fi

echo "Done."
