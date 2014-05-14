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

The block size is limited by 10⁷ bytes.

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

ZeroMQ requires that the complete message could be fit into RAM. Thus, to prevent a memory exhaustion attack, it is necessary to reject clients attempting to push larger messages. It is thought that a maximal block size of 10⁷ bytes will provide reasonable performance.

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
  message Object {
    required Digest.Type digest_type = 1;
    required bytes       content     = 2;
  }
  required Type type = 1;
  optional Digest get_digest       = 2;
  optional Object put_object       = 3;
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
    Ok          = 1; // of object
    NotFound    = 2;
    Unavailable = 3;
  }
  required Result result = 1;
  optional bytes  object = 2;
}
```

The `object` field in `BlockserverGetResp` must only be present if `result = Ok`.

A client that sends a _get_ request must verify that the received object indeed has the digest that the client requires.

The blockserver will return `result = NotFound` for digests with `type = Inline`.

The blockserver will return `result = Unavailable` if it is unable to contact its backend.

#### Put

A valid _put_ request is a `BlockserverReq` with `type = Put` and only `put_object` present.

The response is defined as follows:

``` protoc
message BlockserverPutResp {
  enum Result {
    Ok           = 1;
    Unavaliable  = 2;
    NotSupported = 3;
  }
  required Result result = 1;
}
```

The blockserver will return `result = Unavailable` if the backend is temporarily unable to fulfill the request, e.g. if it is out of storage space or a network link is severed.

The blockserver will return `result = NotSupported` for digests with `type` equal to any hash function that it considers insecure, or with `type = Inline`.

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
    Ok        = 1; // of cookie
    Exhausted = 2;
    Forbidden = 3;
  }
  message Listing {
    required string cookie  = 1;
    repeated Digest digests = 2;
  }
  required Result  result  = 1;
  optional Listing listing = 2;
}
```

If `result = Ok`, `listing` must be set. Otherwise, `listing` must not be set. `listing.cookie` is an opaque value that must be passed in a subsequent _enumerate_ request.

A set of requests to `enumerate` ending with an `Exhausted` response will return some (ideally, all) of the digests identifying objects contained on  the blockserver, but no guarantees on order or completeness of enumeration are provided.

Filesystem structure
--------------------

At its core, Cylinder provides an implementation of a filesystem with persistent, immutable, authenticated data structures that supports atomic concurrent updates of arbitrarily large trees. There is no single point of responsibility for the integrity of the filesystem; both the server and the client verify that there is an unbroken chain of signatures between the old and the new state before accepting it.

The entire filesystem, data and metadata alike, is stored on the blockserver. This section explains the storage format and the invariants that ensure its integrity.

Chunks
------

A _chunk_ is the unit of storage of the file contents. When stored, a file is broken into several pieces, each no bigger than the maximum block size; the content may now be represented by a list of digests corresponding to said pieces. This allows to efficiently update large files.

In order to be able to deduplicate stored data, _convergent encryption_ is used. That is, the content of the chunk is symmetrically encrypted using a key derived from the content itself and a _convergence key_ using a hash function; this way, ciphertext only depends on cleartext and the convergence key.

It is only possible to access the data contained in a chunk using a _capability_. A capability consists of the digest of the ciphertext (which allows to retrieve the ciphertext from the blockserver) and the encryption key. Thus, a capability is necessary and sufficient to retrieve the cleartext.

This scheme is inspired by [Tahoe-LAFS][]; it is described in detail [in its documentation][convergence-secret].

[tahoe-lafs]: http://tahoe-lafs.org
[convergence-secret]: https://tahoe-lafs.org/trac/tahoe-lafs/browser/docs/convergence-secret.rst

### Rationale

#### Inline capabilities

A capability can be quite large--a capability with SHA512 digest and SHA512-XSalsa20-Poly1305 key takes 128 bytes to store. It makes no sense to upload smaller chunks of data to the blockserver, hence, they're stored inline in the capability.

#### Chunk mapping

A client can choose any chunk sizes or encodings it desires. This allows a client to optimize for cases where some parts of a huge file are rarely changing and some are changing frequently, or avoid costly compression on platforms which aren't fast enough.

### Storage format

#### Capability

```
message Capability {
  message Handle {
    enum Algorithm {
      SHA512_XSalsa20_Poly1305 = 1;
    }
    required Digest    digest    = 1;
    required Algorithm algorithm = 2;
    required bytes     key       = 3;
  }
  enum Type {
    Inline = 1;
    Stored = 2;
  }
  required Type   type   = 1;
  optional bytes  data   = 2;
  optional Handle handle = 3;
}
```

The `data` field must be present iff `type = Inline`. The `handle` field must be present iff `type = Stored`.

The `handle.key` field must have the length corresponding to `handle.algorithm`:

