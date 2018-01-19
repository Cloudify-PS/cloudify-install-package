# Cloudify Installation Package

This package contains all artifacts required in order to:

* Install the Cloudify CLI
* Bootstrap a Cloudify Manager

## Contents

* `bin`: installation scripts.
* `cli`: CLI installation packages for various platforms.
* `dsl`: YAML files to be copied to the Cloudify Manager's `resources` directory during
         bootstrap.
* `resources`: additional helper artifacts.
* `wagons`: offline plugin packages ("Wagons"), for the latest official Cloudify plugins.
* `prereq`: prerequisite system-level RPM's that are not provided with Cloudify Manager 

## Bootstrapping a Manager

Bootstrapping a manager can be done by using the `bin/bootstrap.sh` script. Run it without arguments
in order to see available parameters.

### Process

1. Install Python system-level prerequisites, if not provided by the operating system
2. Install the CLI RPM (unless asked to skip)
3. Perform bootstrap
4. Copy all official DSL resources
5. Upload all official plugin packages

### Parameters

The following parameters must be specified:

* `--private-ip`: the current machine's private IP. This IP address is used for:
  * Communication between certain internal Cloudify Manager components
  * Communication between Cloudify Manager instances that are a part of a high availability cluster
  * Default communication between Cloudify Manager and VM agents
* `--public-ip`: any IP address by which this Cloudify Manager is to be known externally,
  for CLI or REST clients. This IP address is used in two places:
  * The CLI profile being created automatically after bootstrap, on the current machine.
  * The public-facing SSL certificate attached to the public-facing REST API endpoint.
* `--key`: private key file to use for SSH'ing into the local machine.

Optional parameters:

* `--user`: the user account to use when SSH'ing into the local machine. If omitted, then the
  currently logged-in user account is used.
* `--extra`: path to a YAML file containing additional Manager Blueprint inputs, to be appended
  to the automatically-generated inputs file.
* `--no-ssl`: avoid SSL-protecting the public REST API endpoint.
* `--admin-password`: explicitly set the administrator user's password. If omitted, a random password
  will be generated.
* `--skip-memory-validation`: if specified, skip the validation of available memory.
* `--skip-cli`: skips the pre-bootstrap step of installing the CLI RPM. Note that the CLI RPM installation is
  required for the bootstrap process to work.
* `--skip-prereq`: skips installing prerequisites (if not already installed), or uninstalling potentially-interfering
  packages (if installed).
* `--skip-yum-config`: skips stopping and disabling the `yum-cron` service (if it exists).
