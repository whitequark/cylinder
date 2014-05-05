Design of Cylinder
==================

Cylinder is a least-authority, distributed file synchronization engine. It runs on a cluster of hosts with loosely defined roles, which is semi-centralized for ease of deployment.

This document explains the design and rationale behind Cylinder's algorithms and protocols, layer by layer.

Cylinder uses only [Protocol Buffers][protobuf] for serialization, [NaCl][] (as [libsodium][]) for cryptography, and [ZeroMQ][] for transport.

The basic unit of identity in Cylinder is a client, i.e. a single installation of the Cylinder client with its unique Curve25519 keypair. There is no concept of an user.

All communication in Cylinder happens over an encrypted channel using the [CURVE][] authentication mechanism. Below, "client identity" refers to the public key of the client.

On the highest level, Cylinder has four host roles:

  * Blockserver, which logically stores all of the data and metadata in the system. It does not guarantee integrity or confidentiality, but only availability.

  Blockserver is unable to discern any structure in data stored on it except size, i.e. it sees it as a set of opaque blobs.

  Blockserver is stateless, so its job is distributed over multiple hosts.

  * Stateserver, which stores an authoritative reference to the most current state of the tree, and clears the blockserver from stale or orphan blocks. It too does not guarantee integrity or confidentiality.

  Stateserver is able to observe the filesystem structure, but not the data or metadata, i.e. it can discern which opaque blobs are changesets, directories, files, file content blocks and attribute them to clients, but not read the actual filenames, file contents, etc. Filesystem structure can be made opaque to stateserver in restricted use cases.

  Stateserver, as the name implies, is stateful. Currently it is a single point of failure.

  * Commserver, which is the endpoint to which clients connect, and which allows them to discover blockserver, stateserver and each other.

  Commserver only distributes endpoint addresses (but not public keys) and relays encrypted, authenticated messages between clients.

  Commserver is stateless, and its job can be distributed over multiple hosts, if necessary.

  * Client, which ensures confidentiality and integrity of data without trusting any other component of the system. It relies on an unbroken chain of signatures and distribution of keys through unrelated channels.

[protobuf]: https://developers.google.com/protocol-buffers/
[nacl]: http://nacl.cr.yp.to
[libsodium]: https://github.com/jedisct1/libsodium
[zeromq]: http://zeromq.org
[curve]: http://rfc.zeromq.org/spec:25

Blockserver
-----------

The blockserver provides a persistent value store. That is, it allows to store opaque objects of any size and retrieve them back by their digest. Additionally, it provides means to account for and reclaim storage space to the Stateserver.

The block size is limited by 16M.

The blockserver protocol is based on stateless request-reply. On a high level, it provides the following operations:

  * _get_: retrieve an object by its digest. Alternatively, signal that the object is not found.

  Client identity is not considered.

  * _put_: accept an object and ensure it is present in the store, returning a digest. Alternatively, signal that the storage space is exhausted or that the client has exceeded its quota.

  Client identity may be used to enforce disk quotas.

  * _erase_: remove an object by its digest.

  Client identity must belong to the stateserver.

  * _enumerate_: enumerate digests of all contained objects. No guarantees on order or completeness are provided.

  Client identity must belong to the stateserver.

### Rationale

#### Digest format

The blockserver digests consist of the hash function output together with the identifier of the hash function. While SHA-512 is considered safe today, it is not inconceivable that it will be broken later. When this happens, it is necessary to have a smooth migration path to another hash function, which would allow to reuse existing data.

As SHA-512 digests are 64 byte long, an alternative encoding for blocks shorter than 64 bytes exists that packs the actual data into the "digest". As the digest is necessary and enough to retrieve the data, this has no further implications to security.

#### Erasing data

A simplest persistent value store would only have the _put_ and _get_ commands. However, this ignores an important practical problem. That is, a malicious or malfunctioning client may fill the blockserver with garbage, and cause a denial of service.

