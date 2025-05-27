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

The script automatically detects storage type. Exporting `export HD_TYPE=hdd` will automatically use this env var instead of the auto-detected type.
