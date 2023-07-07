---
title: "PostgreSQL Database Tuning"
weight: 10
---

# XNAT Database Tuning Settings for PostgreSQL

If XNAT is performing poorly, such as very long delays when adding a Subjects
tab, it may be due to the small default Postgres memory configuration. 

To change the Postgres memory configuration to better match the available
system memory, add/edit the following settings in
`/etc/postgresql/10/opex/postgresql.conf`

  ```
  work_mem = 50MB
  maintenance_work_mem = 128MB
  effective_cache_size = 256MB
  ```

For further information see:
  - [https://wiki.xnat.org/workshop-2016/step-8-of-8-postgres-tuning-29032963.html](https://wiki.xnat.org/workshop-2016/step-8-of-8-postgres-tuning-29032963.html)