| `handle.algorithm`         | `length(handle.key)` |
| -------------------------- | -------------------- |
| `SHA512_XSalsa20_Poly1305` | 56                   |

#### Chunk data

```
message Chunk {
  enum Encoding {
    None = 1;
    LZ4  = 2;
  }
  required Encoding encoding = 1   [default=None];
  required bytes    content  = 15;
}
```

The `encoding` field specifies the transformation applied to `content` prior to serialization:

| `encoding` | Operation                |
| ---------- | ------------------------ |
| `None`     | Identity                 |
| `LZ4`      | Compression with [LZ4][] |

[lz4]: https://code.google.com/p/lz4/

### Algorithms

#### SHA512_XSalsa20_Poly1305

To encrypt, perform following:

  1. Let `clear_chunk` be a serialized `Chunk` message, and `key_conv` an externally selected convergence key.
  2. Let `hash` be `SHA512(key_conv || SHA512(clear_chunk))`. `hash` is 64 bytes long.
  3. Let `key` be bytes 0..31 of `hash`.
  4. Let `nonce` be bytes 32..55 of `hash`.
  5. Let `enc_chunk` be `Encrypt_XSalsa20_Poly1305(clear_chunk, key, nonce)` as described in [secretbox][].
  6. Let `capa_key` be bytes 0..55 of `hash`.

The block content is `enc_chunk`, and `Capability.handle.key` is `capa_key`.

To decrypt, perform following:

  1. Let `capa_key` be `Capability.handle.key`, and `enc_chunk` be `Chunk.content`.
  2. Let `key` be bytes 0..31 of `capa_key`.
  3. Let `nonce` be bytes 32.55 of `capa_key`.
  4. Let `clear_chunk` be `Decrypt_XSalsa20_Poly1305(enc_chunk, key, nonce)` as described in [secretbox][].

The serialized `Chunk` message is `clear_chunk`.

[box]: http://nacl.cr.yp.to/box.html
[secretbox]: http://nacl.cr.yp.to/secretbox.html

Secret box
----------

The following sections make use of an intermediate storage structure, encapsulating data encrypted with a secret-key algorithm

### Storage format

```
message SecretBoxKey {
  enum Algorithm {
    XSalsa20_Poly1305 = 1;
  }
  required Algorithm algorithm = 1;
  required bytes     key       = 2;
}

message SecretBox {
  required bytes data  = 1;
  required bytes nonce = 2;
}
```

Graph elements
--------------

A filesystem is a directed acyclic graph: directories point to files, files point to chunks. To aid processing by the stateserver, all non-leaf graph nodes are stored in a uniform format.

A graph element consists of the nested message and a list of blocks this message refers to. The entity creating the graph element is responsible for ensuring that the block list is consistent with the nested message.

The block list is encrypted using the stateserver's public key.

### Storage format

```
message EdgeList {
  repeated Digest edges = 1;
}

message GraphElement {
  required bytes content = 1;
  required bytes edges   = 2;
}
```

`GraphElement.edges` contains `EdgeList`, contained within a `Box` and encrypted with the public key of the stateserver.

### Algorithms

#### Curve25519_XSalsa20_Poly1305

As described in [box][].

Files
-----

A file is a graph element whose content consists of a list of chunks with the file contents and a list of attributes. Currently, the only attributes stored are the time of last modification and the *nix execute permission.

File element contents is encrypted with the checkpoint key (see below).

### Storage format

```
message File {
  required int64      last_modified = 1;
  required bool       executable    = 2 [default=false];
  repeated Capability chunks        = 15;
}
```

`File.last_modified` stores the number of milliseconds since 1970-01-01T00:00:00.000Z.

Directories
-----------

A directory is a graph element whose content consists of a list of nested files, directories and checkpoints.

Directory element contents is encrypted with the checkpoint key (see below).

### Storage format

```
message Directory {
  message Entry {
    enum Type {
      File       = 1;
      Directory  = 2;
      Checkpoint = 3;
    }
    required string name  = 1;
    required Type   type  = 2;
    required Digest block = 3;
  }
  repeated Entry contents = 1;
}
```

Checkpoints
-----------

A checkpoint is a graph element that demarcates a subgraph. It is a unit of access control policy and also a unit of atomic update. Checkpoints may be nested in directories and they themselves nest a single directory; a checkpoint _owns_ the transitive closure of files and directories (but not other checkpoints) embedded in it.

All of the elements owned by a checkpoint are encrypted with a secret key associated with that checkpoint. When the access control list is updated, the key is changed and all elements owned by the checkpoint are reencrypted with the new key.

The stateserver ensures that a checkpoint is updated consistently; it rejects checkpoint updates that do not refer to the most recent checkpoint block in the edge list. Similarly, it rejects checkpoint updates that violate the access control policy.
