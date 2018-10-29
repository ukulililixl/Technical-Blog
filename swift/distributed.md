# Distributed Mode of OpenStack Swift

##### prepare vm

We first prepare three vms to test deploying OpenStack Swift using real distributed mode

* swift1  (proxy-server)
  * ip: 172.16.83.159
* swift2 (account-server, container-server, object-server)
  * ip: 172.16.83.157
* swift3 (account-server, container-server, object-server)
  * ip: 172.16.83.158
* swift4 (account-server, container-server, object-server)
  * ip: 172.16.83.160

######System configurations in common of all the vms

**The following operations are performed on all the vms**

* system

  * ubuntu 16.04

* root permission 

  ```bash
  $> sudo visudo

  Defaults env_keep += "http_proxy https_proxy socks_proxy ftp_proxy no_proxy"
  xiaolu ALL=(ALL:ALL) ALL
  xiaolu ALL=(ALL) NOPASSWD: ALL
  ```

* edit /etc/hosts

* configure ssh without passwd

  ```bash
  $> ssh-keygen
  $> ssh-copy-id xiaolu@ip
  ```

* set proxy if needed

  ```bash
  # edit .bashrc
  export http_proxy=
  export no_proxy=
  ```

* install dependencies for swift

  ```bash
  $> sudo apt-get update
  $> sudo apt-get install curl gcc memcached rsync sqlite3 xfsprogs \
                       git-core libffi-dev python-setuptools \
                       liberasurecode-dev libssl-dev
  $> sudo apt-get install python-coverage python-dev python-nose \
                       python-xattr python-eventlet \
                       python-greenlet python-pastedeploy \
                       python-netifaces python-pip python-dnspython \
                       python-mock
  ```

##### prepare dir for proxy

```bash
$> sudo mkdir -p /var/run/swift
$> sudo chown -R ${USER}:${USER} /var/run/swift
```

#####prepare loop device in storage node

In each swift2, swift3 and swift4 which we will run storage service:

```bash
$> sudo mkdir /srv
$> sudo truncate -s 1GB /srv/swift-disk
$> sudo mkfs.xfs /srv/swift-disk
$> sudo vim /etc/fstab
/srv/swift-disk /mnt/sdb1 xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0

$> sudo mkdir /mnt/sdb1
$> sudo mount /mnt/sdb1
$> sudo mkdir /mnt/sdb1/store
$> sudo chown ${USER}:${USER} /mnt/sdb1/*
$> sudo ln -s /mnt/sdb1/store /srv/store
$> sudo mkdir -p /srv/store/sdb1 /srv/store/sdb2
$> sudo mkdir -p /var/run/swift
$> sudo chown -R ${USER}:${USER} /var/run/swift
$> sudo chown -R ${USER}:${USER} /srv/store/

$> sudo vim /etc/rc.local

mkdir -p /var/cache/swift 
chown xiaolu:xiaolu /var/cache/swift
mkdir -p /var/run/swift
chown xiaolu:xiaolu /var/run/swift

exit 0

$> cd ~
$> truncate -s 1GB xfs_file
$> mkfs.xfs xfs_file
$> sudo mount -o loop,noatime,nodiratime xfs_file /tmp
$> sudo chmod -R 1777 /tmp
$> sudo vim /etc/fstab
/home/xiaolu/xfs_file /tmp xfs rw,noatime,nodiratime,attr2,inode64,noquota 0 0
```

##### get code

in swift1-4:

```bash
$> cd $HOME; git clone https://github.com/openstack/python-swiftclient.git
$> cd $HOME/python-swiftclient; sudo python setup.py develop; cd -
$> git clone https://github.com/openstack/swift.git
$> cd $HOME/swift; sudo pip install --no-binary cryptography -r requirements.txt; sudo python setup.py develop; cd -
```

##### rsync

in swift1:

edit /etc/rsyncd.conf

```ini
uid = xiaolu
gid = xiaolu
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid
address = 172.16.83.159
# in swift2: 172.16.83.157
# in swift3: 172.16.83.158
# in swift4: 172.16.83.160

[account]
max connections = 25
path = /srv/store
read only = false
lock file = /var/lock/account.lock

[container]
max connections = 25
path = /srv/store
read only = false
lock file = /var/lock/container.lock

[object]
max connections = 25
path = /srv/store
read only = false
lock file = /var/lock/object.lock
```

edit /etc/default/rsync

```bash
RSYNC_ENABLE=true
```

start rsync daemon

```bash
$> sudo systemctl enable rsync
$> sudo systemctl start rsync
```

to check rsync in swift1

```bash
$> rsync rsync://pub@172.16.83.159
```

For swift2, swift3 and swift4, we perform similar operations, except that ip is different in each vm.

##### memcached

In all nodes:

```bash
$> sudo vim /etc/memcached.conf
-l 0.0.0.0
$> sudo systemctl enable memcached.service
$> sudo systemctl restart memcached.service
```

##### rsyslog

for swift1:

```bash
$> sudo vim /etc/rsyslog.d/10-swift.conf
local1.*;local1.!notice /var/log/swift/proxy.log
local1.notice           /var/log/swift/proxy.error
local1.*                ~
```

for swift2:

```bash
$> sudo vim /etc/rsyslog.d/10-swift.conf
local1.*;local1.!notice /var/log/swift/storage1.log
local1.notice           /var/log/swift/storage1.error
local1.*
```

for swift3:

```bash
$> sudo vim /etc/rsyslog.d/10-swift.conf
local1.*;local1.!notice /var/log/swift/storage2.log
local1.notice           /var/log/swift/storage2.error
local1.*
```

for swift4:

```bash
$> sudo vim /etc/rsyslog.d/10-swift.conf
local1.*;local1.!notice /var/log/swift/storage3.log
local1.notice           /var/log/swift/storage3.error
local1.*
```

Then in each node:

```bash
$> sudo vim /etc/rsyslog.conf

$PrivDropToGroup adm
$> sudo mkdir -p /var/log/swift
$> sudo chown -R syslog.adm /var/log/swift
$> sudo chmod -R g+w /var/log/swift
$> sudo service rsyslog restart
```

#####configure

######swift1

```bash
$> sudo rm -rf /etc/swift
$> sudo mkdir /etc/swift
$> sudo chown -R ${USER}:${USER} /etc/swift
```

swift.conf; proxy-server.conf;

add `/etc/swift/swift.conf`

```ini
[swift-hash]
# random unique strings that can never change (DO NOT LOSE)
# Use only printable chars (python -c "import string; print(string.printable)")
swift_hash_path_prefix = changeme
swift_hash_path_suffix = changeme

[storage-policy:0]
name = gold
policy_type = replication
default = yes

[storage-policy:1]
name = silver
policy_type = replication

[storage-policy:2]
name = ec42
policy_type = erasure_coding
ec_type = liberasurecode_rs_vand
ec_num_data_fragments = 4
ec_num_parity_fragments = 2
```

add `proxy-server.conf`

```ini
[DEFAULT]
bind_ip = 172.16.83.159
bind_port = 8080
workers = 1
user = xiaolu
log_facility = LOG_LOCAL1
eventlet_debug = true

[pipeline:main]
# Yes, proxy-logging appears twice. This is so that
# middleware-originated requests get logged too.
pipeline = healthcheck proxy-logging cache tempauth proxy-logging proxy-server

[filter:healthcheck]
use = egg:swift#healthcheck

[filter:proxy-logging]
use = egg:swift#proxy_logging

[filter:tempauth]
use = egg:swift#tempauth
user_admin_admin = admin .admin .reseller_admin
user_test_tester = testing .admin http://172.16.83.159:8080/v1/AUTH_test
user_test_tester2 = testing2 .admin
user_test_tester3 = testing3
user_test2_tester2 = testing2 .admin

[filter:cache]
use = egg:swift#memcache
memcache_servers = 172.16.83.159:11211

[app:proxy-server]
use = egg:swift#proxy
allow_account_management = true
account_autocreate = true
```

###### swift2-4

```bash
$> sudo rm -rf /etc/swift
$> sudo mkdir /etc/swift
$> sudo chown -R ${USER}:${USER} /etc/swift
$> mkdir /etc/swift/account-server
$> mkdir /etc/swift/container-server
$> mkdir /etc/swift/object-server
```

add configuration for account-server: /etc/swift/account-server/1.conf

```ini
[DEFAULT]
devices = /srv/store
mount_check = false
disable_fallocate = true
bind_ip = 172.16.83.157  # different vm use different ip
bind_port = 6012
workers = 1
user = xiaolu
log_facility = LOG_LOCAL1
recon_cache_path = /var/cache/swift
eventlet_debug = true

[pipeline:main]
pipeline = healthcheck recon account-server

[app:account-server]
use = egg:swift#account

[filter:recon]
use = egg:swift#recon

[filter:healthcheck]
use = egg:swift#healthcheck

[account-replicator]
rsync_module = {replication_ip}::account{replication_port}

[account-auditor]

[account-reaper]
```

add configuration for container-server: /etc/swift/container-server/1.conf

```ini
[DEFAULT]
devices = /srv/store
mount_check = false
disable_fallocate = true
bind_ip = 172.16.83.157
bind_port = 6011
workers = 1
user = xiaolu
log_facility = LOG_LOCAL1
recon_cache_path = /var/cache/swift
eventlet_debug = true

[pipeline:main]
pipeline = healthcheck recon container-server

[app:container-server]
use = egg:swift#container

[filter:recon]
use = egg:swift#recon

[filter:healthcheck]
use = egg:swift#healthcheck

[container-replicator]
rsync_module = {replication_ip}::container{replication_port}

[container-updater]

[container-auditor]

[container-sync]

[container-sharder]
auto_shard = true
rsync_module = {replication_ip}::container{replication_port}
# This is intentionally much smaller than the default of 1,000,000 so tests
# can run in a reasonable amount of time
shard_container_threshold = 100
# The probe tests make explicit assumptions about the batch sizes
shard_scanner_batch_size = 10
cleave_batch_size = 2
```

