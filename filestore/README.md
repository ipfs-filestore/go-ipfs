# Notes on the Filestore Datastore

The filestore is a work-in-progress datastore that stores the unixfs
data component of blocks in files on the filesystem instead of in the
block itself.  The main use of the datastore is to add content to IPFS
without duplicating the content in the IPFS datastore

## Quick start

To add a file to IPFS without copying, first bring the daemon offline
and then use `add --no-copy` or to add a directory use `add -r
--no-copy`.  (Throughout this document all command are assumed to
start with `ipfs` so `add --no-copy` really mains `ipfs add
--no-copy`).  For example to add the file `hello.txt` use:
```
  ipfs add --no-copy hello.txt
```

The file or directory will then be added.  You can now bring the
daemon online and try to retrieve it from another node such as the
ipfs.io gateway.

To add a file to IPFS without copying and the daemon online you must
first enable API.ServerSideAdds using:
```
  ipfs config API.ServerSideAdds --bool true
```
This will enable adding files from the filesystem the server is on.
*This option should be used with care since it will allow anyone with
access to the API Server access to any files that the daemon has
permission to read.* For security reasons it is probably best to only
enable this on a single user system and to make sure the API server is
configured to the default value of only binding to the localhost
(`127.0.0.1`).

With the API.ServerSideAdds option enabled you can add files using
`add-ss --no-copy`.  Since the file will read by the daemon the
absolute path must be specified.  For example, to add the file
`hello.txt` in the local directory use something like:
```
  ipfs add-ss --no-copy "`pwd`"/hello.txt
```

If the contents of an added file have changed the block will become invalid.
The filestore uses the modification-time to determine if a file has changed.
If the mod-time of a file differs from what is expected the contents
of the block are rechecked by recomputing the multihash and failing if
the hash differs from what is expected.

Adding files to the filestore will generally be faster than adding
blocks normally as less data is copied around.  Retrieving blocks from
the filestore takes about the same time when the hash is not
recomputed, when it is retrieval is slower.

## Verifying blocks

To list the contents of the filestore use the command `filestore ls`.
See `--help` for additional information.

Note that due to a known bug, datastore keys are sometimes mangled
(see [go-ipfs issue #2601][1]).  Do not be alarmed if you see keys
like `6PKtDkh6GvBeJZ5Zo3v8mtXajfR4s7mgvueESBKTu5RRy`.  The block is
still valid and can be retrieved by the unreported correct hash.
(Filestore maintenance operations will still function on the mangled
hash, although operations outside the filestore might complain of an
`invalid ipfs ref path`).

[1]: https://github.com/ipfs/go-ipfs/issues/2601

To verify the contents of the filestore use `filestore verify`.
See `--help` for additional info.

## Maintenance

Invalid blocks will cause problems with various parts of ipfs and
should be cleared out on a regular basis.  For example, `pin ls` will
currently abort if it is unable to read any blocks pinned (to get
around this use `pin ls -t direct` or `pin ls -r recursive`).  Invalid
blocks may cause problems elsewhere.

Currently no regular maintenance is done and it is unclear if this is
a desirable thing as I image the filestore will primary be used in
conjunction will some higher level tools that will automatically
manage the filestore.

All maintenance commands should currently be run with the daemon
offline.  Running them with the daemon online is untested, in
particular the code has not been properly audited to make sure all the
correct locks are being held.

## Removing Invalid blocks

The `filestore clean` command will remove invalid blocks as reported
by `filstore verify`.  You must specify what type of invalid blocks to
remove.  This command should be used with some care to avoid removing
more than is intended.  For help with the command use
`filestore clean --help`

Removing `changed` and `no-file` blocks (as reported by `filestore verify`
is generally a safe thing to do.  When removing `no-file` blocks there
is a slight risk of removing blocks to files that might reappear, for
example, if a filesystem containing the file for the block is not
mounted.

Removing `error` blocks runs the risk of removing blocks to files that
are not available due to transient or easily correctable (such as
permission problems) errors.

Removing `incomplete` blocks is generally a good thing to do to avoid
problems with some of the other ipfs maintenance commands such as the
pinner.  However, note that there is nothing wrong with the block
itself, so if the missing blocks are still available elsewhere
removing `incomplete` blocks is immature and might lead to lose of
data.

Removing `orphan` blocks like `incomplete` blocks runs the risk of
data lose if the root node is found elsewhere.  Also `orphan` blocks
do not cause any problems, they just take up a small amount of space.

## Fixing Pins

When removing blocks `filestore clean` will generally remove any pins
associated with the blocks.  However, it will not handle `indirect`
pins.  For example if you add a directory using `add -r --no-copy` and
some of the files become invalid the recursive pin will become invalid
and needs to be fixed.

One way to fix this is to use `filestore fix-pins`.  This will
remove any pines pointing to invalid non-existent blocks and also
repair recursive pins by making the recursive pin a direct pin and
pinning any children still valid.  

Pinning the original root as a direct pin may not always be the most
desirable thing to do, in which case you can use the `--skip-root` 
to unpin the root, but still pin any children still valid.

## Pinning and removing blocks manually.

The desirable behavior of pinning and garbage collection with
filestore blocks is unclear.  For now filestore blocks are pinned as
normal when added, but unpinned blocks are not garbage collected and
need to be manually removed.

To list any unpinned objects in the filestore use `filestore
unpinned`.  This command will list unpinned blocks corresponding to
whole files.  You can either pin them by piping the output into `pin
add` or manually delete them.

To manually remove blocks use `filestore rm`.  By default only blocks
representing whole files can be removed and the removal will be
recursive.  Direct and recursive pins will be removed along with the
block but `filestore rm` will abort if any indirect pins are detected.
To allow the removal of files with indirect pins use the `--force`
option.  Individual blocks can be removed with the `--direct` option.

## Duplicate blocks.

If a block is already in the datastore when adding and then readded
with `--no-copy` the block will be added to the filestore but the now
duplicate block will still exists in the normal datastore.
Furthermore, since the block is likely to be pinned it will not be
removed when `repo gc` in run.  This is nonoptimal and will eventually
be fixed.  For now, you can remove duplicate blocks by running
`filestore rm-dups`.