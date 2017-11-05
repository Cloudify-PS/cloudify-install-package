import os
import argparse
import tempfile
import yaml
import subprocess
import tarfile
import shutil

ARG_CONFIG_FILE = 'config-file'
ARG_OUTPUT_FILE = 'output-file'


def download(url, dest=None, dest_dir=None):
    """
    Download from a URL into a local file.

    Either "dest" or "dest_dir" must be provided, but not both.
    If "dest_dir" is provided, then the downloaded file will carry
    the same basename as the URL.

    :param url: URL to download from
    :type url: str
    :param dest: destination file to write to
    :type dest: str
    :param dest_dir: destination directory to write to
    :type dest_dir: str
    """
    curl_args = ['curl', '-k', '-L', url]
    cwd = None
    if dest:
        curl_args.extend(['-o', dest])
    else:
        if dest_dir:
            cwd = dest_dir
            curl_args.extend(['-O'])
        else:
            raise Exception('Asked to download a file but I don''t know where to')

    print "Downloading {0} into {1}".format(url, dest if dest else dest_dir)
    subprocess.check_call(args=curl_args, cwd=cwd)


# Parse arguments.

parser = argparse.ArgumentParser()
parser.add_argument(ARG_CONFIG_FILE, help='configuration file')
parser.add_argument(ARG_OUTPUT_FILE, help='output file')

args = vars(parser.parse_args())

# Read configuration.

with open(args[ARG_CONFIG_FILE], 'r') as stream:
    configuration = yaml.load(stream)

# Prepare layout of temporary files.

temp_root = tempfile.mkdtemp()
archive_root = os.path.join(temp_root, 'archive')
mgr_blueprints_dir = os.path.join(temp_root, 'mgr-blueprints')
mgr_blueprints_archive = os.path.join(temp_root, 'cloudify-manager-blueprints.tar.gz')

os.mkdir(archive_root)
os.mkdir(mgr_blueprints_dir)

print "Accumulating contents into {0}".format(archive_root)

# Obtain Manager Blueprints

mgr_blueprints_url = configuration['manager-blueprints-url']
download(mgr_blueprints_url, dest=mgr_blueprints_archive)

# Extract the manager blueprints, obtain the DSL resources.
# Use a subprocess rather than TarFile, as the latter doesn't support
# strip-components.

subprocess.check_call(['tar', '--strip-components=1', '-zxvf',
                       mgr_blueprints_archive], cwd=mgr_blueprints_dir)

# Read the default DSL resources.

with open(os.path.join(mgr_blueprints_dir, 'simple-manager-blueprint.yaml')) as f:
    manager_bp = yaml.load(f)

dsl_resources = manager_bp['inputs']['dsl_resources']['default']
dsl_resources.extend(configuration.get('extra-dsl-resources'))

# Obtain YAML files

dsl_resources_dir = os.path.join(archive_root, 'dsl')
os.makedirs(dsl_resources_dir)

for dsl_resource in dsl_resources:
    dest_location = os.path.join(dsl_resources_dir, dsl_resource['destination_path'][1:])
    os.makedirs(os.path.dirname(dest_location))
    download(dsl_resource['source_path'], dest=dest_location)

archive_resources_dir = os.path.join(archive_root, 'resources')
os.makedirs(archive_resources_dir)

# Prepare DSL Resources YAML helper file.

for dsl_resource in dsl_resources:
    dsl_resource['source_path'] = '@root@{0}'.format(dsl_resource['destination_path'])

with open(os.path.join(archive_resources_dir, 'dsl-resources.yaml'), mode='w') as f:
    yaml.dump({ 'dsl_resources' : dsl_resources }, f)

# Obtain CLI packages

cli_package_urls = configuration['cli-package-urls']
cli_packages_dir = os.path.join(archive_root, 'cli')
os.makedirs(cli_packages_dir)

for url in cli_package_urls:
    download(url, dest_dir=cli_packages_dir)

# Obtain manager resources package

mgr_resources_package_url = configuration['mgr-resources-package']
download(mgr_resources_package_url, dest=os.path.join(archive_root, 'manager-resources-package.tar.gz'))

# Obtain Wagon files

wagon_files = configuration['wagon-files']
wagon_dir = os.path.join(archive_root, 'wagons')
os.makedirs(wagon_dir)

for wagon in wagon_files:
    download(wagon, dest_dir=wagon_dir)

# Copy README file

shutil.copy(os.path.join(os.path.dirname(__name__), 'README.md'),
            archive_root)

# Copy additional dirs

for name in os.listdir('resources'):
    qualified_name = os.path.join('resources', name)
    if os.path.isdir(qualified_name):
        shutil.copytree(qualified_name, os.path.join(archive_root, name))
    else:
        shutil.copy(qualified_name, archive_root)

# Copy prerequisite RPM's

rpms_dir = os.path.join(archive_root, 'prereq')
prerequisite_rpms = configuration['python-prereq-rpms']
for rpm in prerequisite_rpms:
    download(rpm, dest_dir=rpms_dir)

# Create archive.
# No need in compression as the vast majority of the contents
# is already compressed.

with tarfile.open(args[ARG_OUTPUT_FILE], mode='w') as output_file:
    for name in os.listdir(archive_root):
        output_file.add(os.path.join(archive_root, name),
                        arcname=os.path.join('cloudify', name))

# Remove temporaries.

shutil.rmtree(temp_root)

print "Done."