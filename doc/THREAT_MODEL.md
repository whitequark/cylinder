Threat model
============

Cylinder is designed and operates under three main assumptions:

  * Never trust the network. Anything that passes over a network is monitored, stored, and possibly mangled.
  * Never trust the storage. Anything you can store remotely will eventually leak and/or get corrupted, maliciously or not.
  * Never trust the endpoints. Endpoints *will* get compromised.

Cylinder deals with it.

(•_•)<br>
( •_•)>⌐■-■<br>
(⌐■_■)

Overview
--------

Cylinder is a distributed system for file storage and interactive synchronization. It includes two kinds of assets: filesystem content, i.e.: file content and directory structure, and filesystem metadata, i.e.: the identity of endpoints that have updated or have permissions to update the filesystem.

Cylinder is designed around the _principle of least authority_; that is, every node of the system is restricted to the bare minimum of the information it needs to operate using strong cryptography. Thus, when a node is compromised, the fallout is minimal.

Cylinder is also designed with the understanding that nodes will routinely be compromised. It provides facilities to perform rollover without interrupting normal operation of the network.

Storage structure
-----------------

TODO

Communication structure
-----------------------

The Cylinder nodes belong to one of three roles:

  * A _blockserver_ node is concerned with bulk storage of data. It allows storing and retrieving small chunks of data by its digest. A blockserver abstracts a reliable storage backend, thus providing availability guarantees, but not confidentiality or integrity ones.
  * A _stateserver_ node is concerned with coordination of other nodes. It tracks the most recent state of the filesystem, ensures that no data, including historical, is lost while updating the filesystem, reclaims unreferenced blocks, enforces disk quotas and sends out notifications to the devices. It guarantees availability and confidentiality of the client .
  * A _device_ node is concerned with retrieving and updating the filesystem, interacting with previous two in the process. It locally verifies integrity of the remotely stored filesystem and authorization of any updates.

The blockserver and stateserver nodes together form a _cluster_. Device nodes discover the structure of the cluster on startup by requesting it from any cluster node.

TODO
