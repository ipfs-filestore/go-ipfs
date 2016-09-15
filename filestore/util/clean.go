package filestore_util

import (
	"errors"
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"time"
	"strings"

	bs "github.com/ipfs/go-ipfs/blocks/blockstore"
	butil "github.com/ipfs/go-ipfs/blocks/blockstore/util"
	k "github.com/ipfs/go-ipfs/blocks/key"
	cmds "github.com/ipfs/go-ipfs/commands"
	"github.com/ipfs/go-ipfs/core"
	. "github.com/ipfs/go-ipfs/filestore"
	"github.com/ipfs/go-ipfs/pin"
	fsrepo "github.com/ipfs/go-ipfs/repo/fsrepo"
	//b58 "gx/ipfs/QmT8rehPR3F6bmwL6zjUN8XpiDBFFpMP2myPdC6ApsWfJf/go-base58"
)

func Clean(req cmds.Request, node *core.IpfsNode, fs *Datastore, quiet bool, what ...string) (io.Reader, error) {
	exclusiveMode := node.LocalMode()
	stages := 0
	to_remove := make([]bool, 100)
	incompleteWhen := make([]string, 0)
	for i := 0; i < len(what); i++ {
		switch what[i] {
		case "invalid":
			what = append(what, "changed", "no-file")
		case "full":
			what = append(what, "invalid", "incomplete", "orphan")
		case "changed":
			stages |= 0100
			incompleteWhen = append(incompleteWhen, "changed")
			to_remove[StatusFileChanged] = true
		case "no-file":
			stages |= 0100
			incompleteWhen = append(incompleteWhen, "no-file")
			to_remove[StatusFileMissing] = true
		case "error":
			stages |= 0100
			incompleteWhen = append(incompleteWhen, "error")
			to_remove[StatusFileError] = true
		case "incomplete":
			stages |= 0020
			to_remove[StatusIncomplete] = true
		case "orphan":
			stages |= 0003
			to_remove[StatusOrphan] = true
		default:
			return nil, errors.New("invalid arg: " + what[i])
		}
	}
	incompleteWhenStr := strings.Join(incompleteWhen,",")

	rdr, wtr := io.Pipe()
	var rmWtr io.Writer = wtr
	if quiet {
		rmWtr = ioutil.Discard
	}

	snapshot, err := fs.GetSnapshot()
	if err != nil {
		return nil, err
	}

	Logger.Debugf("Starting clean operation.")

	go func() {
		// 123: verify-post-orphan required
		// 12-: verify-full
		// 1-3: verify-full required (verify-post-orphan would be incorrect)
		// 1--: basic
		// -23: verify-post-orphan required
		// -2-: verify-full (cache optional)
		// --3: verify-full required (verify-post-orphan would be incorrect)
		// ---: nothing to do!
		var ch <-chan ListRes
		switch stages {
		case 0100:
			fmt.Fprintf(rmWtr, "performing verify --basic --level=6\n")
			ch, err = VerifyBasic(snapshot.Basic, &VerifyParams{
				Level:   6,
				Verbose: 1,
				NoObjInfo: true,
			})
		case 0120, 0103, 0003:
			fmt.Fprintf(rmWtr, "performing verify --level=6 --incomplete-when=%s\n",
				incompleteWhenStr)
			ch, err = VerifyFull(node, snapshot, &VerifyParams{
				Level:   6,
				Verbose: 6,
				IncompleteWhen: incompleteWhen,
				NoObjInfo: true,
			})
		case 0020:
			fmt.Fprintf(rmWtr, "performing verify --skip-orphans --level=1\n")
			ch, err = VerifyFull(node, snapshot, &VerifyParams{
				SkipOrphans: true,
				Level:       1,
				Verbose:     6,
				NoObjInfo: true,
			})
		case 0123, 0023:
			fmt.Fprintf(rmWtr, "performing verify-post-orphan --level=6 --incomplete-when=%s\n",
				incompleteWhenStr)
			ch, err = VerifyPostOrphan(node, snapshot, 6, incompleteWhen)
		default:
			// programmer error
			panic(fmt.Errorf("invalid stage string %d", stages))
		}
		if err != nil {
			wtr.CloseWithError(err)
			return
		}

		var toDel []k.Key
		for r := range ch {
			if to_remove[r.Status] {
 				key, err := k.KeyFromDsKey(r.Key)
				if err != nil {
					wtr.CloseWithError(err)
					return
				}
				toDel = append(toDel, key)
			}
		}
		ch2 := make(chan interface{}, 16)
		if exclusiveMode {
			rmBlocks(node.Blockstore, node.Pinning, ch2, toDel, Snapshot{}, fs)
		} else {
			rmBlocks(node.Blockstore, node.Pinning, ch2, toDel, snapshot, fs)
		}
		err2 := butil.ProcRmOutput(ch2, rmWtr, wtr)
		if err2 != nil {
			wtr.CloseWithError(err2)
			return
		}
		wtr.Close()
	}()

	return rdr, nil
}

func rmBlocks(mbs bs.MultiBlockstore, pins pin.Pinner, out chan<- interface{}, keys []k.Key,
	snap Snapshot, fs *Datastore) {

	debugCleanRmDelay()

	if snap.Defined() {
		Logger.Debugf("Removing invalid blocks after clean.  Online Mode.")
	} else {
		Logger.Debugf("Removing invalid blocks after clean.  Exclusive Mode.")
	}

	prefix := fsrepo.FilestoreMount

	go func() {
		defer close(out)

		unlocker := mbs.GCLock()
		defer unlocker.Unlock()

		stillOkay := butil.CheckPins(mbs, pins, out, keys, prefix)

		for _, k := range stillOkay {
			keyBytes := k.DsKey().Bytes()
			var origVal []byte
			if snap.Defined() {
				var err error
				origVal, err = snap.DB().Get(keyBytes, nil)
				if err != nil {
					out <- &butil.RemovedBlock{Hash: k.String(), Error: err.Error()}
					continue
				}
			}
			ok, err := fs.Update(keyBytes, origVal, nil)
			// Update does not return an error if the key no longer exist
			if err != nil {
				out <- &butil.RemovedBlock{Hash: k.String(), Error: err.Error()}
			} else if !ok {
				out <- &butil.RemovedBlock{Hash: k.String(), Error: "value changed"}
			} else {
				out <- &butil.RemovedBlock{Hash: k.String()}
			}
		}
	}()
}

// this function is used for testing in order to test for race
// conditions
func debugCleanRmDelay() {
	delayStr := os.Getenv("IPFS_FILESTORE_CLEAN_RM_DELAY")
	if delayStr == "" {
		return
	}
	delay, err := time.ParseDuration(delayStr)
	if err != nil {
		Logger.Warningf("Invalid value for IPFS_FILESTORE_CLEAN_RM_DELAY: %f", delay)
	}
	println("sleeping...")
	time.Sleep(delay)
}
