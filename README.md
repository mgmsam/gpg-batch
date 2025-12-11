[![Repository License](https://img.shields.io/badge/license-GPL%20v3.0-brightgreen.svg)](COPYING)

# GPG-Batch

Unattended key generation using one or more batch files.

This script extends the following features of batch mode:

- master key generation with multiple subkeys
- adding multiple subkeys to the master key
- setting the expiration date for each subkey individually

# Usage

To generate the master key:

```bash
./gpg-batch.sh [OPTION] [--] BATCHFILE ...
```

To generate additional subkeys to the existing master key:

```bash
./gpg-batch.sh [OPTION] --edit-key <key-ID> [--] BATCHFILE ...
```

Try `./gpg-batch.sh --help` for more information.

# Examples

## Generating a master key with multiple subkeys

1. Create a batch file with the options necessary for yourself. For example, `sample/ECC.batch`

   ```bash
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

   ```bash
   ./gpg-batch.sh --verbose sample/ECC.batch
   ```

3. List secret keys:

   ```bash
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

   ```bash
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

   ```bash
   ./gpg-batch.sh --verbose --edit-key 9A68BD144710FD28 sample/ELG.batch
   ```

3. List secret keys:

   ```bash
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

Items are arranged in order of priority from the lowest to the highest

- Use the script's STDIN:

  ```bash
  echo 'My passphrase' | ./gpg-batch.sh [OPTIONS] BATCHFILE ...
  ```

  or

  ```bash
  cat /tmp/gpg.pass | ./gpg-batch.sh [OPTIONS] BATCHFILE ...
  ```

  > Only the first line will be read from STDIN;

- Use the `passphrase` option in the options file:

  ```bash
  cat ~/gpg.options
  ```

  ```
  pinentry-mode loopback
  passphrase My passphrase
  ```

  Then run key generation:

  ```bash
  ./gpg-batch.sh [OPTIONS] --options ~/gpg.options [--] BATCHFILE ...
  ```

- Specify the passphrase in the arguments:

  ```bash
  ./gpg-batch.sh [OPTIONS] --passphrase "My passphrase" [--] BATCHFILE ...
  ```

- Save the passphrase to a file:

  ```bash
  cat /tmp/gpg.pass
  ```

  ```
  My passphrase
  ```

  > Only the first line will be read from file;

  - Specify the path to the passphrase file in the options file:

    ```bash
    cat ~/gpg.options
    ```

    ```
    passphrase-file /tmp/gpg.pass
    ```

    > the `~` - `gpg` extension is unsupported;

    Then run key generation:

    ```bash
    ./gpg-batch.sh [OPTIONS] --options ~/gpg.options [--] BATCHFILE ...
    ```

  - Specify the path to the passphrase file in the arguments:

    ```bash
    ./gpg-batch.sh [OPTIONS] --passphrase-file /tmp/gpg.pass [--] BATCHFILE ...
    ```

  - Specify the file descriptor containing the passphrase:

    ```bash
    cat /tmp/passphrase
    ```

    ```
    My passphrase
    ```

    Open the file descriptor:

    ```bash
    exec 5< /tmp/passphrase
    ```

    - Specify the file descriptor in the options file:

      ```bash
      cat ~/gpg.options
      ```

      ```
      passphrase-fd 5
      ```

      Then run key generation:

      ```bash
      ./gpg-batch.sh [OPTIONS] --options ~/gpg.options [--] BATCHFILE ...
      ```

    - Specify the file descriptor in the arguments:

      ```bash
      ./gpg-batch.sh [OPTIONS] --passphrase-fd 5 [--] BATCHFILE ...
      ```

    - The passphrase can be specified in the batch file as the first line before each master key:

      ```
      My passphrase 01

      Key-Type:      EdDSA
      Key-Curve:     ed25519
      Key-Usage:     cert

      Name-Real:     ECC
      Name-Comment:  Elliptic Curve Cryptography
      Name-Email:    test1@example.com

      Expire-Date:   1m

      Subkey-Type:   ECDH
      Subkey-Curve:  ed25519
      Subkey-Usage:  encrypt

      %commit
      My passphrase 02

      Key-Type:      EdDSA
      Key-Curve:     ed25519
      Key-Usage:     cert

      Name-Real:     ECC
      Name-Comment:  Elliptic Curve Cryptography
      Name-Email:    test2@example.com

      Subkey-Type:   ELG
      Subkey-Length: 4096
      Subkey-Usage:  Encrypt
      ```

      > _**WARNING:** Ensure the privacy of passphrases_
      >
      > If the line is empty, the key is generated without a passphrase.
      >
      > Pay attention to the required keyword `%commit`. If it is not specified, the line `My passphrase 02` will be included in the parameters of the first key.
      >
      > _**WARNING:** NOT TESTED !!!_

      Then run key generation:

      ```bash
      ./gpg-batch.sh [OPTIONS] --passphrase-fd 0 [--] BATCHFILE ...
      ```

    - The passphrase can be passed on STDIN:

      ```bash
      echo 'My passphrase' | ./gpg-batch.sh [OPTIONS] --passphrase-fd 0 [--] BATCHFILE ...
      ```

      > The passphrase is applied to all generated keys, but only if its own passphrase is not specified in the batch file using the `Passphrase:` parameter and the `%no-protection` parameter is absent; see further.

  When both `--passphrase-fd` and `--passphrase-file` are specified, the last discovered option takes precedence.

  The `--passphrase` option is only applied if both `--passphrase-fd` and `--passphrase-file` are absent, both in the arguments and in the options file.

- Specify the passphrase in the batch file:

  - *__`Passphrase:`__ My passphrase*

    > _**WARNING:** When using the `Passphrase:` parameter, you cannot specify a passphrase that begins or ends with whitespace characters._

  - *__`%no-protection`__*
            Using this option allows the creation of keys without any passphrase protection. This option is mainly intended for regression tests.
