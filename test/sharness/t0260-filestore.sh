#!/bin/sh
#
# Copyright (c) 2014 Christian Couder
# MIT Licensed; see the LICENSE file in this repository.
#

test_description="Test filestore"

. lib/test-filestore-lib.sh
. lib/test-lib.sh

test_init_ipfs

test_add_cat_file "filestore add" "`pwd`"

test_post_add "filestore add" "`pwd`"

test_add_cat_5MB "filestore add" "`pwd`"

test_expect_success "fail after file move" '
    mv mountdir/bigfile mountdir/bigfile2
    test_must_fail ipfs cat "$HASH" >/dev/null
'

# check "ipfs filestore " cmd by using state left by add commands

cat <<EOF > ls_expect_all
QmQ8jJxa1Ts9fKsyUXcdYRHHUkuhJ69f82CF8BNX14ovLT
QmQNcknfZjsABxg2bwxZQ9yqoUZW5dtAfCK3XY4eadjnxZ
QmQnNhFzUjVRMHxafWaV2z7XZV8no9xJTdybMZbhgZ7776
QmSY1PfYxzxJfQA3A19NdZGAu1fZz33bPGAhcKx82LMRm2
QmSr7FqYkxYWGoSfy8ZiaMWQ5vosb18DQGCzjwEQnVHkTb
QmTFH6xrLxiwC7WRwou2QkvgZwVSdQNHc1uGfPDNBqH2rK
QmTbkLhagokC5NsxRLC2fanadqzFdTCdBB7cJWCg3U2tgL
QmTvvmPaPBHRAo2CTvQC6VRYJaMwsFigDbsqhRjLBDypAa
QmVr26fY1tKyspEJBniVhqxQeEjhF78XerGiqWAwraVLQH
QmWgZKyDJzixHydY5toiJ2EHFdDkooWJnvH5uixY4rhq2W
QmYNVKQFvW3UwUDGoGSS68eBBYSuFY8RVp7UTinkY8zkYv
QmZBe6brSjd2XBzAyqJRAYnNm3qRYR4BXk8Akfuot7fuSY
QmayX17gA63WRmcZkQuJGcDAv1hWP4ULpXaPUHSf7J6UbC
Qmb6wyFUBKshoaFRfh3xsdbrRF9WA5sdp62R6nWEtgjSEK
QmcZm5DH1JpbWkNnXsCXMioaQzXqcq7AmoQ3BK5Q9iWXJc
Qmcp8vWcq2xLnAum4DPqf3Pfr2Co9Hsj7kxkg4FxUAC4EE
QmeXTdS4ZZ99AcTg6w3JwndF3T6okQD17wY1hfRR7qQk8f
QmeanV48k8LQxWMY1KmoSAJiF6cSm1DtCsCzB5XMbuYNeZ
Qmej7SUFGehBVajSUpW4psbrMzcSC9Zip9awX9anLvofyZ
QmeomcMd37LRxkYn69XKiTpGEiJWRgUNEaxADx6ssfUJhp
QmfAGX7cH2G16Wb6tzVgVjwJtphCz3SeuRqvFmGuVY3C7D
QmfYBbC153rBir5ECS2rzrKVUEer6rgqbRpriX2BviJHq1
EOF

cat <<EOF > ls_expect
QmSr7FqYkxYWGoSfy8ZiaMWQ5vosb18DQGCzjwEQnVHkTb
QmVr26fY1tKyspEJBniVhqxQeEjhF78XerGiqWAwraVLQH
EOF

test_expect_success "testing filestore ls" '
  ipfs filestore ls -q -a | LC_ALL=C sort > ls_actual_all &&
  ipfs filestore ls -q | LC_ALL=C sort > ls_actual &&
  test_cmp ls_expect ls_actual
'
test_expect_success "testing filestore verify" '
  test_must_fail ipfs filestore verify > verify_actual &&
  grep -q "changed  QmVr26fY1tKyspEJBniVhqxQeEjhF78XerGiqWAwraVLQH" verify_actual &&
  grep -q "no-file  QmQ8jJxa1Ts9fKsyUXcdYRHHUkuhJ69f82CF8BNX14ovLT" verify_actual &&
  grep -q "incomplete QmSr7FqYkxYWGoSfy8ZiaMWQ5vosb18DQGCzjwEQnVHkTb" verify_actual
'

test_expect_success "tesing re-adding file after change" '
  ipfs filestore add "`pwd`"/mountdir/hello.txt &&
  ipfs filestore ls -q -a | grep -q QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN
'

cat <<EOF > ls_expect
QmSr7FqYkxYWGoSfy8ZiaMWQ5vosb18DQGCzjwEQnVHkTb
QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN
EOF

test_expect_success "tesing filestore clean invalid" '
  ipfs filestore clean invalid > rm-invalid-output &&
  ipfs filestore ls -q -a | LC_ALL=C sort > ls_actual &&
  test_cmp ls_expect ls_actual
'

cat <<EOF > ls_expect
QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN
EOF

