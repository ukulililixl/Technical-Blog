# object-reconstructor

Before we discuss the reconstruction process of swift, we first need to figure out what metadata does swift stores. 

###### EC operations we discuss in this notes

* original object size: 4M
* swift segment size: 1M
* EC configuration (k=4, m=2)
* Process
  * In **proxy-server**, a **segment** is divided into 4 **fragments** and 2 additional **fragments** are calculated as parity fragments. 6 **fragments** are sent to 6 different storage divices in total according to object-ring for our erasure coding policy.
  * As our original object is 4M, each device holds 4 fragments, which is 1M in total.

We first take a look at disk file in node4:

```bash
└── 4
    └── node
        ├── sdb4
        │   ├── accounts
        │   │   └── 802
        │   │       └── 178
        │   │           └── c8bcccab3ddbfdc34b08e9223f4f5178
        │   │               ├── c8bcccab3ddbfdc34b08e9223f4f5178.db
        │   │               └── c8bcccab3ddbfdc34b08e9223f4f5178.db.pending
        │   ├── objects-2
        │   │   └── 341
        │   │       ├── ea5
        │   │       │   └── 5564ca7addd2096f6cbf7cfc31b8eea5
        │   │       │       └── 1540036499.00571#2#d.data
        │   │       ├── hashes.invalid
        │   │       └── hashes.pkl
        │   └── objects-3
        └── sdb8
            └── objects-2
```

`1540036499.00571#2#d.data` is the erasure-coded data with ec-index equals to 2. If we take a look at the file size, we find that is larger than `1M (1048576 bytes)`. Actually, this disk file is `1048896` bytes.

###### What are additional bytes added into disk file?

**Additional data added to user data comes from PyECLib, which is opaque to OpenStack Swift!**. When swift call PyECLib to encode a segment, it divides them into 4 fragments and return 6 encoded-fragments, each of which is added 80 bytes more data. These data are needed by PyECLib.

###### Where is the metadata?

Swift stores all metadata in file attribute! We can write a program and take look at the file attribute of this disk file:

```python
import collections
import errno
import xattr
import pickle
import sys
from hashlib import md5

etag_hasher = md5()
frag_hashers = collections.defaultdict(md5)

METADATA_KEY = b'user.swift.metadata'
METADATA_CHECKSUM_KEY = b'user.swift.metadata_checksum'

diskfile=sys.argv[1]
fd=open(diskfile)
metadata=b''
key=0
try:
    while True:
        metadata += xattr.getxattr(
            fd, METADATA_KEY + str(key or '').encode('ascii'))
        key += 1
except (IOError, OSError) as e:
    if errno.errorcode.get(e.errno) in ('ENOTSUP', 'EOPNOTSUPP'):
        msg = "Filesystem at %s does not support xattr"
        print msg
    if e.errno == errno.ENOENT:
        print "File does not exist"
metadata_checksum = None
try:
    metadata_checksum = xattr.getxattr(fd, METADATA_CHECKSUM_KEY)
except (IOError, OSError):
    print "Error getting checksum"

if metadata_checksum:
    computed_checksum = md5(metadata).hexdigest().encode('ascii')
metadata = pickle.loads(metadata)
print metadata
```

When we run this program to check metadata, we can see the following output:

```bash
{'Content-Length': '1048896', 'name': '/AUTH_test/container1/4M', 'X-Object-Sysmeta-Ec-Frag-Index': '2', 'X-Object-Meta-Mtime': '1539592806.550829', 'X-Object-Sysmeta-Ec-Content-Length': '4194304', 'X-Object-Sysmeta-Ec-Etag': '08e924836480366fe1246b93b132bd14', 'ETag': '00f5c851659911b01bdd73d4e0a3b40f', 'X-Timestamp': '1540036499.00571', 'X-Object-Sysmeta-Ec-Scheme': 'liberasurecode_rs_vand 4+2', 'Content-Type': 'application/octet-stream', 'X-Object-Sysmeta-Ec-Segment-Size': '1048576'}
```

We filter out some information in metadata:

* Content-Length: 1048896
  * This means that the content length stored in this node is 1048896 bytes, which is 4 * (262144 + 80) bytes.
  * For a object-server, it receives data from proxy-server and stores it in local disk. It does not care about the semantics in the content.
* name: `/AUTH_test/container1/4M`
  * account: AUTH_test
  * container: container1
  * object: 4M
  * This name denotes the original object that this fragment belongs to 
* X-Object-Sysmeta-EC-Frag-Index: 2
  * This metadata is special to erasure coding
  * erasure coding index for this fragment is 2
* X-Object-Sysmeta-Ec-Content-Length: 4194304
  * This is the original size of un-coded object
* X-Object-Sysmeta-Ec-Etag:
  * This is the hash value of the original un-coded object
  * This value should be the same for all fragments
* ETag:
  * This is the hash value of current fragment

###### How failure is detected in OpenStack Swift?

Failure detection design in OpenStack Swift is quite different than that in HDFS/QFS, in which a centralized controller (e.g. NameNode/Metadata Server) is responsible to check the integrity of the whole system.

For example, in HDFS-3, NameNode maintains the integrity of DFS via the heartbeat information from DataNodes periodically. DataNodes report to NameNode the physical blocks that store in them. Having the global view of DFS metadata, NameNode is able to detect failures and assign EC tasks (i.e. repair task) to surviving DataNodes. Once the missing blocks are repaired, NameNode updates integrity information via heartbeat information once again.

