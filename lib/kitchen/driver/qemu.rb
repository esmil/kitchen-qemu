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

      default_config :arch,      'x86_64'
      default_config :username,  'kitchen'
      default_config :password,  'kitchen'
      default_config :port,      2222
      default_config :display,   'none'
      default_config :memory,    '512'
      default_config :nic_model, 'virtio'

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
        config[:vga] = 'qxl' if config[:spice] && !config[:vga]
        self
      end

      # Creates a QEMU instance.
      #
      # @param state [Hash] mutable instance and driver state
      # @raise [ActionFailed] if the action could not be completed
      def create(state)
        monitor = monitor_qmp_path
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

        fqdn = config[:vm_hostname] || instance.name
        hostname = fqdn.match(/^([^.]+)/)[0]

        state[:hostname] = 'localhost'
        state[:port]     = config[:port]
        state[:username] = config[:username]
        state[:password] = config[:password]

        cmd = [
          config[:binary], '-daemonize',
          '-display', config[:display].to_s,
          '-chardev', "socket,id=mon-qmp,path=#{monitor},server,nowait",
          '-mon', 'chardev=mon-qmp,mode=control,default',
          '-chardev', "socket,id=mon-rdl,path=#{monitor_readline_path},server,nowait",
          '-mon', 'chardev=mon-rdl,mode=readline',
          '-m', config[:memory].to_s,
          '-net', "nic,model=#{config[:nic_model]}",
          '-net', "user,net=192.168.1.0/24,hostname=#{hostname},hostfwd=tcp::#{state[:port]}-:22",
          '-device', 'virtio-scsi-pci,id=scsi',
          '-device', 'scsi-hd,drive=root',
          '-drive', "if=none,id=root,readonly,file=#{config[:image]}",
          '-snapshot',
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

        if hostname == fqdn
          names = fqdn
        else
          names = "#{fqdn} #{hostname}"
        end

        info 'Waiting for SSH..'
        conn = instance.transport.connection(state)
        conn.wait_until_ready
        conn.execute("sudo sh -c 'echo 127.0.0.1 #{names} >> /etc/hosts; hostnamectl set-hostname #{hostname} || hostname #{hostname} || true' 2>/dev/null")
        conn.execute('install -dm700 "$HOME/.ssh"')
        conn.execute("echo '#{@@PUBKEY}' > \"$HOME/.ssh/authorized_keys\"")
        conn.close
        state[:ssh_key] = privkey_path
      end

      # Destroys an instance.
      #
      # @param state [Hash] mutable instance state
      # @raise [ActionFailed] if the action could not be completed
      def destroy(state)
        monitor = monitor_qmp_path
        return unless File.exist?(monitor)

        instance.transport.connection(state).close

        begin
          mon = QMPClient.new(UNIXSocket.new(monitor), 2)
          info 'Quitting QEMU..'
          mon.execute('quit')
          mon.wait_for_eof(5)
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

      def monitor_qmp_path
        File.join(config[:kitchen_root], '.kitchen', "#{instance.name}.qmp")
      end

      def monitor_readline_path
        File.join(config[:kitchen_root], '.kitchen', "#{instance.name}.mon")
      end

      def create_privkey
        path = privkey_path
        return true if File.file?(path)
        File.open(path, File::CREAT|File::TRUNC|File::RDWR, 0600) { |f| f.write(@@PRIVKEY) }
      end

      def cleanup!
        begin
          File.delete(monitor_qmp_path)
        rescue Errno::ENOENT
          # do nothing
        end
        begin
          File.delete(monitor_readline_path)
        rescue Errno::ENOENT
          # do nothing
        end
      end

    end
  end
end

# vim: set ts=2 sw=2 et:
