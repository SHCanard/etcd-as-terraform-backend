# etcd-as-terraform-backend
How to install etcd as a terraform backend (but etcd is now depecrated for Terraform).
Here we will use a cluster of 3 servers, each server has a frontend (10.0.0.x) and a backend network (10.0.1.x).


Server preparation
--------

Disk carveout
```bash
mkdir /etcd
vgcreate -s 4M database /dev/sdb
lvcreate -n etcd -l 100%VG database
mkfs.xfs -K /dev/database/etcd
echo '/dev/database/etcd /etcd                xfs defaults 0 0 ' >> /etc/fstab
mount -a
```

Firewall setup
```bash
firewall-cmd --add-port 2379/tcp --permanent
firewall-cmd --add-port 2380/tcp --permanent
service firewalld reload
```

Generate certificates for each server and put them under /etcd/pki/certs (.pem) et /etcd/pki/keys (.key).
-	1 TLS Web Server certificate  « client to server » for terrabackv0xp / 10.0.0.x
-	1 TLS Web Server certificate « peer to peer » for 10.0.1.x

Create an etcd user which will launch etcd as a service. It will use /etcd/data as home directory.

```yaml
custom_groups:
  group1:
    name: "etcd"
    gid: "1501"

custom_users:
  user1:
    name: "etcd"
    uid: "1501"
    primary_group: "etcd"
    homedir: "/etcd/data"
    shell: "/bin/false"
```

```yaml
- name: Ensure local groups exists
  group:
    name: "{{ item.value.name }}"
    gid: "{{ item.value.gid }}"
    state: present
  with_dict: "{{ custom_groups }}"
  when: custom_groups is defined
  become: yes

- name: Ensure local users exists
  user: 
    name: "{{ item.value.name }}"
    state: present
    uid: "{{ item.value.uid }}"
    group: "{{ item.value.primary_group }}"
    home: "{{ item.value.homedir }}"
    shell: "{{ item.value.shell }}"
    append: yes
  with_dict: "{{ custom_users }}"
  when: custom_users is defined
  become: yes
```


etcd installation
--------

Downlad and install
```bash
ETCD_VER=v3.3.8
# choose either URL
GOOGLE_URL=https://storage.googleapis.com/etcd
GITHUB_URL=https://github.com/coreos/etcd/releases/download
DOWNLOAD_URL=${GITHUB_URL}
rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
rm -rf /tmp/test-etcd && mkdir -p /tmp/test-etcd
curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar xzvf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp/test-etcd --strip-components=1
sudo cp /tmp/test-etcd/etcd* /etcd
/etcd/etcd --version
ETCDCTL_API=3 /etcd/etcdctl version
```

Create the etcd service
```bash
systemctl edit etcd.service --force --full
```

And enter the following configuration
```bash
[Unit]
Description=etcd service
Documentation=https://github.com/coreos/etcd
 
[Service]
User=etcd
Type=notify
ExecStart=/etcd/etcd \
 --name serve01 \
 --data-dir /etcd/data \
 --initial-advertise-peer-urls https://10.0.1.1:2380 \
 --listen-peer-urls https://10.0.1.1:2380 \
 --listen-client-urls https://10.0.0.1:2379,http://127.0.0.1:2379 \
 --advertise-client-urls https://10.0.0.1:2379 \
 --initial-cluster-token terraformbackend \
 --initial-cluster serve01=https://10.0.1.1:2380,server02=https://10.0.1.2:2380,server03=https://10.0.1.3:2380 \
 --initial-cluster-state new \
 --heartbeat-interval 1000 \
 --election-timeout 5000 \
 --trusted-ca-file /etcd/pki/certs/rootCA.pem \
 --cert-file /etcd/pki/certs/client_cert.pem \
 --key-file /etcd/pki/keys/client_cert.key \
 --peer-client-cert-auth \
 --peer-trusted-ca-file /etcd/pki/certs/rootCA.pem \
 --peer-cert-file /etcd/pki/certs/peer_cert.pem \
 --peer-key-file /etcd/pki/keys/peer_cert.key
Restart=on-failure
RestartSec=5
 
[Install]
WantedBy=multi-user.target
```

Activate and start the service
```bash
systemctl daemon-reload
systemctl enable etcd
systemctl start etcd
/etcd/etcdctl cluster-health
```

If it fails chack permissions on the etcd user home directory
```bash
chown -R etcd:etcd /etcd/data
```

For an earsier administration, you can add the following lines to your .bashrc
```bash
export ETCDCTL_API=3
alias etcdctl="/etcd/etcdctl"
```

Maintenance
--------

To determine who is the node leader (v1)
```bash
/etcd/etcdctl member list
```
or (v3)
```bash
/etcd/etcdctl -w table --endpoints=https://10.0.0.1:2379,https://10.0.0.2:2379,https://10.0.0.3:2379 endpoint status
```

Backup (manual)
```bash
etcdctl snapshot save /etcd/backup/snapshot.db
```

Backup (scripted)
```bash
#!/bin/bash

date=`date +%d-%b-%Y`

#Perform a DB snapshot
ETCDCTL_API=3 /etcd/etcdctl snapshot save /etcd/backup/snapshot_$date.db

#Cleanup of old backups (more than 30 days)
find /etcd/backup -mtime +30 -delete;
```
