# <a name="title"></a> kitchen-qemu

A Test Kitchen Driver for QEMU.


## <a name="requirements"></a> Requirements

Test Kitchen and QEMU should be installed. To use KVM acceleration
you should have read/write access to `/dev/kvm`. This is usually
done by adding your user to the `kvm`-group.


## <a name="installation"></a> Installation and Setup

### <a name="installation-driver"></a> Driver Installation

This driver is installable via `gem install kitchen-qemu`.
Please read the [Kitchen docs][docs] for more details
on how to configure Kitchen to use this driver.

### <a name="installation-image"></a> Image Download

Images for use with kitchen-qemu can be downloaded from

http://esmil.dk/kitchen-qemu/

These are all generated by [this cookbook][cookbook].

### <a name="installation-image"></a> Image Creation

Create a bootable image of your favourite \*NIX and go through
the following checklist:

1. Create a user for kitchen to use. This can be root but
   should preferably be a different user.
   The username `kitchen` with password `kitchen` are good choices.

2. Install sudo and make sure the `kitchen` user has
   password-less sudo rights. Eg.
   ```
   # echo 'kitchen ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/kitchen
   ```

3. Install an SSH server and make sure it is started automatically
   at boot and listens on port 22.

4. Install curl, wget or something similar for downloading
   Chef from the guest or pre-install the Chef
   [Omnibus package][chef_omnibus_dl] for even faster
   converge times.

5. Ensure that the image uses DHCP to configure its network.
   The network must be operational for kitchen to function.
   Pay special attention to MAC addresses being hard-coded in
   scripts like 'ifcfg-eth0'. You may need to create 'ifcfg-eth1'
   to deal with the udev system making another interface (e.g.: Centos 6).

6. Bonus points for automatically starting a getty on the first
   serial port. This way you can log into the guest without using
   SSH like so:
   ```
   $ socat -,cfmakeraw,escape=0xf .kitchen/<instance name>.mon
   ```
   Use Ctrl-o to exit socat.

### <a name="installation-berkshelf"></a> Berkshelf Workaround

