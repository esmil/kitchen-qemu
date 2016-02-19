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

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kitchen/driver/qemu_version'

Gem::Specification.new do |gem|
  gem.name          = 'kitchen-qemu'
  gem.version       = Kitchen::Driver::QEMU_VERSION
  gem.license       = 'GPL-3.0+'
  gem.authors       = [ 'Emil Renner Berthing' ]
  gem.email         = [ 'esmil@esmil.dk' ]
  gem.description   = 'Kitchen::Driver::Qemu - A QEMU Driver for Test Kitchen.'
  gem.summary       = gem.description
  gem.homepage      = 'https://github.com/esmil/kitchen-qemu/'

  gem.files         = [ # `git ls-files`.split($/)
    'lib/kitchen/driver/qemu_version.rb',
    'lib/kitchen/driver/qemu.rb',
    'lib/kitchen/driver/qmpclient.rb',
  ]
  gem.executables   = []
  gem.require_paths = [ 'lib' ]

  gem.add_dependency 'test-kitchen', '~> 1.4'
end