test_expect_success "tesing filestore clean incomplete" '
  ipfs filestore clean incomplete > rm-invalid-output &&
  ipfs filestore ls -q -a | LC_ALL=C sort > ls_actual &&
  test_cmp ls_expect ls_actual
'

test_expect_success "re-added file still available" '
  ipfs cat QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN > expected &&
  test_cmp expected mountdir/hello.txt
'

test_expect_success "testing filestore rm" '
  ipfs filestore rm QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN
'

test_expect_success "testing file removed" '
  test_must_fail cat QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN > expected
'

#
# Duplicate block testing
#

test_expect_success "create duplicate blocks" '
  ipfs add mountdir/hello.txt &&
  ipfs filestore add "`pwd`"/mountdir/hello.txt
'

cat <<EOF > locate_expect0
QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN /blocks found
QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN /filestore found
EOF

test_expect_success "ipfs block locate" '
  ipfs block locate QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN > locate_actual0 &&
  test_cmp locate_expect0 locate_actual0
'

test_expect_success "testing filestore rm-dups" '
  ipfs filestore rm-dups > rm-dups-output &&
  grep -q "duplicate QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN" rm-dups-output &&
  ipfs cat QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN > expected &&
  test_cmp expected mountdir/hello.txt
'

cat <<EOF > locate_expect1
QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN /blocks error  blockstore: block not found
QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN /filestore found
EOF

test_expect_success "ipfs block locate" '
  ipfs block locate QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN > locate_actual1
  test_cmp locate_expect1 locate_actual1
'

#
# Duplicate block with pinning testing
#

test_expect_success "clean up from last test" '
  ipfs pin rm QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN &&
  ipfs filestore rm QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN
'

test_expect_success "create duplicate blocks" '
  ipfs add mountdir/hello.txt &&
  ipfs filestore add "`pwd`"/mountdir/hello.txt &&
  ipfs pin ls QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN &&
  ipfs block locate QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN > locate_actual0 &&
  test_cmp locate_expect0 locate_actual0
'

test_expect_success "ipfs block rm pinned but duplciate block" '
  ipfs block rm QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN
'

test_expect_success "ipfs block locate" '
  ipfs block locate QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN > locate_actual1
  test_cmp locate_expect1 locate_actual1
'

test_expect_success "ipfs filestore rm pinned block fails" '
  test_must_fail ipfs filestore rm QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN
'

#
# Pin related tests
#

clear_pins() {
    test_expect_success "clearing all pins" '
      ipfs pin ls -q -t recursive > pin_ls &&
      ipfs pin ls -q -t direct >> pin_ls &&
      cat pin_ls | xargs ipfs pin rm > pin_rm &&
      ipfs pin ls -q > pin_ls &&
      test -e pin_ls -a ! -s pin_ls
    '
}

cat <<EOF > add_expect
added QmQhAyoEzSg5JeAzGDCx63aPekjSGKeQaYs4iRf4y6Qm6w adir
added QmSr7FqYkxYWGoSfy8ZiaMWQ5vosb18DQGCzjwEQnVHkTb adir/file3
added QmVr26fY1tKyspEJBniVhqxQeEjhF78XerGiqWAwraVLQH adir/file1
added QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN adir/file2
EOF

clear_pins

test_expect_success "testing filestore add -r --pin" '
  mkdir adir &&
  echo "Hello Worlds!" > adir/file1 &&
  echo "HELLO WORLDS!" > adir/file2 &&
  random 5242880 41 > adir/file3 &&
  ipfs filestore add -r --pin "`pwd`"/adir | LC_ALL=C sort > add_actual &&
  test_cmp add_expect add_actual
'

test_expect_success "testing rm of indirect pinned file" '
  test_must_fail ipfs filestore rm QmZm53sWMaAQ59x56tFox8X9exJFELWC33NLjK6m8H7CpN
'

clear_pins

test_expect_success "testing filestore mv" '
  HASH=QmQHRQ7EU8mUXLXkvqKWPubZqtxYPbwaqYo6NXSfS9zdCc &&
  random 5242880 42 >mountdir/bigfile-42 &&
  ipfs add mountdir/bigfile-42 &&
  ipfs filestore mv $HASH mountdir/bigfile-42-also &&
  test_cmp mountdir/bigfile-42 mountdir/bigfile-42-also
'

test_expect_success "testing filestore mv result" '
  ipfs filestore verify -l9 > verify.out &&
  grep -q "ok \+QmQHRQ7EU8mUXLXkvqKWPubZqtxYPbwaqYo6NXSfS9zdCc " verify.out
'

#
# Additional add tests
#

cat <<EOF > add_expect
added QmbFMke1KXqnYyBBWxB74N4c5SBnJMVAiMNRcGu6x1AwQH emptyfile
EOF

test_expect_success "testing adding of empty file" '
  cat /dev/null > emptyfile
  ipfs filestore add "`pwd`"/emptyfile > add_actual &&
  test_cmp add_expect add_actual
'

test_add_cat_200MB "filestore add" "`pwd`"

test_done
