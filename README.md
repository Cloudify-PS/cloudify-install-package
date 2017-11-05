# Cloudify Installation Package

This project contains a small script, `create.py`, which creates a TAR file containing everything that is required
in order to bootstrap a Cloudify Manager.

*NOTE*: The `create.py` script must be run in a virtualenv that has `pyyaml` installed:

```bash
virtualenv /tmp/inst
/tmp/inst/bin/pip install pyyaml
/tmp/inst/bin/python create.py parameters ...
```

## Syntax:

```bash
create.py <configuration-yaml> <output-file>
```

`<configuration-yaml>` is a YAML file describing all artifacts that need to be collected. As this project is source-controlled,
the included `config.yaml` should be adequate for the current release so it probably can be used without modification.

## Configuration Directives

* `manager-blueprints-url`: a URL to a `tar.gz` file containing the manager blueprints. **NOTE**: these manager blueprints
  are *not* going to be included in the output TAR file; they are only used in order to get the default `dsl_resources`.
* `cli-package-urls`: list of URLs to CLI installation packages to be included in the output TAR. If this TAR is for the
  purpose of bootstrapping a manager, then the RHEL/CentOS installation package (RPM) must be included.
* `mgr-resources-package`: a URL to the Cloudify Manager resources package to include.
* `wagon-files`: list of URLs to offline plugin packages ("Wagons") to be included in the output.
* `extra-dsl-resources`: additional DSL resources to be included in the package. Normally, this should be
  a dictionary containing all of the official plugins' YAML files.
