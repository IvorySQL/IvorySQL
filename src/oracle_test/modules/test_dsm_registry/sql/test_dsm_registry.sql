SELECT name, type, size IS DISTINCT FROM 0 AS size
FROM pg_dsm_registry_allocations
WHERE name like 'test_dsm_registry%' ORDER BY name;
CREATE EXTENSION test_dsm_registry;
SELECT set_val_in_shmem(1236);
\c
SELECT get_val_in_shmem();
\c
SELECT name, type, size IS DISTINCT FROM 0 AS size
FROM pg_dsm_registry_allocations
WHERE name like 'test_dsm_registry%' ORDER BY name;
