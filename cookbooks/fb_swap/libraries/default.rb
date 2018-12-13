# vim: syntax=ruby:expandtab:shiftwidth=2:softtabstop=2:tabstop=2
# Copyright (c) 2016-present, Facebook, Inc.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree. An additional grant
# of patent rights can be found in the PATENTS file in the same directory.
#
#

module FB
  module FbSwap
    ENCRYPTED_DEVICE_MAPPER_NAME = 'encrypted_swap'.freeze
    ENCRYPTED_DEVICE_NAME = "/dev/mapper/#{ENCRYPTED_DEVICE_MAPPER_NAME}".freeze

    def self.get_base_swap_device_from_crypttab
      return nil unless File.exist?('/etc/crypttab')

      encrypted_crypttab_line =
        File.read('/etc/crypttab').each_line.select do |line|
          line.split[0] == FB::FbSwap::ENCRYPTED_DEVICE_MAPPER_NAME
        end

      if encrypted_crypttab_line.any?
        return encrypted_crypttab_line[0].split[1]
      else
        return nil
      end
    end

    def self.get_base_swap_device(node)
      from_crypttab = get_base_swap_device_from_crypttab
      return from_crypttab if from_crypttab

      swap_mounts = node['filesystem2']['by_device'].to_hash.select do |k, v|
        v['fs_type'] == 'swap' && k != FB::FbSwap::ENCRYPTED_DEVICE_NAME
      end

      case swap_mounts.count
      when 0
        return nil
      when 1
        return swap_mounts.keys[0]
      else
        fail 'More than one swap mount found, this is not right.'
      end
    end

    def self.get_swap_uuid_from_fstab(node)
      fstab_swap_line =
        FB::Fstab.base_fstab_contents(node).each_line.select do |line|
          line.split[1] == 'swap'
        end

      return nil if fstab_swap_line.empty?

      if fstab_swap_line[0].split[0] =~ /UUID=(\S*)/
        return $1
      end

      return nil
    end

    def self.get_current_swap_device(node)
      if node['fb_swap']['enable_encryption'] &&
         !get_swap_uuid_from_fstab(node).nil?
        return FB::FbSwap::ENCRYPTED_DEVICE_NAME
      else
        return get_base_swap_device(node)
      end
    end

    def self.get_current_swap_device_uuid(node)
      device = get_current_swap_device(node)
      so = Mixlib::ShellOut.new(
        "/sbin/blkid --match-token TYPE=swap --output export #{device}",
      ).run_command
      so.stdout.each_line do |line|
        if line =~ /UUID=(\S*)/
          return $1
        end
      end

      return nil
    end

    def self._root_filesystem(node)
      node['filesystem2']['by_mountpoint']['/']
    end

    def self.get_current_swap_unit(node)
      return FB::Systemd.path_to_unit(
        get_current_swap_device(node),
        'swap',
      )
    end

    def self.swap_file_possible?(node)
      if _root_filesystem(node)['fs_type'] == 'btrfs'
        # The historical take on btrfs is that swap files are not supported.
        # This is changing soon (4.16+?). There's no feature test for this
        # (yet?) so we'll be pessimistic and say no.
        Chef::Log.warn('fb_swap: Swap file not generally possible on btrfs')
        return false
      end
      return self._root_on_rotational?(node)
    end

    def self._root_on_rotational?(node)
      _root_filesystem(node)['devices'].each do |dev|
        match = %r/\/dev\/(?<block>[[:alpha:]]+)[[:digit:]]/.match(dev)
        # assert we can find a block device name in here
        return false unless match
        block_device = match['block']
        if node['devices'][block_device]['rotational'] == '1'
          Chef::Log.warn(
            'fb_swap: Swap file not possible due to rotational device ' +
            block_device,
          )
          return false
        end
      end
      Chef::Log.debug(
        'fb_swap: Swap file possible (no rotational device members on root ' +
        'filesytem)',
      )
      return true
    end
  end
end
