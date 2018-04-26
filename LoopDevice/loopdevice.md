# Loop Device in Linux

update 20180426

We can create a file, and then use this file as if it is a block device.

```bash
$> dd if=/dev/zero of=./loopdevice bs=1048576 count=1024
```

Next, we format this file with a specific file system type. e.g. ext4

```bash
$> mkfs.ext4 ./loopdevice 
mke2fs 1.42.13 (17-May-2015)
Discarding device blocks: done                            
Creating filesystem with 262144 4k blocks and 65536 inodes
Filesystem UUID: c41d42ff-58e4-44d8-88a7-dc043b2a4171
Superblock backups stored on blocks: 
	32768, 98304, 163840, 229376

Allocating group tables: done                            
Writing inode tables: done                            
Creating journal (8192 blocks): done
Writing superblocks and filesystem accounting information: done
```

Next, we mount this loopdevice

```bash
$> losetup /dev/loop2 ./loopdevice
$> mkdir looptmp
$> mount /dev/loop2 ./looptmp/
```

Now we can check the content in our mount point

```bash
$> ls looptmp
lost+found
```

This is the basic content of ext4???

unmount

```bash
$> sudo umount /dev/loop2
$> sudo losetup -d /dev/loop2
```



