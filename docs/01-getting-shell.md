# Getting a shell

No exploit required. ASUS ships SSH; it is just switched off.

## Enable it

Web GUI → **Administration → System**:

- *Enable SSH* → `LAN only` to start with
- *Allow SSH port forwarding* → as you like
- Paste your public key into *Authorized Keys*
- Leave *Allow password login* on **until you have confirmed the key works**

Then, once you are in with the key:

    nvram set sshd_pass=0
    nvram commit

## dropbear is old, and it matters

The shipped dropbear is **2019.78**. Two practical limits:

**No ed25519.** Generate RSA:

    ssh-keygen -t rsa -b 4096 -f ~/.ssh/gtac5300

**No `rsa-sha2-*` signatures.** Modern OpenSSH clients disabled the old
`ssh-rsa` algorithm by default, so a correct key still fails with
*no mutual signature algorithm*. You must re-enable it client-side:

    Host router
      HostName 192.0.2.1
      User youruser
      IdentityFile ~/.ssh/gtac5300
      IdentitiesOnly yes
      HostKeyAlgorithms +ssh-rsa
      PubkeyAcceptedAlgorithms +ssh-rsa

Without those last two lines you will spend an hour convinced your key is
wrong. It is not.

## Confirm what you have

    # uname -a
    # nvram get buildno ; nvram get extendno
    # cat /proc/cpuinfo | grep -c processor
    # df -h /jffs

You should have a root prompt, four cores, and a writable `/jffs`.

## A word on the shell

It is busybox `ash`. It is not bash, and it is not a full POSIX shell either —
several standard utilities are simply absent (`uniq` is the one that will
surprise you). Read `99-gotchas.md` before you write anything non-trivial.
