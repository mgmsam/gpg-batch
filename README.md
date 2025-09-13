# GPG-Batch

Unattended key generation using one or more batch files.

This script extends the following features of batch mode:

- master key generation with multiple subkeys
- adding multiple subkeys to the master key
- setting the expiration date for each subkey individually

# Usage

To generate the master key:

```shell
./gpg-batch.sh [OPTION] [--] BATCHFILE ...
```

To generate additional subkeys to the existing master key:

```shell
./gpg-batch.sh [OPTION] --edit-key <key-ID> [--] BATCHFILE ...
```

Try `./gpg-batch.sh --help` for more information.

# Examples

## Generating a master key with multiple subkeys

1. Create a batch file with the options necessary for yourself. For example, `sample/ECC.batch`

   ```shell
   cat sample/ECC.batch
   ```

   The contents of the file minus some comments:

   ```
   # This file is an example to demonstrate the features gpg-batch.sh.
   # Tested with GnuPG version 2.4.4
   # A detailed description of the parameters can be found
   # on the official website of the GnuPG project:
   #   https://www.gnupg.org/documentation/manuals/gnupg-devel/Unattended-GPG-key-generation.html

   %echo Generating an OpenPGP ECC (algo 22) key
   %echo ECC (Elliptic Curve Cryptography)

   Key-Type:      EdDSA
   Key-Curve:     ed25519
   Key-Usage:     cert

   Name-Real:     ECC
   Name-Comment:  Elliptic Curve Cryptography
   Name-Email:    test@example.com

   Expire-Date:   1m

   Subkey-Type:   ECDH
   Subkey-Curve:  ed25519
   Subkey-Usage:  encrypt

   Subkey-Type:   EdDSA
   Subkey-Curve:  ed25519
   Subkey-Usage:  auth
   Expire-Date:   2w

   Subkey-Type:   EdDSA
   Subkey-Curve:  ed25519
   Subkey-Usage:  sign
   Expire-Date:   1w

   Subkey-Type:   ECDH
   Subkey-Curve:  cv25519
   Subkey-Usage:  encrypt
   Expire-Date:   1d
   ```

2. Start generating the key:

   ```shell
   ./gpg-batch.sh --verbose sample/ECC.batch
   ```

3. List secret keys:

   ```shell
   gpg --list-secret-keys
   ```

   ```
   sec   ed25519/9A68BD144710FD28 2025-09-13 [C] [expires: 2025-10-13]
         108F380AD5251674FD00B7139A68BD144710FD28
   uid                 [ultimate] ECC (Elliptic Curve Cryptography) <test@example.com>
   ssb   ed25519/BA1C97BDABAA72D1 2025-09-13 [E] [expires: 2025-10-13]
   ssb   ed25519/CE701383F1B6A376 2025-09-13 [A] [expires: 2025-09-27]
   ssb   ed25519/6D31AE92B386BED8 2025-09-13 [S] [expires: 2025-09-20]
   ssb   cv25519/07EBF2F079ACD174 2025-09-13 [E] [expires: 2025-09-14]
   ```

## Generating additional subkeys for an existing master key

1. Create a batch file with the options necessary for yourself. For example, `sample/ELG.batch`:

   ```shell
   cat sample/ELG.batch
   ```

   The contents of the file minus some comments:
   ```
   # This file is an example to demonstrate the features gpg-batch.sh.
   # Tested with GnuPG version 2.4.4
   # A detailed description of the parameters can be found
   # on the official website of the GnuPG project:
   #   https://www.gnupg.org/documentation/manuals/gnupg-devel/Unattended-GPG-key-generation.html

   %echo Generating an OpenPGP ELG (algo 16) subkey
   %echo ELG (Taher A. Elgamal)

   %echo To apply this file, run the following command:
   %echo ./gpg-batch.sh --edit-key <key-ID> sample/ELG.batch

   Subkey-Type:   ELG
   Subkey-Length: 4096
   Subkey-Usage:  Encrypt
   Expire-Date:   1w

   Subkey-Type:   ELG
   Subkey-Length: 2048
   Subkey-Usage:  Encrypt
   Expire-Date:   1d
   ```

2. Start generating the subkey:

   ```shell
   ./gpg-batch.sh --verbose --edit-key 9A68BD144710FD28 sample/ELG.batch
   ```

3. List secret keys:

   ```shell
   gpg --list-secret-keys
   ```

   ```
   sec   ed25519/9A68BD144710FD28 2025-09-13 [C] [expires: 2025-10-13]
         108F380AD5251674FD00B7139A68BD144710FD28
   uid                 [ultimate] ECC (Elliptic Curve Cryptography) <test@example.com>
   ssb   ed25519/BA1C97BDABAA72D1 2025-09-13 [E] [expires: 2025-10-13]
   ssb   ed25519/CE701383F1B6A376 2025-09-13 [A] [expires: 2025-09-27]
   ssb   ed25519/6D31AE92B386BED8 2025-09-13 [S] [expires: 2025-09-20]
   ssb   cv25519/07EBF2F079ACD174 2025-09-13 [E] [expires: 2025-09-14]
   ssb   elg4096/CE93AC9437438F87 2025-09-13 [E] [expires: 2025-09-20]
   ssb   elg2048/5A1416A4A16E62DB 2025-09-13 [E] [expires: 2025-09-14]
   ```

## Enter a passphrase

- use the script's STDIN:

  ```shell
  echo 'My passphrase' | ./gpg-batch.sh [OPTIONS] BATCHFILE ...
  ```

  or

  ```shell
  cat /tmp/gpg.pass | ./gpg-batch.sh [OPTIONS] BATCHFILE ...
  ```

  > the passphrase can be empty

- specify passphrase in the batch file:

  *__Passphrase:__ string*

  > don't use a passphrase:
  > *%no-protection*

- specify in the options file:

  ```shell
  cat ~/gpg.options
  ```

  ```
  passphrase  My passphrase
  pinentry-mode loopback
  ```

  or save the passphrase in a file, such as `/tmp/gpg.pass` and specify the path to this file in the same options file:

  ```shell
  cat ~/gpg.options
  ```

  ```
  passphrase-file /tmp/gpg.pass
  pinentry-mode loopback
  ```

  > `passphrase-file` takes priority over `passphrase`;
  > the `~` - `gpg` extension is unsupported;

  then run key generation:

  ```shell
  ./gpg-batch.sh [OPTIONS] --options ~/gpg.options [--] BATCHFILE ...
  ```

  or

  ```shell
  ./gpg-batch.sh [OPTIONS] --options ~/gpg.options --edit-key <key-ID> [--] BATCHFILE ...
  ```
