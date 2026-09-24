-- Enables PostGIS before any schema migration that declares `geometry`
-- columns (ADR-017: SRID 4326, GiST indexes). Must run before the generated
-- schema migration, hence its position first in the journal.
CREATE EXTENSION IF NOT EXISTS postgis;
