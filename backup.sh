#! /bin/bash

tar cvzf /tmp/pengzhangdev.github.io.tgz -C ../ pengzhangdev.github.io
scp /tmp/pengzhangdev.github.io.tgz root@192.168.31.100:/mnt/mmc/backup/
