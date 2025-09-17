SELECT NOT(pg_numa_available()) AS skip_test \gset
\if :skip_test
SELECT COUNT(*) = 0 AS ok FROM pg_shmem_allocations_numa;
\quit
\endif

-- switch to superuser
\c -

SELECT COUNT(*) >= 0 AS ok FROM pg_shmem_allocations_numa;
