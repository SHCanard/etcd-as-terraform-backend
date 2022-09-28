#!/bin/bash

date=`date +%d-%b-%Y`

#Perform a DB snapshot
ETCDCTL_API=3 /etcd/etcdctl snapshot save /etcd/backup/snapshot_$date.db

#Cleanup of old backups (more than 30 days)
find /etcd/backup -mtime +30 -delete;
