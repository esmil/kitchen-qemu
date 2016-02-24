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

require 'json'
require 'socket'

module Kitchen
  module Driver
    class QMPClient
      class Timeout < Exception
      end

      def initialize(io, timeout = 1)
        @io = io
        @ioa = [ io ]
        @timeout = timeout
        @buf = []
        readnext(timeout) or raise Timeout
        execute('qmp_capabilities') or raise Timeout
        self
      end

      def execute(cmd, timeout = @timeout)
        send( 'execute' => cmd )
        loop do
          ret = readnext(timeout) or raise Timeout
          if ret['return']
            return ret['return']
          end
        end
      end

      def wait_for_eof(timeout = @timeout)
        while IO.select(@ioa, nil, nil, timeout)
          begin
            @io.read_nonblock(4096)
          rescue EOFError
            return
          rescue Errno::ECONNRESET
            return
          rescue IO::WaitReadable
            # do nothing
          end
        end
        raise Timeout
      end

      def close
        @io.close
      end

      private

      def send(obj)
        @io.write("#{obj.to_json}\r\n")
      end

      def readnext(timeout)
        loop do
          if not @buf.empty? and @buf.last.match("\n")
            s = @buf.pop.split("\n", 2)
            @buf.push(s[0])
            obj = JSON.parse(@buf.join(''))
            @buf.clear
            @buf.push(s[1]) unless s[1].empty?
            return obj
          end

          loop do
            return nil unless IO.select(@ioa, nil, nil, timeout)
            begin
              @buf.push(@io.read_nonblock(4096))
            rescue IO::WaitReadable
              # do nothing
            else
              break
            end
          end
        end
      end
    end
  end
end

# vim: set ts=2 sw=2 et:
