# This file is part of kitchen-qemu.
# Copyright 2016 Emil Renner Berthing <esmil@esmil.dk>
#
# kitchen-qemu is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# kitchen-qemu is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with kitchen-qemu.  If not, see <http://www.gnu.org/licenses/>.

require 'open3'
require 'socket'

require 'kitchen'
require 'kitchen/driver/qemu_version'
require 'kitchen/driver/qmpclient'

module Kitchen

  module Driver

    # QEMU driver for Kitchen.
    #
    # @author Emil Renner Berthing <esmil@esmil.dk>
    class Qemu < Kitchen::Driver::Base
      include ShellOut

      kitchen_driver_api_version 2
      plugin_version Kitchen::Driver::QEMU_VERSION

      default_config :arch,       'x86_64'
      default_config :username,   'kitchen'
      default_config :password,   'kitchen'
      default_config :port_min,   1025
      default_config :port_max,   65535
      default_config :display,    'none'
      default_config :memory,     '512'
      default_config :nic_model,  'virtio'
      default_config :hostshares, []

      default_config :image_path do |_|
        if ENV.has_key?('KITCHEN_QEMU_IMAGES')
          ENV['KITCHEN_QEMU_IMAGES']
        elsif ENV.has_key?('XDG_CONFIG_HOME')
          "#{ENV['XDG_CONFIG_HOME']}/kitchen-qemu"
        elsif ENV.has_key?('HOME')
          "#{ENV['HOME']}/.config/kitchen-qemu"
        else
          '/tmp/kitchen-qemu'
        end
      end

      required_config :image do |_attr, value, _subject|
        raise UserError, 'Must specify image file' unless value
      end

      # A lifecycle method that should be invoked when the object is about ready
      # to be used. A reference to an Instance is required as configuration
      # dependant data may be access through an Instance. This also acts as a
      # hook point where the object may wish to perform other last minute
      # checks, validations, or configuration expansions.
      #
      # @param instance [Instance] an associated instance
      # @return [self] itself, for use in chaining
      # @raise [ClientError] if instance parameter is nil
      def finalize_config!(instance)
        super
        if not config[:binary]
          config[:binary] = @@ARCHBINARY[config[:arch]] or
            raise UserError, "Unknown architecture '#{config[:arch]}'"
        end

        # kitchen-vagrant compatibility
        config[:hostname] = config[:vm_hostname] if config[:hostname].nil?

        acpi_poweroff = false
        if config[:image].kind_of?(String)
          config[:image] = [{
            :file     => config[:image],
            :readonly => false,
            :snapshot => true,
          }]
        else
          raise UserError, "Invalid image entry for #{instance.to_str}" unless
            config[:image].kind_of?(Array)
          config[:image].each do |image|
            raise UserError, "Invalid image entry for #{instance.to_str}" unless
              image.kind_of?(Hash) && image[:file]
            image[:readonly] = false             if image[:readonly].nil?
            image[:snapshot] = !image[:readonly] if image[:snapshot].nil?
            acpi_poweroff = true unless (image[:snapshot] || image[:readonly])
          end
        end
        config[:acpi_poweroff] = acpi_poweroff if config[:acpi_poweroff].nil?

        raise UserError, "Invalid share entry for #{instance.to_str}" unless
          config[:hostshares].kind_of?(Array)
        # kitchen-vagrant compatibility
        if config[:hostshares].empty? && config[:synced_folders].kind_of?(Array)
          config[:synced_folders].each do |folder|
            if !folder[0].kind_of?(String) || !folder[1].kind_of?(String)
              config[:hostshares].clear
              break
            end
            config[:hostshares].push({ :path => folder[0], :mountpoint => folder[1] })
          end
        else
          config[:hostshares].each do |share|
            raise UserError, "Invalid share entry for #{instance.to_str}" unless
              share.kind_of?(Hash) && share[:path]
            raise UserError, "No mountpoint defined for share '#{share[:path]}' of #{instance.to_str}" unless
              share[:mountpoint]
            raise UserError, "Invalid mount options for share '#{share[:path]}' of #{instance.to_str}" unless
              share[:mount_options].nil? || share[:mount_options].kind_of?(Array)
          end
        end

        config[:vga] = 'qxl' if config[:spice] && !config[:vga]
        self
      end

      # Creates a QEMU instance.
      #
      # @param state [Hash] mutable instance and driver state
      # @raise [ActionFailed] if the action could not be completed
      def create(state)
        Dir.chdir(config[:kitchen_root])

        monitor = monitor_path
        if File.exist?(monitor)
          begin
            mon = UNIXSocket.new(monitor)
          rescue Errno::ECONNREFUSED
            info 'Stale monitor socket detected. Assuming old QEMU already quit.'
            cleanup!
          else
            mon.close
            raise ActionFailed, "QEMU instance #{instance.to_str} already running."
          end
        end

        create_privkey or raise ActionFailed, "Unable to create file '#{privkey_path}'"

        fqdn = config[:hostname] || instance.name
        hostname = fqdn.match(/^([^.]+)/)[0]

        cmd = [
          config[:binary], '-daemonize',
          '-display', config[:display].to_s,
          '-chardev', "socket,id=mon-qmp,path=#{monitor},server,nowait",
          '-mon', 'chardev=mon-qmp,mode=control,default',
          '-serial', "mon:unix:path=#{serial_path},server,nowait",
          '-m', config[:memory].to_s,
        ]

        kvm = config[:kvm]
        if kvm.nil? # autodetect
          begin
            kvm = File.stat('/dev/kvm')
          rescue Errno::ENOENT
            kvm = false
            info 'KVM device /dev/kvm doesn\'t exist. Maybe the module is not loaded.'
          else
            kvm = kvm.writable? && kvm.readable?
            info 'KVM device /dev/kvm not read/writeable. Maybe add your user to the kvm group.' unless kvm
          end
        end
        if kvm
          info 'KVM enabled.'
          cmd.push('-enable-kvm', '-cpu', 'host')
        else
          info 'KVM disabled'
        end

        cmd.push('-vga',   config[:vga].to_s)   if config[:vga]
        cmd.push('-spice', config[:spice].to_s) if config[:spice]
        cmd.push('-vnc',   config[:vnc].to_s)   if config[:vnc]

        cmd.push('-device', 'virtio-scsi-pci,id=scsi')
        config[:image].each_with_index do |image, i|
          drive = ['if=none', "id=drive#{i}"]
          drive.push('readonly')    if image[:readonly]
          drive.push('snapshot=on') if image[:snapshot]
          if image[:file][0] == '/'
            drive.push("file=#{image[:file]}")
          else
            drive.push("file=#{config[:image_path]}/#{image[:file]}")
          end
          cmd.push('-device', "scsi-hd,drive=drive#{i}",
                   '-drive', drive.join(','))
        end

        config[:hostshares].each_with_index do |share, i|
          path = share[:path]
          path = "#{config[:kitchen_root]}/#{path}" unless path[0] == '/'
          raise ActionFailed, "Share path '#{path}' not a directory" unless
            ::File.directory?(path)
          cmd.push('-fsdev', "local,id=fsdev#{i},security_model=none,path=#{path}",
                   '-device', "virtio-9p-pci,fsdev=fsdev#{i},mount_tag=path#{i}")
        end

        port = config[:port]
        port = random_free_port('127.0.0.1', config[:port_min], config[:port_max]) if port.nil?
        cmd.push(
          '-net', "nic,model=#{config[:nic_model]}",
          '-net', "user,net=192.168.1.0/24,hostname=#{hostname},hostfwd=tcp::#{port}-:22",
        )

        info 'Spawning QEMU..'
        error = nil
        Open3.popen3({ 'QEMU_AUDIO_DRV' => 'none' }, *cmd) do |_, _, err, thr|
          if not thr.value.success?
            error = err.read.strip
          end
        end
        if error
          cleanup!
          raise ActionFailed, error
        end

        state[:hostname]      = '127.0.0.1'
        state[:port]          = port
        state[:username]      = config[:username]
        state[:password]      = config[:password]
        state[:acpi_poweroff] = config[:acpi_poweroff]

        if hostname == fqdn
          names = fqdn
        else
          names = "#{fqdn} #{hostname}"
        end

        info 'Waiting for SSH..'
        conn = instance.transport.connection(state)
        conn.wait_until_ready
        conn.execute(<<-EOS)