add configuration file for object-server: /etc/swift/object-server/1.conf

```ini
[DEFAULT]
devices = /srv/store
mount_check = false
disable_fallocate = true
bind_ip = 172.16.83.157
bind_port = 6010
workers = 1
user = xiaolu
log_facility = LOG_LOCAL1
recon_cache_path = /var/cache/swift
eventlet_debug = true

[pipeline:main]
pipeline = healthcheck recon object-server

[app:object-server]
use = egg:swift#object

[filter:recon]
use = egg:swift#recon

[filter:healthcheck]
use = egg:swift#healthcheck

[object-replicator]
rsync_module = {replication_ip}::object{replication_port}

[object-reconstructor]

[object-updater]

[object-auditor]
```

/etc/swift/swift.conf

```ini
[swift-hash]
# random unique strings that can never change (DO NOT LOSE)
# Use only printable chars (python -c "import string; print(string.printable)")
swift_hash_path_prefix = changeme
swift_hash_path_suffix = changeme

[storage-policy:0]
name = gold
policy_type = replication
default = yes

[storage-policy:1]
name = silver
policy_type = replication

[storage-policy:2]
name = ec42
policy_type = erasure_coding
ec_type = liberasurecode_rs_vand
ec_num_data_fragments = 4
ec_num_parity_fragments = 2
```

##### remakering

```bash
#!/bin/bash

set -e

# clean ring in all nodes
for i in 1 2 3 4
do
ssh swift$i "cd /etc/swift; rm -f *.builder *.ring.gz backups/*.builder backups/*.ring.gz"
done

# create ring in proxy node
cd /etc/swift

# create account ring
swift-ring-builder account.builder create 10 3 1
swift-ring-builder account.builder add r1z1-172.16.83.157:6012/sdb1 1
swift-ring-builder account.builder add r1z2-172.16.83.158:6012/sdb1 1
swift-ring-builder account.builder add r1z3-172.16.83.160:6012/sdb1 1
swift-ring-builder account.builder rebalance

# create container ring
swift-ring-builder container.builder create 10 3 1
swift-ring-builder container.builder add r1z1-172.16.83.157:6011/sdb2 1
swift-ring-builder container.builder add r1z2-172.16.83.158:6011/sdb2 1
swift-ring-builder container.builder add r1z3-172.16.83.160:6011/sdb2 1
swift-ring-builder container.builder rebalance

# create default obj ring
swift-ring-builder object.builder create 10 3 1
swift-ring-builder object.builder add r1z1-172.16.83.157:6010/sdb1 1
swift-ring-builder object.builder add r1z2-172.16.83.158:6010/sdb1 1
swift-ring-builder object.builder add r1z3-172.16.83.160:6010/sdb1 1
swift-ring-builder object.builder rebalance

# create obj ring for policy:1
swift-ring-builder object-1.builder create 10 2 1
swift-ring-builder object-1.builder add r1z1-172.16.83.157:6010/sdb1 1
swift-ring-builder object-1.builder add r1z2-172.16.83.158:6010/sdb2 1
swift-ring-builder object-1.builder rebalance

# create objring for policy:2
swift-ring-builder object-2.builder create 10 6 1
swift-ring-builder object-2.builder add r1z1-172.16.83.157:6010/sdb1 1
swift-ring-builder object-2.builder add r1z1-172.16.83.157:6010/sdb2 1
swift-ring-builder object-2.builder add r1z2-172.16.83.158:6010/sdb1 1
swift-ring-builder object-2.builder add r1z2-172.16.83.158:6010/sdb2 1
swift-ring-builder object-2.builder add r1z3-172.16.83.160:6010/sdb1 1
swift-ring-builder object-2.builder add r1z3-172.16.83.160:6010/sdb2 1
swift-ring-builder object-2.builder rebalance

# distribute ring to all node
for i in 2 3 4
do
scp *.ring.gz swift$i:/etc/swift
done
```

##### startswift.sh

```bash
#!/bin/bash

set -e

# start proxy
swift-init proxy start

# start storage
for i in 2 3 4
do
ssh swift$i "swift-init account start; swift-init container start; swift-init object start"
done
```

##### stopswift.sh

```bash
#!/bin/bash

set -e

# stop proxy
swift-init proxy kill

# stop storage
for i in 2 3 4
do
ssh swift$i "swift-init account kill; swift-init container kill; swift-init object kill"
done
```

##### .bashrc

```bash
# swift authentication
export ST_AUTH="http://172.16.83.159:8080/auth/v1.0"
export ST_USER="test:tester"
export ST_KEY="testing"
```

##### testec.sh

```bash
#!/bin/bash

set -e

swift post -H 'X-Storage-Policy: ec42' container1

cd ~
swift upload container1 4M
cd -
```









