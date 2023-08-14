@{
package_manager = 'dnf'
python3_pkgversion = '3'

if os_name == 'rhel' and os_code_name.isnumeric() and int(os_code_name) < 8:
    package_manager = 'yum'
    python3_pkgversion = '36'
}@
# generated from @template_name

@[if os_name in ['rhel']]@
FROM almalinux:@(os_code_name)

# Enable EPEL on RHEL
RUN @(package_manager) install -y epel-release
@[else]@
FROM @(os_name):@(os_code_name)
@[end if]@

RUN @(package_manager) update -y

@[if os_name in ['rhel']]@
# Enable CRB on RHEL
RUN crb enable
@[end if]@

RUN @(package_manager) install -y dnf{,-command\(download\)} mock{,-{core-configs,scm}} python@(python3_pkgversion){,-{catkin_pkg,empy,rosdistro,yaml}}

RUN useradd -u @(uid) -l -m buildfarm
RUN usermod -a -G mock buildfarm

# Clean up after updates and freshen cache
RUN @(package_manager) clean dbcache packages
RUN @(package_manager) makecache

# "Expire" the cache to force the next operation to check again
RUN @(package_manager) clean expire-cache

# automatic invalidation once every day
RUN echo "@(today_str)"

RUN @(package_manager) update -y

# Workaround for broken mock configs for EPEL 8
RUN echo -e "include('templates/almalinux-8.tpl')\ninclude('templates/epel-8.tpl')\n\nconfig_opts['root'] = 'epel-8-x86_64'\nconfig_opts['target_arch'] = 'x86_64'\nconfig_opts['legal_host_arches'] = ('x86_64',)" > /etc/mock/epel-8-x86_64.cfg

@[for i, key in enumerate(distribution_repository_keys)]@
RUN echo -e "@('\\n'.join(key.splitlines()))" > /etc/pki/mock/RPM-GPG-KEY-ros-buildfarm-@(i)
@[end for]@
COPY mock_config.cfg /etc/mock/ros_buildfarm.cfg

# Upgrade cmake to 3.22.1 to match Ubuntu 22.04
RUN wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | sudo tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null \
    && echo 'deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ focal main' | tee /etc/apt/sources.list.d/kitware.list >/dev/null \
    && apt-get update \
    && apt-get remove -y cmake && apt-get purge -y cmake && apt-get remove -y cmake-data && apt-get purge -y cmake-data \
    && apt-get install -y cmake=3.22.1-0kitware1ubuntu20.04.1 cmake-data=3.22.1-0kitware1ubuntu20.04.1 \
    && cmake --version \
&& rm -rf /var/lib/apt/lists/* \
&& apt-get clean

USER buildfarm
ENTRYPOINT ["sh", "-c"]
@{
cmds = [
    'PYTHONPATH=/tmp/ros_buildfarm:$PYTHONPATH python3 -u' +
    ' /tmp/ros_buildfarm/scripts/release/rpm/get_sourcepkg.py' +
    ' --rosdistro-index-url ' + rosdistro_index_url +
    ' ' + rosdistro_name +
    ' ' + package_name +
    ' --sourcepkg-dir ' + sourcepkg_dir +
    (' --skip-download-sourcepkg' if skip_download_sourcepkg else ''),

    'PYTHONPATH=/tmp/ros_buildfarm:$PYTHONPATH python3 -u' +
    ' /tmp/ros_buildfarm/scripts/release/rpm/build_binarypkg.py' +
    ' ' + rosdistro_name +
    ' ' + package_name +
    ' --sourcepkg-dir ' + sourcepkg_dir +
    ' --binarypkg-dir ' + binarypkg_dir +
    (' --append-timestamp' if append_timestamp else '') +
    (' --skip-tests' if skip_tests else ''),
]
}@
CMD ["@(' && '.join(cmds))"]
