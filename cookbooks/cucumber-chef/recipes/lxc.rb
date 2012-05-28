#
# Author:: Zachary Patten (<zpatten@jovelabs.com>)
# Cookbook Name:: cucumber-chef
# Recipe:: lxc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#


%w(lxc bridge-utils debootstrap dhcp3-server).each do |p|
  package p
end

# configure dhcp3-server for lxc
bash "configure dhcp3-server" do
  code <<-EOH
cat <<EOF > /etc/dhcp3/dhcpd.conf
ddns-update-style none;

default-lease-time 600;
max-lease-time 7200;
log-facility local7;

include "/etc/dhcp3/lxc.conf";
EOF
  EOH
end

# configure bridge-utils for lxc
bash "configure bridge-utils" do
  code <<-EOH
cat <<EOF >> /etc/network/interfaces

# The bridge network interface
auto br0
iface br0 inet static
address 192.168.255.254
netmask 255.255.0.0
pre-up brctl addbr br0
post-down brctl delbr br0
EOF
  EOH

  not_if "ip link ls dev br0"
end

# enable ipv4 packet forwarding
execute "sysctl -w net.ipv4.ip_forward=1" do
  not_if "ip link ls dev br0"
end

# enable nat'ing of all outbound traffic
execute "iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE" do
  not_if "ip link ls dev br0"
end

# restart the network so our changes take immediate effect
execute "/etc/init.d/networking restart" do
  not_if "ip link ls dev br0"
end

# create the cgroup device
directory "/cgroup"

mount "/cgroup" do
  device "cgroup"
  fstype "cgroup"
  pass 0
  action [:mount, :enable]
end

# create a configuration directory for lxc
directory "/etc/lxc"

# load the chef client into our distro lxc cache
install_chef_sh = "/tmp/install-chef.sh"
distros = %w(ubuntu)
arch = (%x(arch).include?("i686") ? "i386" : "amd64")

template "/etc/lxc/initializer" do
  source "lxc-initializer-config.erb"
end

distros.each do |distro|
  cache_rootfs = "/var/cache/lxc/#{distro}/rootfs-#{arch}"

  execute "lxc-create -n initializer -f /etc/lxc/initializer -t #{distro}"

  execute "lxc-destroy -n initializer"

  template "#{cache_rootfs}#{install_chef_sh}" do
    source "lxc-install-chef.erb"
    mode "0755"
  end

  execute "chroot #{cache_rootfs} /bin/bash -c '#{install_chef_sh}'"
end