sudo sh -s 2>/dev/null <<END
echo '127.0.0.1 #{names}' >> /etc/hosts
hostnamectl --transient set-hostname #{hostname} || hostname #{hostname}
END
umask 0022
install -dm700 "$HOME/.ssh"
echo '#{@@PUBKEY}' > "$HOME/.ssh/authorized_keys"
EOS
        config[:hostshares].each_with_index do |share, i|
          options = share[:mount_options] ?
            share[:mount_options].join(',') : 'cache=none,access=any,version=9p2000.L'
          conn.execute("sudo sh -c 'install -dm755 \"#{share[:mountpoint]}\" && mount -t 9p -o trans=virtio,#{options} path#{i} \"#{share[:mountpoint]}\"'")
        end
        conn.close
        state[:ssh_key] = privkey_path
      end

      # Destroys an instance.
      #
      # @param state [Hash] mutable instance state
      # @raise [ActionFailed] if the action could not be completed
      def destroy(state)
        Dir.chdir(config[:kitchen_root])

        monitor = monitor_path
        return unless File.exist?(monitor)

        instance.transport.connection(state).close

        begin
          mon = QMPClient.new(UNIXSocket.new(monitor), 2)
          if state[:acpi_poweroff]
            info 'Sending ACPI poweroff..'
            mon.execute('system_powerdown')
            mon.wait_for_eof(30)
          else
            info 'Quitting QEMU..'
            mon.execute('quit')
            mon.wait_for_eof(5)
          end
          mon.close
        rescue Errno::ECONNREFUSED
          info 'Connection to monitor refused. Assuming QEMU already quit.'
        rescue QMPClient::Timeout
          mon.close
          raise ActionFailed, "QEMU instance #{instance.to_str} is unresponsive"
        end

        cleanup!
      end

      private

      @@PRIVKEY = %{-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAyG6ASL3bWS67rsA5LDvKnfdCBagK61B5LIr+NvdjK3oRKhCq
qRs7aNSPOqMu2NbKot4/BtD0hWipF7CAsMqK+241coMUwxRTlqvoe/L7xZ24Ktaj
rm1kk/xNUGP5vWyK8sYfYnDUuLSypRaZ/ZfWuKZgQLDdOw2FWqHFVLoJDsXgsa/y
i1F3b5l4+F36vN+7pbS9YIMmjdmKng8J/hsTPETZudayEWuAy+mNaz4M7ZtxS/gP
TIJcxIxC27PLOhA1XsABunaNR8Ety6ghsZX2YEYnnpcyB5Mmqi0VOJs6m5IZn2kf
1P3x0KaUQ2Fm9wqAkgYpSccWH4yytVQ8lzlpBwIDAQABAoIBAH3s5w5Msj5C3Un6
nTEMU82RZlqVbF7RjYANx5ATN6w+IgCSvhZG9Ll1KpPFqI41zNQs295Vc/tJeUtX
6lKovk8fu9a5QlcaMzYrxYHydHqBEA9iES5qrlFHp++FEIgRZO8IyPkZOJzfconE
PHWWayJR7ZFXTXdnlEwP7SHBTCWJ0PIRoNQEkOMX+tsbbS5w5kIpWNUx9YJzLezt
YSy/9RLLuhioq7ElBM6rgb3jn37W9+yhSsD+9nbQCePS5BoEzrwxZ298pyYpX/2B
DPKJ5RegClKJqGgBYjcit0n5fyzis01tzPRKGl/VjOFEEcKvoi3TLodORGCQks8q
5TVkt+ECgYEA+wRQOq8zcsBq+5+4PjML9KHxtkcug2gfD+5PtY7nvM9ndxmk3DC/
87mE30LlXjEHt1zp5XWWsoVadjedZ9b+H5RUS2b3qxgqR6v2GAgGkdz3zf9ZgsO7
lqHY6pnmKjXGRZ3w5fneVPeI0fQ3l77WpUUOAM9PGVKjpnLKBBKx5DcCgYEAzGkc
IT8SBPXBd+yYFNNnLjj6jIBnRC/giiRoepO9Ojf2ZGUzFT1sLYG0//gtn/rdru57
Y0FOwsA6AhYXJa+5oEBdARWdGJIBz9EQbuVidK/wj7wAqvIvOeGp1TnzMxAz1+8v
CGVw22nxqtCguPzeKEZmzm3kagJuApfxiEp42bECgYEAw8ZHdJ20uKkOR5X4srpJ
dtDfnlTCGEcbAufRTz9XylDQ13kutXVoIITu9tpL3jzLUd2rpwUhNbcAKPeTUqvB
o4uievSh8dV1FFUwKOoJhbYbp5SikXRrWD5+2eqSMxWhwCZA/nz1RLuTAH1C5p02
98t18ne9r3henrEkkiyqhd0CgYBH2XplxUGUNL34ZVVfnJ9cA/Mth8TElv+aDwoa
a+vLlvgoednm0VxA8qKohpei8A8T+ges77u7gM3jBdjFCmt5BKasRuidRlUUsyvP
jxl4Yo9wNmkVrWMkOUn1BRWTEVLnx88EaIOu3CJyJDsaSufbyENCtCXhjVEV4Eqp
2WN5QQKBgDHr6hoSHRNWpC6ruuaFF8MGrV8mnvWbCn9KUxQ6zWbm6hQSyEa/3b4d
kc9GOsm4n+EVnWyhUVjwxEExaCRuFa4aJ/ekLZYtepNnd9Nsoknqd1SVW163QjrY
tY4IM9IaSC2LuPFVc0Kx6TwObdeQScOokIxL3HfayfLKieTLC+w2
-----END RSA PRIVATE KEY-----
}.freeze

      @@PUBKEY = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDIboBIvdtZLruuwDksO8qd90IFqArrUHksiv4292MrehEqEKqpGzto1I86oy7Y1sqi3j8G0PSFaKkXsICwyor7bjVygxTDFFOWq+h78vvFnbgq1qOubWST/E1QY/m9bIryxh9icNS4tLKlFpn9l9a4pmBAsN07DYVaocVUugkOxeCxr/KLUXdvmXj4Xfq837ultL1ggyaN2YqeDwn+GxM8RNm51rIRa4DL6Y1rPgztm3FL+A9MglzEjELbs8s6EDVewAG6do1HwS3LqCGxlfZgRieelzIHkyaqLRU4mzqbkhmfaR/U/fHQppRDYWb3CoCSBilJxxYfjLK1VDyXOWkH kitchen-qemu'.freeze

      @@ARCHBINARY = {
        'i386'   => 'qemu-system-i386',
        'amd64'  => 'qemu-system-x86_64',
        'x86'    => 'qemu-system-i386',
        'x86_64' => 'qemu-system-x86_64',
        '32bit'  => 'qemu-system-i386',
        '64bit'  => 'qemu-system-x86_64',
      }.freeze

      def privkey_path
        File.join(config[:kitchen_root], '.kitchen', 'kitchen-qemu.key')
      end

      def monitor_path
        File.join('.kitchen', "#{instance.name}.qmp")
      end

      def serial_path
        File.join('.kitchen', "#{instance.name}.mon")
      end

      def create_privkey
        path = privkey_path
        return true if File.file?(path)
        File.open(path, File::CREAT|File::TRUNC|File::RDWR, 0600) { |f| f.write(@@PRIVKEY) }
      end

      def random_free_port(host, min, max)
        loop do
          port = rand(max - min) + min
          begin
            serv = TCPServer.new(host, port)
          rescue Errno::EADDRINUSE
            # do nothing
          else
            serv.close
            return port
          end
        end
      end

      def cleanup!
        begin
          File.delete(monitor_path)
        rescue Errno::ENOENT
          # do nothing
        end
        begin
          File.delete(serial_path)
        rescue Errno::ENOENT
          # do nothing
        end
      end

    end
  end
end

# vim: set ts=2 sw=2 et:
