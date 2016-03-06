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

### <a name="installation-image"></a> Image Creation

Create a bootable image of your favourite \*NIX and go through
the following check list:

1. Create a user for kitchen to use. This can be root but
   should preferably be a different user.
   The username `kitchen` with password `kitchen` are good choices.

2. Install sudo and make sure the `kitchen`-user has
   password-less sudo rights. Eg. <br/>
   `echo 'kitchen ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/kitchen`

3. Install an SSH server and make sure it is started automatically
   at boot and listens on port 22.

4. Install curl, wget or something similar for downloading
   Chef from the guest or pre-install the Chef
   [Omnibus package][chef_omnibus_dl] for even faster
   converge times.

5. Bonus points for automatically starting a getty on the first
   serial port. This way you can log into the guest without using
   SSH like so:
   ```$ socat -,cfmakeraw,escape=0xf .kitchen/<instance name>.mon```
   Use Ctrl-o to exit socat.


## <a name="config"></a> Configuration

### <a name="config-image"></a> image

This setting is required to specify the path to
the harddrive image to boot. It'll only be opened for reading.
Any changes shall be written to temporary storage
and lost once the instance is destroyed.

See above for how to prepare images for use with kitchen-qemu.

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

Defaults to port 2222 for now. No randomisation or probing for free
ports are done yet, so different platforms need different ports
configured to run at the same time. Eg. like so:
```yaml
driver:
  name: qemu

platforms:
  - name: squeeze
    driver:
      image: /path/to/squeeze.qcow2
      port: 2201
  - name: wheezy
    driver:
      image: /path/to/wheezy.qcow2
      port: 2202
  - name: jessie
    driver:
      image: /path/to/jessie.qcow2
      port: 2203
```

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

### <a name="config-memory"></a> memory

Determines the number of megabytes of RAM to give the instance.

Defaults to 512 (MiB).

### <a name="config-nic-model"></a> nic\_model

Determines the type of virtual ethernet hardware the guest will see.

Defaults to `virtio`.

### <a name="config-hostname"></a> hostname

Set the hostname of the guest.

Defaults to the instance name.

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
[issues]:           https://github.com/esmil/kitchen-qemu/issues
[license]:          https://github.com/esmil/kitchen-qemu/blob/master/LICENSE
[repo]:             https://github.com/esmil/kitchen-qemu
[docs]:             http://kitchen.ci/docs/getting-started/creating-cookbook
[chef_omnibus_dl]:  http://www.chef.io/chef/install/
