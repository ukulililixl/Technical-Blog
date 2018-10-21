# operation

##### stat

```bash
$> swift stat
```

The request is issued by command line tools in package `python-swiftclient`.

`swift.proxy.server` first deal with this incoming request in `handle_request`. It first figures out corresponding controller that should furtherly deal with the request, which is `swift.proxy.controllers.account.AccountController`. Then `AccountController` deal with the request in method `GETorHead`. Inside this method, `account_listing_response` is called. Note that this method is in `swift.account.util`. From this point, account server start to take the responsibility. As we just start out swift cluster and haven't performed any operations, so `broker` in account server is `None`. To response the request, account server create a `FakeAccountBroker`, in which the number of containers equals to 0, as is the same with the number of objects. Finally, such information is returned to us. So we can see the output like this:

```bash
               Account: AUTH_test
            Containers: 0
               Objects: 0
                 Bytes: 0
       X-Put-Timestamp: 1539366099.79100
           X-Timestamp: 1539366099.79100
            X-Trans-Id: tx3c2845bf6e88444190aeb-005bc0dcd3
          Content-Type: text/plain; charset=utf-8
X-Openstack-Request-Id: tx3c2845bf6e88444190aeb-005bc0dcd3
```

**XL:** What is the usage of *broker*? When will it be created?

##### create container

```bash
$> swift post container1
```

This command create a container called `container1` under our storage account `AUTH_test`.

`swift.proxy.server` first figures out corresponding controller for this request, which is `swift.proxy.controllers.container.ContainerController`. Then `ContainerController` deal with the request in method `POST`. Inside this method, it first analysis information about account:

```bash
account partition: 802
```

Recall that we have created `account_ring` before we start Swfit. Our `account_ring` has `1024` partitions, with `replica=3`. From partition id `802`, we can obtian corresponding server that maintains metadata for this count.

Similarly, `ContainerController` also figures out the partition ID for `container1`, which is `244`. And we also obtain corresponding servers that is responsible for this container. Now, `ContainerController` sends requests to corresponding server to create container.

Then, where is the request served? It is `swift.container.server`. There is a method called `POST` inside this class that deals with incoming `POST` request. In this method, metadata for container is stored in disk.

Let's take a look at our disk after such operation:

```bash
$> tree /mnt/sdb1
/mnt/sdb1
├── 1
│   └── node
│       ├── sdb1
│       │   └── containers
│       │       └── 244
│       │           └── c78
│       │               └── 3d0c9366f2c6e55246f4c2a0469e5c78
│       │                   └── 3d0c9366f2c6e55246f4c2a0469e5c78.db
│       └── sdb5
├── 2
│   └── node
│       ├── sdb2
│       │   └── accounts
│       │       └── 802
│       │           └── 178
│       │               └── c8bcccab3ddbfdc34b08e9223f4f5178
│       │                   ├── c8bcccab3ddbfdc34b08e9223f4f5178.db
│       │                   └── c8bcccab3ddbfdc34b08e9223f4f5178.db.pending
│       └── sdb6
├── 3
│   └── node
│       ├── sdb3
│       │   ├── accounts
│       │   │   └── 802
│       │   │       └── 178
│       │   │           └── c8bcccab3ddbfdc34b08e9223f4f5178
│       │   │               ├── c8bcccab3ddbfdc34b08e9223f4f5178.db
│       │   │               └── c8bcccab3ddbfdc34b08e9223f4f5178.db.pending
│       │   └── containers
│       │       └── 244
│       │           └── c78
│       │               └── 3d0c9366f2c6e55246f4c2a0469e5c78
│       │                   └── 3d0c9366f2c6e55246f4c2a0469e5c78.db
│       └── sdb7
└── 4
    └── node
        ├── sdb4
        │   ├── accounts
        │   │   └── 802
        │   │       └── 178
        │   │           └── c8bcccab3ddbfdc34b08e9223f4f5178
        │   │               ├── c8bcccab3ddbfdc34b08e9223f4f5178.db
        │   │               └── c8bcccab3ddbfdc34b08e9223f4f5178.db.pending
        │   └── containers
        │       └── 244
        │           └── c78
        │               └── 3d0c9366f2c6e55246f4c2a0469e5c78
        │                   └── 3d0c9366f2c6e55246f4c2a0469e5c78.db
        └── sdb8

40 directories, 9 files

```

Note that 3 replication applies for both account metadata and container metadata.

**XL:** Do we need to figure out the format of these disk files?

##### upload object using default storage policy (replication)

```bash
$> swift upload container1 hello
```

This command upload a local file called `hello` to the container we just created previously (`container1`).

Similarly, `swift.proxy.server` figures out corresponding controller `ReplicatedObjectController` to deal with this request in method `PUT`. Inside this method, WSGI environment is responsible to read data from local disk. And `_store_object` is called to send data to corresponding servers that are responsible to deal with this object.

To deal with this request

After we upload this object, we can then check the our local disk:

```bash
/mnt/sdb1/
├── 1
│   └── node
│       ├── sdb1
│       │   ├── containers
│       │   │   └── 244
│       │   │       └── c78
│       │   │           └── 3d0c9366f2c6e55246f4c2a0469e5c78
│       │   │               ├── 3d0c9366f2c6e55246f4c2a0469e5c78.db
│       │   │               └── 3d0c9366f2c6e55246f4c2a0469e5c78.db.pending
│       │   └── objects
│       │       └── 111
│       │           ├── 89b
│       │           │   └── 1bcf675e369d6b96dad6e751d01c489b
│       │           │       └── 1539376573.41794.data
│       │           └── hashes.invalid
│       └── sdb5
├── 2
│   └── node
│       ├── sdb2
│       │   └── accounts
│       │       └── 802
│       │           └── 178
│       │               └── c8bcccab3ddbfdc34b08e9223f4f5178
│       │                   ├── c8bcccab3ddbfdc34b08e9223f4f5178.db
│       │                   └── c8bcccab3ddbfdc34b08e9223f4f5178.db.pending
│       └── sdb6
├── 3
│   └── node
│       ├── sdb3
│       │   ├── accounts
│       │   │   └── 802
│       │   │       └── 178
│       │   │           └── c8bcccab3ddbfdc34b08e9223f4f5178
│       │   │               ├── c8bcccab3ddbfdc34b08e9223f4f5178.db
│       │   │               └── c8bcccab3ddbfdc34b08e9223f4f5178.db.pending
│       │   ├── containers
│       │   │   └── 244
│       │   │       └── c78
│       │   │           └── 3d0c9366f2c6e55246f4c2a0469e5c78
│       │   │               ├── 3d0c9366f2c6e55246f4c2a0469e5c78.db
│       │   │               └── 3d0c9366f2c6e55246f4c2a0469e5c78.db.pending
│       │   └── objects
│       │       └── 111
│       │           ├── 89b
│       │           │   └── 1bcf675e369d6b96dad6e751d01c489b
│       │           │       └── 1539376573.41794.data
│       │           └── hashes.invalid
│       └── sdb7
└── 4
    └── node
        ├── sdb4
        │   ├── accounts
        │   │   └── 802
        │   │       └── 178
        │   │           └── c8bcccab3ddbfdc34b08e9223f4f5178
        │   │               ├── c8bcccab3ddbfdc34b08e9223f4f5178.db
        │   │               └── c8bcccab3ddbfdc34b08e9223f4f5178.db.pending
        │   ├── containers
        │   │   └── 244
        │   │       └── c78
        │   │           └── 3d0c9366f2c6e55246f4c2a0469e5c78
        │   │               ├── 3d0c9366f2c6e55246f4c2a0469e5c78.db
        │   │               └── 3d0c9366f2c6e55246f4c2a0469e5c78.db.pending
        │   └── objects
        │       └── 111
        │           ├── 89b
        │           │   └── 1bcf675e369d6b96dad6e751d01c489b
        │           │       └── 1539376573.41794.data
        │           └── hashes.invalid
        └── sdb8
```

##### read replicated-object

```bash
$> swift download container1 hello
```

Similarly, the download request is first sent to `swift.proxy.server`. The server figures out that this is a request for downloading an object. Thus `swift.proxy.controllers.obj.ReplicatedObjectController` deals with this request in the method `GET`. In this method, there is a parameter `concurrent=1`, which means that proxy only get data from one source node. How swift figures out where to download data from? `Ring`. Swift hashes the object name on the ring and get corresponding partitionID, with which a list of devices. In our example here, Swfit decides to download data from `127.0.0.1`. However, I haven't read code in detail which one swift should choose. (Actually, I test multiple times, and each time proxy get object from a different source node.)

On the other side, `swift.obj.server` deals with the request in `GET` method. It first figures out corresponding disk file and read content in the disk file to return.

#####write erasure-coded-object

OpenStack Swfit does not include codes for encoding and decoding data. It counts one external libraries for this purpose. PyECLib can be added as EC support to Swift.

```bash
$> git clone https://github.com/openstack/liberasurecode.git
$> sudo apt-get install build-essential autoconf automake libtool
$> cd liberasurecode
$> ./autogen.sh
$> ./configure
$> make
$> sudo make install
```

We first need to configure erasure coding storage policy:

```bash
[storage-policy:2]
name = ec42
policy_type = erasure_coding
ec_type = liberasurecode_rs_vand
ec_num_data_fragments = 4
ec_num_parity_fragments = 2
```

Then we create a container that is configured with erasure coding policy

```bash
$> swift post -H 'X-Storage-Policy: ec42' container1
$> swift upload container1 4M
```

This figure plots the whole process of uploading a object to swift with erasure coding policy:

![ecflow](ecflow.png)

As is the same with replicated-write operation, `swift.proxy.server` figures out that `proxy.controller.obj.ECObjectController` deals with request in `PUT` method. Furtherly, the method `_store_object` in class `ECObjectController` is called. And later on, `_transfer_data` is called. In this function, client data is cached into a sequence of `chunks`, each of which is `65536` bytes by default. To encode source data, a module called `chunk_transformer` get data chunks from cached chunks one by one and concatenated them into a segment (the default size is `1048576` bytes). Once there is enough data in a segment, `chunk_transformer`  calls the ec backend in `PyECLib` to encode a segment into `n` fragments, `k` out of which are source data fragments while the remainings are parity fragments. After encoding is finished, `n` data fragments are sent to `n` target storage nodes.