Berkshelf has a bug
([they wont fix](https://github.com/berkshelf/berkshelf/issues/1627))
that makes it crash if it encounters a named unix socket
when uploading cookbooks to the guest.
This will happen when uploading the cookbook in the current
directory since that includes the `.kitchen` directory where
kitchen-qemu creates two unix sockets for each running instance.
One is a "serial terminal" and one is used to shutdown the running
instance gracefully.

To work around this bug make Berkshelf ignore the `.kitchen`
directory by adding it to a `chefignore` file. Eg.
```
$ echo .kitchen >> chefignore
```

Alternatively create a `Cheffile` and let kitchen use
[Librarian-Chef](https://github.com/applicationsonline/librarian-chef)
to resolve cookbook dependencies.

## <a name="config"></a> Configuration

### <a name="config-image"></a> image

This setting is required to specify the path to a
bootable disk image. It'll only be opened for reading.
Any changes shall be written to temporary storage
and lost once the instance is destroyed. Eg.:
```yml
driver:
  name: qemu

platforms:
  - name: myplatform
    driver:
      image: /path/to/mybootable.qcow2
```
See above for how to prepare images for use with kitchen-qemu.

For advanced uses this setting can also be a list of maps
describing several images to attach to the guest. Eg.:
```yml
driver:
  name: qemu

platforms:
  - name: myplatform
    driver:
      image:
        # opened read-only, guest changes discarded when shut down
        - file: /path/to/bootable.qcow2
        # opened read/write, guest changes persisted
        - file: /path/to/writable.qcow2
          snapshot: off
        # opened read-only, guest cannot write to it
        - file: /path/to/readonly.qcow2
          readonly: on
```

### <a name="config-image-path"></a> image\_path

Specifies the default path for images. That is unless the absolute path
to the an image file is given this path is prepended.

Defaults to the following:
- if the `KITCHEN_QEMU_IMAGES` environment variable if set use that
- if `XDG_CONFIG_HOME` is set use `$XDG_CONFIG_HOME/kitchen-qemu`
- if `HOME` is set use `$HOME/.config/kitchen-qemu`
- fall back to `/tmp/kitchen-qemu`.

This means the following `.kitchen.yml` will usually look for
`$HOME/.config/kitchen-qemu/jessie.qcow2` and `$HOME/.config/kitchen-qemu/trusty.qcow2`.

```yml
driver:
  name: qemu

platforms:
  - name: jessie
    driver:
      image: jessie.qcow2
  - name: trusty
    driver:
      image: trusty.qcow2
```

### <a name="config-arch"></a> arch

Determines the QEMU command to run:
* `x86`,  `i386` or `32bit` runs `qemu-system-i386`.
* `x86_64`, `amd64` or `64bit` runs `qemu-system-x86_64`.

Defaults to `x86_64`.

### <a name="config-binary"></a> binary

Explicitly set which QEMU binary to run.

Defaults to unset which means the binary is guessed from the `arch` setting.

### <a name="config-username"></a> username

Username to use when SSH'ing to the instance.

Defaults to `kitchen`.

### <a name="config-password"></a> password

Password to use when first SSH'ing to the instance.
This is only used when creating the instance.
Subsequent connections will use a built-in RSA key-pair.

Defaults to `kitchen`.

### <a name="config-port"></a> port

Determines which port QEMU will listen on. Connections to
localhost on this port are forwarded to port 22 on the guest
which should accept incoming SSH connections there.

Defaults to unset which means a random free port is used.

### <a name="config-port-min"></a> port\_min

Determines the lowest port number to pick when
the port is not specified.

Defaults to 1025.

### <a name="config-port-max"></a> port\_min

Determines the highest port number to pick when
the port is not specified.

Defaults to 65535.

### <a name="config-kvm"></a> kvm

Determines whether to enable KVM acceleration or not.

Defaults to unset which means kitchen-qemu will check
if `/dev/kvm` is both readable and writable before
enabling KVM.

### <a name="config-display"></a> display

Sets the -display option for QEMU. Set to `sdl` or `gtk`
to get a virtual screen window. This may be helpful to
debug why your image doesn't respond to SSH.

Defaults to `none' which means no window is displayed.

### <a name="config-bios"></a> bios

Use bios implementation at the given path.

### <a name="config-cpus"></a> cpus

Sets the number of virtual CPUs to give the instance.
Alternatively set one or more of the following 3 options
for more control over the virtual CPU topology.

Defaults to 1.

### <a name="config-sockets"></a> sockets

Sets the number of CPU sockets in each instance.

Defaults to 1.

### <a name="config-cores"></a> cores

Sets the number of cores in each instance CPU.

Defaults to 1.

### <a name="config-threads"></a> threads

Sets the number of threads in each instance CPU core.

Defaults to 1.

### <a name="config-memory"></a> memory

Determines the number of megabytes of RAM to give the instance.

Defaults to 512 (MiB).

### <a name="config-networks"></a> networks

Specify NICs and networks. If not specified it defaults to

```yml
suites:
  - name: mysuite
    driver:
      networks:
        - netdev: user,id=user,net=192.168.1.0/24,hostname=%h,hostfwd=tcp::%p-:22
          device: virtio-net-pci,netdev=user
```
If a netdev entry contains a `hostname=%h` setting the `%h` is replaced by the
configured hostname of the guest. Similarly when setting `hostfwd=..` any `%p` is
replaced by the possibly random port chosen for kitchen to connect to.
See the [port](#config-port) option above.

### <a name="config-hostname"></a> hostname

Set the hostname of the guest.

Defaults to the instance name.

### <a name="config-hostshares"></a> hostshares

Share parts of the host filesystem with the guest. Eg.
```yml
suites:
  - name: mysuite
    driver:
      hostshares:
        - path: my/shared/directory   # path to export
          mountpoint: /mnt            # mountpoint inside the guest
```
If the path is not an absolute path it is taken relative to the
directory of the `.kitchen.yml`. The shared path is automatically mounted
at the specified mountpoint inside the guest.
This is similar to Vagrant's synced_folders, but uses QEMU's builtin
9pfs over virtio feature. On Linux this requires the 9p and 9pnet_virtio
modules to be loadable or built in.

### <a name="config-acpi-poweroff"></a> acpi\_poweroff

Determines how guests are closed when running `kitchen destroy`.
When `true` an ACPI poweroff event is sent to the guest which
is expected to respond by closing down gracefully. This is
like pressing a virtual power button on the virtual machine.
When `false` QEMU is simply shut down immediately. This is faster
but similar to forcefully pulling the power from the virtual machine.

Defaults to `false` when all attached disk images are snapshotted or
read-only. Otherwise `true`.

### <a name="config-require-chef-omnibus"></a> require\_chef\_omnibus

Determines whether or not a Chef [Omnibus package][chef_omnibus_dl] will be
installed. There are several different behaviors available:

* `true` - the latest release will be installed. Subsequent converges
  will skip re-installing if chef is present.
* `latest` - the latest release will be installed. Subsequent converges
  will always re-install even if chef is present.
* `<VERSION_STRING>` (ex: `10.24.0`) - the desired version string will
  be passed the the install.sh script. Subsequent converges will skip if
  the installed version and the desired version match.
* `false` or `nil` - no chef is installed.

The default value is unset, or `nil`.

## <a name="development"></a> Development

* Source hosted at [GitHub][repo]
* Report issues/questions/feature requests on [GitHub Issues][issues]

Pull requests are very welcome! Make sure your patches are well tested.
Ideally create a topic branch for every separate change you make. For
example:

1. Fork the repo
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## <a name="authors"></a> Authors

Created and maintained by [Emil Renner Berthing][author] <<esmil@esmil.dk>>


## <a name="license"></a> License

GPLv3 or later (see [LICENSE][license])


[author]:           https://github.com/esmil
[cookbook]:         https://github.com/esmil/kitchen-qemu-images
[issues]:           https://github.com/esmil/kitchen-qemu/issues
[license]:          https://github.com/esmil/kitchen-qemu/blob/master/LICENSE
[repo]:             https://github.com/esmil/kitchen-qemu
[docs]:             http://kitchen.ci/docs/getting-started/creating-cookbook
[chef_omnibus_dl]:  http://www.chef.io/chef/install/