However, in OpenStack Swift, designs are different. Being designed as a de-centralized storage system. All object data a well as metadata are disseminated in different nodes, as is instructed by the data structure, Ring. How the failure is detected in Swift? **Chatting between neighborhoods**.

If we do not start object-reconstructor, failures cannot be detected and repaired. And this is similar to object-replicator, which is designed for repairing lost replicated-data. 

Before we discuss the steps for reconstruction, we first need to know the whole layout for our erasure-coded object. Note that we ignore the layout for account and container metadata.

```bash
./
├── 1
│   └── node
│       ├── sdb1
│       │   ├── objects-2
│       │   │   └── 341
│       │   │       ├── ea5
│       │   │       │   └── 5564ca7addd2096f6cbf7cfc31b8eea5
│       │   │       │       └── 1540036499.00571#4#d.data
│       │   │       ├── hashes.invalid
│       │   │       └── hashes.pkl
│       │   └── objects-3
│       └── sdb5
│           └── objects-2
│               └── 341
│                   ├── ea5
│                   │   └── 5564ca7addd2096f6cbf7cfc31b8eea5
│                   │       └── 1540036499.00571#0#d.data
│                   ├── hashes.invalid
│                   └── hashes.pkl
├── 2
│   └── node
│       ├── sdb2
│       │   ├── objects-2
│       │   └── objects-3
│       └── sdb6
│           └── objects-2
│               └── 341
│                   ├── ea5
│                   │   └── 5564ca7addd2096f6cbf7cfc31b8eea5
│                   │       └── 1540036499.00571#3#d.data
│                   ├── hashes.invalid
│                   └── hashes.pkl
├── 3
│   └── node
│       ├── sdb3
│       │   ├── objects-2
│       │   │   └── 341
│       │   │       ├── ea5
│       │   │       │   └── 5564ca7addd2096f6cbf7cfc31b8eea5
│       │   │       │       └── 1540036499.00571#5#d.data
│       │   │       ├── hashes.invalid
│       │   │       └── hashes.pkl
│       │   └── objects-3
│       └── sdb7
│           └── objects-2
│               └── 341
│                   ├── ea5
│                   │   └── 5564ca7addd2096f6cbf7cfc31b8eea5
│                   │       └── 1540036499.00571#1#d.data
│                   ├── hashes.invalid
│                   └── hashes.pkl
└── 4
    └── node
        ├── sdb4
        │   ├── objects-2
        │   │   └── 341
        │   │       ├── ea5
        │   │       │   └── 5564ca7addd2096f6cbf7cfc31b8eea5
        │   │       │       └── 1540036499.00571#2#d.data
        │   │       ├── hashes.invalid
        │   │       └── hashes.pkl
        │   └── objects-3
        └── sdb8
            └── objects-2
```



Here are some key steps in object-replicator.

* obtain all the partitions stored in my disk
  * Node1: partition 341 in sdb1; partition 341 in sdb4
  * Node2: partition 341 in sdb6
  * Node3: partition 341 in sdb3; partition 341 in sdb7
  * Node4: partition 341 in sdb4
* collect useful metadata for each partition
  * The most important metadata is the hash value. Especially, **X-Object-Sysmeta-Ec-Etag**, which should be the same in all the object-server corresponding to the same original object.
* For each partition, sync the hash value with it's neighbor.
  * How do we define neighbor? **X-Object-Sysmeta-EC-Frag-Index**
    * e.g. In our example, node 4 holds fragment index 2. For node 4, it's neighbor is the node which holds fragment index 1 and fragment index 3. How does node 4 know the exact nodes that holds these two indices? It can obtain such information from Ring! In our example, node 4 gets the information from Ring and knows the neighborhood node2 (for index 3) and node3 (for index1).
  * The node sends hashvalue to it's neighbor and wait for a response.
    * node4 sends sync to node2 and node3.
    * How does receiver node deal with the sync task? It obtain partition information from incoming message and read metadata information in physical disk. After that returns hash value it maintains to the sender. 
    * If the partition is missing, receiver side just returns an empty hashvalue to sender.
    * If the receiver node is unavailable, sync connect times out after a configured period of time.
  * Once the node gets response message or time out, it compares remote hash values (in the neighbor) with hash value it maintains in disk. 
    * If the hash value is the same, then there is no need to reconstruct fragment in **remote node**.
    * If there is difference between local hash value and remote hash value in the neighborhood, hash values are update to the latest version. 
    * Only the case that my hash value is the latest and remote hash value is invalid can I start a reconstruct job for remote node. (e.g. when frag3 in node2 is missing, node4 knows there should be reconstruction work for frag3 in node2.)
* reconstruct job
  * node4 starts up a reconstruction process for frag3 and sends it to node2.
  * for reconstruction process, it sends request to all nodes that holds surviving fragments one by one. Once it got responses from nodes that holds enough fragments to repair, it can repair lost fragment and send to node.
* Problem: **There can be the case that reconstructor on two nodes detect failure in node2**.
  * In our example, node2 (holds frag3) also have two neighbors
    * node1: frag4
    * node4: frag2
  * Actually, both the nodes detect the failure in node2 and start the reconstruction process. However, only one node successfully finishes the reconstruction process while another node stops, as the receiver (node2) resets the connection.

##### Summary

* Designed with the decentralized feature, all data and metadata are disseminated in all nodes.
* object-reconstructor is designed to detect failure and repair failure, without which OpenStack Swift cannot provide availability for erasure-coded object.
* In OpenStack Swift, reconstruction opts for a 'push' mode.