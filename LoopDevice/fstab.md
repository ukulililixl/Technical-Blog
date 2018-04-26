# fstab

What is **fstab**? fstab records the devices as well as the file system informations in the machine.

The path of fstab is **/etc/fstab**

It contains the following information

```bash
# <file system>        <dir>    <type> <options>           <dump> <pass>
```

Here is an example of this file in a amazon ec2 virtual machine:

```bash
LABEL=cloudimg-rootfs   /        ext4   defaults,discard        0 0
/srv/swift-disk /mnt/sdb1 xfs loop,noatime,nodiratime,nobarrier,logbufs=8 0 0
/home/xiaolu/xfs_file /tmp xfs rw,noatime,nodiratime,attr2,inode64,noquota 0 0
```

* file system

  Actually, it is not the file system type as we refers to. Here it means a device.

* dir

  This is to tell where the device should be mounted to.

* type

  This is exactly the file system type such as ext4, ext3, xfs ...

* options

  * default=[rw,suid,dev,exec,auto,nouser,async]
  * rw: mount as read/write device
  * suid: ?
  * dev
  * exec: binary files in this folder can be executable
  * auto: It is mounted automatically at the start up
  * async: I/O is in async manner

* dump

  * Whether to back up this file system
  * 0: do not backup
  * 1: reversly

* pass

  * fsck check the integer under this tab.
  * 0: not be checked by fsck

