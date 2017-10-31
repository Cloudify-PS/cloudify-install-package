import os
import argparse
import tempfile
import yaml
import subprocess
import tarfile
import shutil


def download(url, dest=None, dest_dir=None):
    args = ['curl', '-k', '-L', url]
    cwd = None
    if dest:
        args.extend(['-o', dest])
    else:
        if dest_dir:
            cwd = dest_dir
            args.extend(['-O'])
        else:
            raise Exception('Asked to download a file but I don''t know where to')

    print "Downloading {0} into {1}".format(url, dest if dest else dest_dir)
    subprocess.check_call(args=args, cwd=cwd)


parser = argparse.ArgumentParser()
parser.add_argument('c', help='configuration file')
parser.add_argument('o', help='output file')

args = parser.parse_args()

with open(args.c, 'r') as stream:
    configuration = yaml.load(stream)

archive_root = tempfile.mkdtemp()
print "Accumulating contents into {0}".format(archive_root)

# Obtain Manager Blueprints
mgr_blueprints_url = configuration['manager-blueprints-url']
mgr_blueprints_dir = tempfile.mkdtemp()

with tempfile.NamedTemporaryFile('w', delete=False) as f:
    mgr_blueprints_archive = f.name
    download(mgr_blueprints_url, dest=mgr_blueprints_archive)

# Extract the manager blueprints, obtain the DSL resources.
# Use a subprocess rather than TarFile, as the latter doesn't support
# strip-components.
subprocess.check_call(['tar', '--strip-components=1', '-zxvf',
                       mgr_blueprints_archive], cwd=mgr_blueprints_dir)

with open(os.path.join(mgr_blueprints_dir, 'simple-manager-blueprint.yaml')) as f:
    manager_bp = yaml.load(f)

dsl_resources = manager_bp['inputs']['dsl_resources']['default']

# Obtain YAML files
dsl_resources_dir = os.path.join(archive_root, 'dsl')
os.makedirs(dsl_resources_dir)

for dsl_resource in dsl_resources:
    dest_location = os.path.join(dsl_resources_dir, dsl_resource['destination_path'][1:])
    os.makedirs(os.path.dirname(dest_location))
    download(dsl_resource['source_path'], dest=dest_location)

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
    if os.path.isdir(name):
        shutil.copytree(name, os.path.join(archive_root, name))
    else:
        shutil.copy(name, archive_root)

for x in ['resources', 'bin']:
    shutil.copytree(x, os.path.join(archive_root, x))

# Create archive.
# No need in compression as the vast majority of the contents
# is already compressed.

with tarfile.open(args.o, mode='w') as output_file:
    for name in os.listdir(archive_root):
        output_file.add(os.path.join(archive_root, name),
                        arcname=os.path.join('cloudify', name))

# Remove temporaries.
os.remove(mgr_blueprints_archive)
shutil.rmtree(mgr_blueprints_dir)
shutil.rmtree(archive_root)