OpenStack Swift implements a `2-phase commmit` for erasure-coded-upload. However, I didn't go into the details for this part.

We can take a look at our disk after we upload a file with erasure coding.

```bash
/mnt/sdb1/
├── 1
│   └── node
│       ├── sdb1
│       │   ├── accounts
│       │   │   └── 802
│       │   │       └── 178
│       │   │           └── c8bcccab3ddbfdc34b08e9223f4f5178
│       │   │               ├── c8bcccab3ddbfdc34b08e9223f4f5178.db
│       │   │               └── c8bcccab3ddbfdc34b08e9223f4f5178.db.pending
│       │   ├── containers
│       │   │   └── 244
│       │   │       └── c78
│       │   │           └── 3d0c9366f2c6e55246f4c2a0469e5c78
│       │   │               ├── 3d0c9366f2c6e55246f4c2a0469e5c78.db
│       │   │               └── 3d0c9366f2c6e55246f4c2a0469e5c78.db.pending
│       │   └── objects-2
│       │       └── 341
│       │           ├── ea5
│       │           │   └── 5564ca7addd2096f6cbf7cfc31b8eea5
│       │           │       └── 1539593816.91886#1#d.data
│       │           └── hashes.invalid
│       └── sdb5
│           └── objects-2
│               └── 341
│                   ├── ea5
│                   │   └── 5564ca7addd2096f6cbf7cfc31b8eea5
│                   │       └── 1539593816.91886#5#d.data
│                   └── hashes.invalid
├── 2
│   └── node
│       ├── sdb2
│       │   ├── accounts
│       │   │   └── 802
│       │   │       └── 178
│       │   │           └── c8bcccab3ddbfdc34b08e9223f4f5178
│       │   │               ├── c8bcccab3ddbfdc34b08e9223f4f5178.db
│       │   │               └── c8bcccab3ddbfdc34b08e9223f4f5178.db.pending
│       │   ├── containers
│       │   │   └── 244
│       │   │       └── c78
│       │   │           └── 3d0c9366f2c6e55246f4c2a0469e5c78
│       │   │               ├── 3d0c9366f2c6e55246f4c2a0469e5c78.db
│       │   │               └── 3d0c9366f2c6e55246f4c2a0469e5c78.db.pending
│       │   └── objects-2
│       │       └── 341
│       │           ├── ea5
│       │           │   └── 5564ca7addd2096f6cbf7cfc31b8eea5
│       │           │       └── 1539593816.91886#0#d.data
│       │           └── hashes.invalid
│       └── sdb6
│           └── objects-2
│               └── 341
│                   ├── ea5
│                   │   └── 5564ca7addd2096f6cbf7cfc31b8eea5
│                   │       └── 1539593816.91886#4#d.data
│                   └── hashes.invalid
├── 3
│   └── node
│       ├── sdb3
│       │   ├── accounts
│       │   │   └── 802
│       │   │       └── 178
│       │   │           └── c8bcccab3ddbfdc34b08e9223f4f5178
│       │   │               ├── c8bcccab3ddbfdc34b08e9223f4f5178.db
│       │   │               └── c8bcccab3ddbfdc34b08e9223f4f5178.db.pending
│       │   └── containers
│       │       └── 244
│       │           └── c78
│       │               └── 3d0c9366f2c6e55246f4c2a0469e5c78
│       │                   ├── 3d0c9366f2c6e55246f4c2a0469e5c78.db
│       │                   └── 3d0c9366f2c6e55246f4c2a0469e5c78.db.pending
│       └── sdb7
│           └── objects-2
│               └── 341
│                   ├── ea5
│                   │   └── 5564ca7addd2096f6cbf7cfc31b8eea5
│                   │       └── 1539593816.91886#3#d.data
│                   └── hashes.invalid
└── 4
    └── node
        ├── sdb4
        └── sdb8
            └── objects-2
                └── 341
                    ├── ea5
                    │   └── 5564ca7addd2096f6cbf7cfc31b8eea5
                    │       └── 1539593816.91886#2#d.data
                    └── hashes.invalid
```

We can see from the names of each fragment that the erasure coding index is included in the disk file name.

##### degraded-read for erasure-coded object

```bash
$> swift download 4M 
```

`swift.proxy.server` tells `ECObjectController` to deal with the request in method `GET`. It sends out request to all the `n` servers one by one and once there is enough servers, it starts to decode. (**XL:** Actually, I haven't understand this part well. In the code, swift seems to collect several more than `k` servers each time in case something wierd happens. However I do not understand the internal logic in it.). `ECAppIter` is the module to perform decoding operation, which is inserted into swift code base as a `WSGI` application. The method `kickoff` in `ECAppIter` takes the responsibility. In this application, it fetches fragments from corresponding servers and call `_decode_segments_from_fragments` to decode the original segment. The method, `_decode_segments_from_fragments`, calls the ec backend in `PyECLib`.