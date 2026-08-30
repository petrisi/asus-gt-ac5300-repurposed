# Getting a shell

No exploit required. ASUS ships SSH; it is just switched off.

## Enable it

Web GUI → **Administration → System**:

- *Enable SSH* → `LAN only` to start with
- *Allow SSH port forwarding* → as you like
- Paste your public key into *Authorized Keys*
- Leave *Allow password login* on **until you have confirmed the key works**

**Then commit it, or you will lose that key on the next reboot.** The GUI's
Apply writes running nvram and the `/root/.ssh/authorized_keys` derived from it,
but does not write to flash:

    nvram commit

This is not belt-and-braces. A key added through the GUI here worked for 15.8
days of uptime and vanished on the first reboot, restoring a key from the
original rooting months earlier — locking out the only remote access. `nvram
get` only ever shows the *running* value, so the sole way to verify persistence
is to actually reboot. See `99-gotchas.md`.

Once you are in with the key **and a reboot has proven it survives**:

    nvram set sshd_pass=0
    nvram commit

Keep password auth enabled until that reboot. It is the fallback that makes a
failed test cost nothing.

## dropbear is newer than it is usually given credit for

The shipped dropbear is **v2020.81** on firmware `3.0.0.4.386_51582`, and
`ssh-ed25519` and `curve25519-sha256` are both compiled in. So prefer:

    ssh-keygen -t ed25519 -f ~/.ssh/gtac5300

An ed25519 key needs **no client-side workarounds whatsoever** — verified with
`ssh -F /dev/null`, the entire exchange is modern:

    kex: curve25519-sha256
    host key: ssh-ed25519
    user key: ed25519

so the client config is simply:

    Host router
      HostName 192.0.2.1
      User youruser
      IdentityFile ~/.ssh/gtac5300
      IdentitiesOnly yes

It is also about 104 bytes against roughly 740 for a 4096-bit RSA key, which is
worth caring about because `sshd_authkeys` is one nvram variable holding every
authorised key.

**If you use RSA instead**, dropbear cannot produce `rsa-sha2-*` signatures, and
modern OpenSSH clients disabled the legacy `ssh-rsa` algorithm by default — so a
perfectly good key still fails with *no mutual signature algorithm*. You must
re-enable it client-side:

      HostKeyAlgorithms +ssh-rsa
      PubkeyAcceptedAlgorithms +ssh-rsa

Without those you will spend an hour convinced your key is wrong. It is not.
**ed25519 sidesteps the whole problem** and is the better default.

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
