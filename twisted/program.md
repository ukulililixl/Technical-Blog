# Twisted Programming

## Low level program

Here is the main function:

```python
def poetry_main():
    addresses = parse_args()

    start = datetime.datetime.now()

    sockets = [PoetrySocket(i + 1, addr) for i, addr in enumerate(addresses)]

    from twisted.internet import reactor
    reactor.run()

    elapsed = datetime.datetime.now() - start

    for i, sock in enumerate(sockets):
        print 'Task %d: %d bytes of poetry' % (i + 1, len(sock.poem))

    print 'Got %d poems in %s' % (len(addresses), elapsed)
```

We first see reactor.run() here, so we need to find where we add call backs previously. So we turn to read the code in PoedtrySocket constructor

Here is the constructor of SockPoetry

```python
class PoetrySocket(object):

    poem = ''

    def __init__(self, task_num, address):
        self.task_num = task_num
        self.address = address
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.connect(address)
        self.sock.setblocking(0)

        # tell the Twisted reactor to monitor this socket for reading
        from twisted.internet import reactor
        reactor.addReader(self)
```

I see **reactor.addReader(self)**, I'm very curious about this function. This function add an object to the reactor rather than a function. How does the reactor know what function it should call?

Now follow the tutorial, I open the file "/usr/local/lib/python2.7/dist-packages/twisted/internet/interface.py"

and find corresponding code here:

```python
class IReactorFDSet(Interface):
    """
    Implement me to be able to use L{IFileDescriptor} type resources.

    This assumes that your main-loop uses UNIX-style numeric file descriptors
    (or at least similarly opaque IDs returned from a .fileno() method)
    """

    def addReader(reader):
        """
        I add reader to the set of file descriptors to get read events for.

        @param reader: An L{IReadDescriptor} provider that will be checked for
                       read events until it is removed from the reactor with
                       L{removeReader}.

        @return: L{None}.
        """
```

What is IReadctorFDSet? It is an interface to implement a reactor. Any implementation of twisted.reactor should implement a function called "addReader". (In the previous code, we just call this function to add some callbacks)

In the function **addReader**, there is a parameter **reader**. From the documentation we can see that reader is of type **IReadDescriptor**. This indicates that the **SockPoetry** is not just a class, it should be of type **IReadDescriptor**. 



Then let's see how should **SockPoetry** to be like **IReadDescriptor**. Then we find the source code of **IReadDescriptor** :

```python
class IReadDescriptor(IFileDescriptor):
    """
    An L{IFileDescriptor} that can read.

    This interface is generally used in conjunction with L{IReactorFDSet}.
    """

    def doRead():
        """
        Some data is available for reading on your descriptor.

        @return: If an error is encountered which causes the descriptor to
            no longer be valid, a L{Failure} should be returned.  Otherwise,
            L{None}.
        """
```

This means that **SockPoetry** must implement **doRead** function to be of type **IReadDescriptor**. 



To sum up: We use **reactor.addReader(reader)** to add an object of IReadDescriptor ot the reactor. Actually, the reactor will call **reader.doRead**, this function is the callback function.



And this is not enough. **IReadDescriptor** is a childclass of **IFileDescriptor**, so our **SockPoetry** should also implement the interfaces in **IFileDescriptor**

```python
class IFileDescriptor(ILoggingContext):
    """
    A file descriptor.
    """
    def fileno():
        ...
    def connectionLost(reason):
        …
```

And we can also find implementations in our **SockPoetry**.



