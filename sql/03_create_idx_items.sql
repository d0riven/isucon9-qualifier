DROP INDEX idx_category_id ON items;
CREATE INDEX category_created_at_id_idx ON items (category_id, created_at, id);