#
# Cookbook Name:: fb_logrotate
# Recipe:: default
#
# vim: syntax=ruby:expandtab:shiftwidth=2:softtabstop=2:tabstop=2
#
# Copyright (c) 2016-present, Facebook, Inc.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree. An additional grant
# of patent rights can be found in the PATENTS file in the same directory.
#

if node.macosx?
  template '/etc/newsyslog.d/fb_bsd_newsyslog.conf' do
    source 'fb_bsd_newsyslog.conf.erb'
    mode '0644'
    owner 'root'
    group 'root'
  end
  return
end

# assume linux from here onwards

include_recipe 'fb_logrotate::packages'

whyrun_safe_ruby_block 'munge logrotate configs' do
  block do
    node['fb_logrotate']['configs'].to_hash.each do |name, block|
      if block['overrides']
        if block['overrides']['rotation'] == 'weekly' &&
           !block['overrides']['rotate']
          node.default['fb_logrotate']['configs'][name][
            'overrides']['rotate'] = '4'
        end
        if block['overrides']['size']
          time = "size #{block['overrides']['size']}"
        elsif %w{hourly weekly monthly yearly}.include?(
          block['overrides']['rotation'],
        )
          time = block['overrides']['rotation']
        end
      end
      if time
        node.default['fb_logrotate']['configs'][name]['time'] = time
      end
    end
  end
end

whyrun_safe_ruby_block 'validate logrotate configs' do
  block do
    files = []
    node['fb_logrotate']['configs'].to_hash.each_value do |block|
      files += block['files']
    end
    if files.uniq.length < files.length
      fail 'fb_logrotate: there are duplicate logrotate configs!'
    else
      dfiles = []
      tocheck = []
      files.each do |f|
        if f.end_with?('*')
          dfiles << ::File.dirname(f)
        else
          tocheck << f
        end
      end
      tocheck.each do |f|
        if dfiles.include?(::File.dirname(f))
          fail "fb_logrotate: there is an overlapping logrotate config for #{f}"
        end
      end
    end
  end
end

template '/etc/logrotate.d/fb_logrotate.conf' do
  source 'fb_logrotate.conf.erb'
  owner 'root'
  group 'root'
  mode '0644'
end

template '/etc/cron.daily/logrotate' do
  only_if { node['fb_logrotate']['add_locking_to_logrotate'] }
  source 'logrotate_rpm_cron_override.erb'
  mode '0755'
  owner 'root'
  group 'root'
end

# syslog has been moved into the main fb_logrotate.conf
file '/etc/logrotate.d/syslog' do
  action 'delete'
end
