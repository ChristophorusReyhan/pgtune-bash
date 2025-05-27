# pgtune-bash
Automatic PG Config inspired by [le0pard/pgtune](https://github.com/le0pard/pgtune) using bash script. As [le0pard/pgtune-about](https://pgtune.leopard.in.ua/about) said, "It isn't a silver bullet for the optimization settings of PostgreSQL", so tune further based on your case. 

Usage
=====
Omit environment variable as needed
```bash
export DB_TYPE=oltp
export DB_VERSION=16
export TOTAL_MEMORY=64
export MEMORY_UNIT=GB
export CPU_COUNT=16
export CONNECTIONS=1000
export HD_TYPE=hdd

bash generate_pgtune.sh
```

This script will use default settings / auto detects certain settings if you omit it. Exporting variables will automatically use those env var instead of the default.

The variables

1. DB_TYPE
default: dw (Data Warehouse)

2. DB_VERSION
default: 13

3. TOTAL_MEMORY
default: MemTotal of /proc/meminfo

4. MEMORY_UNIT
default: KB

5. CPU_COUNT
default: nproc

6. MAX_CONNECTIONS
default:
DB_TYPE web: 200
DB_TYPE oltp: 300
DB_TYPE dw: 40
DB_TYPE desktop: 20
DB_TYPE mixed: 100

7. HD_TYPE
default: /sys/block/$DEV_NAME/queue/rotational of root block device