The possible race conditions arising from the stateserver garbage collector erasing blocks are handled on the stateserver level. Thus, blockserver remains simple, stateless, and free to use any storage backend that can atomically write single objects.

#### Block size limit

ZeroMQ requires that the complete message could be fit into RAM. Thus, to prevent a memory exhaustion attack, it is necessary to reject clients attempting to push larger messages. It is thought that a maximal block size of 16M will provide reasonable performance.

#### Storage reliability

The blockserver does not attempt to provide a reliable storage mechanism on top of an unreliable one. The blockserver could be used with a wide range of existing backends, e.g.:

  * [Amazon S3](http://aws.amazon.com/s3/)
  * [Ceph](https://ceph.com/)
  * ...

### Protocol

Blockserver has a simple request-response protocol.

#### Digests

The blockserver digest is defined as follows:

``` protoc
message Digest {
  enum Type {
    Inline = 1;
    SHA512 = 2;
  }
  required Type   type    = 1;
  required string content = 2;
}
```

If `type = Inline`, `content` must be of same length or shorter than the output of the hash function with the longest output. Currently, that is SHA-512 with 64-byte output.

#### Request

The blockserver request is defined as follows:

``` protoc
message BlockserverReq {
  enum Type {
    Get       = 1; // of get_digest
    Put       = 2; // of put_object
    Erase     = 3; // of erase_digest
    Enumerate = 4; // of enumerate_marker
  }
  required Type type = 1;
  optional Digest get_digest       = 2;
  optional string put_object       = 3;
  optional Digest erase_digest     = 4;
  optional string enumerate_marker = 5;
}
```

#### Get

A valid _get_ request is a `BlockserverReq` with `type = Get` and only `get_digest` present.

The response is defined as follows:

``` protoc
message BlockserverGetResp {
  enum Result {
    Ok        = 1; // of object
    NotFound  = 2;
  }
  required Result result = 1;
  optional string object = 2;
}
```

The `object` field in `BlockserverGetResp` must only be present if `result = Ok`.

A client that sends a _get_ request must verify that the received object indeed has the digest that the client requires.

The blockserver will return `result = NotFound` for digests with `type = Inline`.

#### Put

A valid _put_ request is a `BlockserverReq` with `type = Put` and only `put_object` present.

The response is defined as follows:

``` protoc
message BlockserverPutResp {
  enum Result {
    Ok        = 1;
    Exhausted = 2;
  }
  required Result result = 1;
}
```

If `result = Exhausted`, the blockserver is out of storage space.

#### Erase

A valid _erase_ request is a `BlockserverReq` with `type = Erase` and only `erase_digest` present.

The response is defined as follows:

``` protoc
message BlockserverEraseResp {
  enum Result {
    Ok        = 1;
    Forbidden = 2;
  }
  required Result result = 1;
}
```

After an _erase_ request is executed, the storage will not contain the object identified by `digest` until it is restored by a corresponding _put_ request.

The blockserver will return `result = Ok` for digests with `type = Inline`.

#### Enumerate

A valid _erase_ request is a `BlockserverReq` with `type = Enumerate` and only `erase_digest` present.

The response is defined as follows:

``` protoc
message BlockserverEnumerateResp {
  enum Result {
    Ok        = 1; // of marker
    Exhausted = 2;
    Forbidden = 3;
  }
  message Listing {
    required string marker  = 1;
    repeated Digest digests = 2;
  }
  required Result  result  = 1;
  optional Listing listing = 2;
}
```

If `result = Ok`, `listing` must be set. Otherwise, `listing` must not be set. `listing.marker` is an opaque value that must be passed in a subsequent _enumerate_ request.

A set of requests to `enumerate` ending with an `Exhausted` response will return some (ideally, all) of the digests identifying objects contained on  the blockserver, but no guarantees on order or completeness of enumeration are provided.
