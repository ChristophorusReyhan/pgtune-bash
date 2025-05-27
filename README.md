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

| Variable        | Default                                                     |
| --------------- | ----------------------------------------------------------- |
| **DB_TYPE**     | `dw` (Data Warehouse)                                       |
| **DB_VERSION**  | `13`                                                        |
| **TOTAL_MEMORY**| `MemTotal` value from `/proc/meminfo`                       |
| **MEMORY_UNIT** | `KB`                                                        |
| **CPU_COUNT**   | output of `nproc`                                           |
| **MAX_CONNECTIONS** | depends on DB_TYPE (see below)                                                       |
| **HD_TYPE**     | rotational flag from `/sys/block/$DEV_NAME/queue/rotational` of the root block device |

| DB_TYPE | MAX_CONNECTIONS |
| ------- | --------------- |
| web     | 200             |
| oltp    | 300             |
| dw      | 40              |
| desktop | 20              |
| mixed   | 100             |

