// package blockstore implements a thin wrapper over a datastore, giving a
// clean interface for Getting and Putting block objects.
package filestore_support

import (
	ds "github.com/ipfs/go-ipfs/Godeps/_workspace/src/github.com/ipfs/go-datastore"
	dsns "github.com/ipfs/go-ipfs/Godeps/_workspace/src/github.com/ipfs/go-datastore/namespace"
	blocks "github.com/ipfs/go-ipfs/blocks"
	bs "github.com/ipfs/go-ipfs/blocks/blockstore"
	fs "github.com/ipfs/go-ipfs/filestore"
)

type blockstore struct {
	bs.GCBlockstore
	//filestore fs.Datastore
	datastore ds.Batching
}

func NewBlockstore(b bs.GCBlockstore, d ds.Batching) bs.GCBlockstore {
	return &blockstore{b, dsns.Wrap(d, bs.BlockPrefix)}
}

func (bs *blockstore) Put(block blocks.Block) error {
	k := block.Key().DsKey()
	println("putting...")

	data := bs.prepareBlock(k, block)
	if data == nil {
		return nil
	}
	return bs.datastore.Put(k, data)
}

func (bs *blockstore) PutMany(blocks []blocks.Block) error {
	println("put many...")
	t, err := bs.datastore.Batch()
	if err != nil {
		return err
	}
	for _, b := range blocks {
		k := b.Key().DsKey()
		data := bs.prepareBlock(k, b)
		if data == nil {
			continue
		}
		err = t.Put(k, data)
		if err != nil {
			return err
		}
	}
	return t.Commit()
}

func (bs *blockstore) prepareBlock(k ds.Key, block blocks.Block) interface{} {
	if fsBlock, ok := block.(*blocks.FilestoreBlock); !ok {
		// Has is cheaper than Put, so see if we already have it
		exists, err := bs.datastore.Has(k)
		if err == nil && exists {
			return nil // already stored.
		}
		return block.Data()
	} else {
		println("DataObj")
		d := &fs.DataObj{
			FilePath: fsBlock.FilePath,
			Offset:   fsBlock.Offset,
			Size:     fsBlock.Size,
			ModTime:  fs.FromTime(fsBlock.ModTime),
		}
		if fsBlock.AltData == nil {
			d.Flags |= fs.WholeFile | fs.FileRoot
			d.Data = block.Data()
		} else {
			d.Flags |= fs.NoBlockData
			d.Data = fsBlock.AltData
		}
		return &fs.DataWOpts{d, fsBlock.AddOpts}
	}

}
